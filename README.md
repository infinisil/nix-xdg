# [WIP] Nix overlay for making programs xdg compliant

This repo contains a nixos module (also usable with home-manager) for making
programs xdg compliant, by wrapping the binaries with certain environment
variables set or certains flags passed. Created the first draft in early 2017,
but only just got it to a usable state, motivated by
https://github.com/rycee/home-manager/issues/95.

All of it is done with a manual
specification for each program, which looks something like this:

```nix
{
  wget.flags = { cache }: "--hsts-file=${cache}/hsts";
  less.env.ZDOTDIR = { config }: config;
}
```

This spec defines that all binaries in the wget package be wrapped with the
"--hsts-file" flag set to a file in the packages cache directory, which is
`${XDG_CACHE_HOME:-$HOME/.cache}/wget` in this case, evaluating to
`~/.cache/wget` at runtime if `XDG_CACHE_HOME` isn't set. Second, all binaries
in the zsh package be wrapped with `ZDOTDIR` set to the packages config
directory, which is `${XDG_CONFIG_HOME:-$HOME/.config}/zsh`. Similarly, you can
use a `data` argument for getting
`${XDG_DATA_HOME:-$HOME/.local/share}/<name>`.

The `specs.nix` file contains some more examples. Also supported is wrapping
specific binaries (for packages containing multiple binaries) and changing the
folder name of the package directories (maybe useful for different versions). By
default, the top-level attributes name (`"wget"` and `"less"` in the above
example is used to get the package to wrap, this can be made explicit with
`package` attribute. The following example demonstrates these features (along
with some others):

```nix
{
  myHello = {
    # Use the hello package, since `pkgs.myHello` doesn't exist
    package = pkgs.hello;

    # This will make the config argument be
    # "${XDG_CONFIG_HOME:-$HOME/.config}/hithere", and similarily for cache and
    # data
    xdgName = "hithere";

    # Wrapping the hello binary only
    bin.hello.env.HELLO_DATA = { data }: data;

    # Such a function can occur anywhere _within_ the packages spec, and the
    arguments will contain the packages directories
    env = { config }: {
      # This will apply for all binaries except the hello one, since HELLO_DATA
      # is explicitly specified for it already.
      HELLO_DATA = "$HOME/.hello";
      HELLO_CONFIG = config;
    };
  };
}
```

# How to use

Import the `module.nix` file in your NixOS or home-manager configuration, by
either cloning this repository and adding

```nix
{
  imports = [
    ~/path/to/module.nix
  ];
}
```

or with nix directly:

```nix
{
  imports = [
    (builtins.fetchTarBall https://github.com/Infinisil/xdg-nix/archive/master.tar.gz)
  ];
}
```

By default no specs are added.

## Adding specs

You can add specifications by declaring them in the `xdgSpec` option like

```nix
{
  xdgSpec = {
    wget.flags = { cache }: "--hsts-file=${cache}/hsts";
  };
}
```

All attributes in the `specs.nix` file are available through an optional
argument. For example you can include the base set like this:

```nix
{
  xdgSpec = specs: specs.base;
}
```

## Using packages

To actually use the wrapped package, you'll have to specify it somewhere in your
nixos / home-manager config, such as

```nix
{
  # NixOS
  environment.systemPackages = with pkgs; [ wget ];

  # home-manager
  home.packages = with pkgs; [ wget ];
}
```


## Avoiding rebuild of dependent packages

Since the wrapped packages differ, other packages dependent on these will be
rebuilt when adding/changing the spec, which is unavoidable if you really want
to use overlays and have the changes propagate.
To avoid having to do that, you can include the package in your
packages directly, which is mostly just what you need:

```nix
{ config, ... }:
let
  xdg = import <nixpkgs> {
    overlays = [ (config.lib.xdg.xdgOverlay {
      specs = foo: foo.all;
    })];
  };
in {
  # NixOS
  environment.systemPackages = with xdg; [ curl ];

  # home-manager
  home.packages = with xdg; [ curl ];
}
```

# ToDo

- Split into more files, add default.nix, support for just importing the
  functions, add overlay.nix
- Overlay rebuilds a lot, but most often you just want changes in the user
  profiles packages anyways -> what to use instead of an overlay to not make it
  ugly?
- Potential home-manager integration, see https://github.com/rycee/home-manager/issues/95
