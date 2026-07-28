# Global git hooks for the emacs dired/dirvish refresh.
#
# ~/.config/git-hooks (what core.hooksPath in dotfiles/jappie/.gitconfig
# points at) is provided declaratively through home-manager; the
# install-nixos.sh symlink scheme is not used for this, that script is
# being phased out.
#
# Decision: mkOutOfStoreSymlink to the live checkout at /linux-config
# instead of a plain xdg.configFile source. A plain source copies the
# hooks into the nix store, so every hook edit would need a rebuild;
# the out-of-store symlink keeps ~/.config/git-hooks pointing at the
# working tree, the same live-editing behaviour the other dotfiles get
# from their symlinks. Cost: the path /linux-config is hardcoded, which
# install-nixos.sh already assumes everywhere else.
{ ... }:
let
  sources = import ../npins;
in
{
  imports = [ (sources.home-manager + "/nixos") ];

  home-manager.users.jappie = { config, ... }: {
    xdg.configFile."git-hooks".source =
      config.lib.file.mkOutOfStoreSymlink
        "/linux-config/dotfiles/jappie/.config/git-hooks";
  };
}
