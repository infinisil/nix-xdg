{ pkgs, config, lib, ... }:

with builtins;
with lib;

let

  print = v: trace v v;

  /* Recursively apply a set of arguments set when encountering
    a function in the given attrset while collecting all used arguments.

    Note: If a function that doesn't specify its arguments attribute names is
    encountered, it is assumed that all arguments are used.

    Note: Derivations are not recursed into.

    Example: 
      x = { a }: {
        y.z = { b }: [ a b ];
      }
      recApplyCollectArgs { a = "A"; b = "B"; c = "C"; } x
      => {
        args = { a = "A"; b = "B"; };
        result = { y = { z = [ "A" "B" ]; }; };
      }
  */
  recApplyCollectArgs = args: value:
  if isFunction value then
    let
      usedArgs' = intersectAttrs (functionArgs value) args;
      usedArgs = if usedArgs' == {} then args else usedArgs';
      sub = recApplyCollectArgs args (value usedArgs);
    in {
      inherit (sub) result;
      args = sub.args // usedArgs;
    }
  else if !isAttrs value || isDerivation value then
    {
      result = value;
      args = {};
    }
  else
    let
      sub = mapAttrs (n: v: recApplyCollectArgs args v) value;
    in {
      result = mapAttrs (n: v: v.result) sub;
      args = foldl (a: b: a // b) {}
        (mapAttrsToList (n: v: v.args) sub);
    };

  # Wraps a single binary
  wrap = {
    input, output,
    # List of strings
    dirs ? [],
    # List of strings or a single string
    flags ? [],
    # List of attrsets, later ones override earlier ones
    env ? []
  }:
  if dirs == [] && flags == [] && env == []
  then "ln -sv ${input} ${output}"
  else let
    dirWrap = optionalString (dirs != [])
      "--run 'mkdir -p ${
        concatMapStringsSep " " (dir: "\"${dir}\"") dirs
      }'";

    envWrap = concatStringsSep " "
      (mapAttrsToList (var: val: "--set '${var}' '${val}'")
      (foldl (a: b: a // b) {} env));

    flagWrap = concatMapStringsSep " "
      (flag: "--add-flags '${flag}'") (toList flags);
  in "makeWrapper ${input} ${output} ${dirWrap} ${envWrap} ${flagWrap}";

  /* Wraps a single program according to the spec argument, which should
  represent an XDG wrapping behaviour.

  For examples see below
  */
  wrapXDG = { base ? {}, name, spec, pkgs }:
  let
    xdgName = spec.xdgName or name;
    xdgDirs = {
      cache = base.cache or "\${XDG_CACHE_HOME:-$HOME/.cache}/${xdgName}";
      config = base.config or "\${XDG_CONFIG_HOME:-$HOME/.config}/${xdgName}";
      data = base.data or "\${XDG_DATA_HOME:-$HOME/.local/share}/${xdgName}";
    };
    package = spec.package or pkgs.${name};

    spec' = recApplyCollectArgs xdgDirs spec;
    mods = { env = {}; flags = []; bin = {}; }
      // spec'.result;
    dirs = attrValues spec'.args;
    
    wrapBin = { name, extraFlags ? [], extraEnv ? [] }: wrap {
      input = "${package}/bin/${name}";
      output = "$out/bin/${name}";
      inherit dirs;
      flags = toList mods.flags ++ toList extraFlags;
      env = toList mods.env ++ toList extraEnv;
    };
  in
    pkgs.runCommand "${package.name}-xdg" {
      buildInputs = [ pkgs.makeWrapper ];
      preferLocalBuild = true;
      allowSubstitutes = false;
    } ''
      mkdir $out
      ln -s ${package}/* $out
      rm $out/bin && mkdir $out/bin
      echo wrapping ${package.name} for XDG spec: '${toJSON spec'}'
      for b in ${package}/bin/*; do
        name=$(basename $b)
        ${wrapBin { name = "$name"; }}
      done
      ${concatMapStringsSep "\n" (name: ''
        rm $out/bin/${name}
        ${wrapBin {
          inherit name;
          extraFlags = mods.bin.${name}.flags or [];
          extraEnv = mods.bin.${name}.env or [];
        }}
      '') (attrNames mods.bin)}
    '';

  # This is a stupidly overspecified spec to just show what's possible
  exampleSpecs = {

    # name of the resulting attribute
    complicated = {
      # Package to wrap, default is pkgs.complicated
      package = pkgs.hello;
      # xdg directory name to use
      xdgName = "compl";
      # Wrap specific binaries
      # data dir will be ${XDG_DATA_HOME:-$HOME/.local/share}/compl
      bin = { data }: {
        # Wrap the "hello" binary with an env var set
        hello.env = { config }: {
          # Set HELLOFILE to ${XDG_CONFIG_HOME:-$HOME/.config}/compl/greetings
          HELLOFILE = "${config}/greetings";
        };
      };

      # Wrap every binary of the package with the "--version" flag
      flags = { config }: [ "--version" ];

      # Wrap with HELLOFILE set, has lower precedence than the specific binary
      # setting, so this won't do anything for the hello binary
      env.HELLOFILE = "hello";

      # This will work though, since FOO hasn't been set for the hello binary
      env.FOO = "foo";

      # Using the cache argument in any attribute makes it create the cache dir
      # when the binary is being run
      extraDirs = { cache }: null;
    };

  };

  xdgOverlay = { base ? {}, specs }: self: pkgs:
    let
      specs' = if isFunction specs then specs (import ./specs.nix) else specs;
    in flip mapAttrs specs' (name: spec:
    wrapXDG { inherit base pkgs name spec; });

in

{

  options.xdgSpec = mkOption {
    type = types.attrsOf types.unspecified;
    description = "xdg specification";
    default = {};
  };

  config = {
    nixpkgs.overlays = singleton (xdgOverlay { specs = config.xdgSpec; });

    lib.xdg = {
      inherit wrapXDG xdgOverlay;
    };
  };
}
