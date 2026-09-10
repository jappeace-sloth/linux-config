let
  sources = import ./npins;
  evalConfig = import (sources.nixpkgs + "/nixos/lib/eval-config.nix");
in
{
  work-machine = evalConfig {
    system = "x86_64-linux";
    modules = [ ./work-machine.nix ];
  };
  lenevo-amd-2022 = evalConfig {
    system = "x86_64-linux";
    modules = [ ./lenovo-amd-2022.nix ];
  };
  lenovo-tablet = evalConfig {
    system = "x86_64-linux";
    modules = [ ./lenovo-tablet.nix ];
  };

  # nix-build -A emacs-tests
  # Loads emacs.el headlessly and runs emacs/emacs-test.el against it, so a
  # change that stops the config loading fails here rather than at login.
  emacs-tests = import ./emacs/tests.nix { };
}
