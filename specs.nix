let

  base = {
    wget.flags = { cache }: "--hsts-file=${cache}/hsts";
    tig.extra = { config, data }: null;
    zsh.env.ZDOTDIR = { config }: config;
    irssi.flags = { config }: "--home=${config}";
    less.env.LESSHISTFILE = { data }: data;
    weechat.env.WEECHAT_HOME = { config }: config;
  };

  rebuildalot = {
    curl.env.CURL_HOME = { config }: config;
    gnupg.GNUPGHOME = { config }: config;
  };

in {

  inherit base rebuildalot;

  all = base // rebuildalot;

}
