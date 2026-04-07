{
  pkgs,
  lib,
  config,
  ...
}:

{
  process.managers.process-compose.tui.enable = false;
  cachix.enable = false;

  languages = {
    elixir = {
      enable = true;
      package = pkgs.elixir_1_19;
    };
  };

  packages =
    with pkgs;
    [
      gnumake
      gcc
    ]
    ++ lib.optionals pkgs.stdenv.isLinux [ inotify-tools ];

  git-hooks.hooks = {
    mix-format = {
      enable = !config.devenv.isTesting;
      name = "mix-format";
      files = ".ex[s]?$";
      entry = "mix format";
    };
    mix-test = {
      enable = !config.devenv.isTesting;
      name = "mix-test";
      entry = "mix test";
      pass_filenames = false;
    };
    mix-compile = {
      enable = !config.devenv.isTesting;
      name = "mix-compile";
      entry = "mix compile --warnings-as-errors";
      pass_filenames = false;
      stages = [ "pre-commit" ];
      files = ".ex[s]?$";
    };

    nixfmt-rfc-style.enable = !config.devenv.isTesting;
  };
}
