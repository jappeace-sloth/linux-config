# config for just nix
{ pkgs, ... }:
let
  sources = import ../npins;

  # After every successful build, push the result and its full closure
  # (including build-time dependencies like cross-GHC) to the binary cache.
  # Uses jappie's SSH key since the nix daemon runs as root.
  pushToCacheScript = pkgs.writeShellScript "push-to-binary-cache" ''
    set -uf
    export NIX_SSHOPTS="-i /home/jappie/.ssh/id_ed25519 -o StrictHostKeyChecking=accept-new"

    # Runtime closure of the outputs
    RUNTIME=$(${pkgs.nix}/bin/nix-store -qR $OUT_PATHS 2>/dev/null) || true

    # Build-time dependencies: for each output, find its deriver (.drv),
    # query the .drv's immediate input derivations, map them to their
    # output paths, and include those that exist in the store.
    BUILD=""
    for out in $OUT_PATHS; do
      DRV=$(${pkgs.nix}/bin/nix-store -qd "$out" 2>/dev/null) || continue
      # Get input derivation paths, then resolve each to its output
      for inputDrv in $(${pkgs.nix}/bin/nix-store -qR "$DRV" 2>/dev/null | grep '\.drv$'); do
        for inputOut in $(${pkgs.nix}/bin/nix-store -q --outputs "$inputDrv" 2>/dev/null); do
          if [ -e "$inputOut" ]; then
            BUILD="$BUILD $inputOut"
            # Include the runtime closure of each build dep too
            BUILD="$BUILD $(${pkgs.nix}/bin/nix-store -qR "$inputOut" 2>/dev/null)" || true
          fi
        done
      done
    done

    # Deduplicate
    PATHS=$(echo "$RUNTIME $BUILD" | tr ' ' '\n' | sort -u | grep '^/nix/store/' || true)
    COUNT=$(echo "$PATHS" | wc -w)
    echo "pushing $COUNT paths to binary cache" >&2

    echo "$PATHS" | xargs ${pkgs.nix}/bin/nix copy --to ssh-ng://root@videocut.org 2>&1 || \
      echo "WARNING: failed to push to binary cache" >&2
  '';
in
{
  nixpkgs.overlays = [
    # Use lix from nixpkgs-lix pin (matching haskell-vibes container)
    # to ensure ssh-ng protocol compatibility for remote nix builds
    (final: _: {
      nix = (import sources.nixpkgs-lix {}).lix;
    })
    (import sources.emacs-overlay)

    (import (sources.leana-dotfiles + "/nix/overlays/nix-monitored.nix"))
  ];

  # make sure the nix daemon uses all memory
  systemd.services.nix-daemon.serviceConfig = {
    MemoryAccounting = true;
    MemoryMax = "90%";
    OOMScoreAdjust = 500;
  };

  nix = {
    gc = {
      automatic = true;
      dates = "monthly"; # https://jlk.fjfi.cvut.cz/arch/manpages/man/systemd.time.7
      options = "--delete-older-than 120d";
    };

    nixPath = [
      "nixos-config=/etc/nixos/configuration.nix"
      "nixpkgs=${sources.nixpkgs}"
      "bloob=/home/jappie/projects/cut-the-crap"
    ];

    extraOptions = ''
      experimental-features = nix-command flakes
      extra-deprecated-features = url-literals
    '';
    settings = {

      # starts the gc when there is less then 50GB in storage
      min-free = 20 * 1024 * 1024 * 1024;

      trusted-users = [
        "root"
        # "nix-builder" # interesting claude wants this.
      ];
      extra-substituters = [
        "https://cache.nixos.org"
        "https://nixcache.reflex-frp.org" # reflex
        "https://jappie.cachix.org"
        "https://nix-community.cachix.org"
        "https://nix-cache.jappie.me"
        # "https://cache.iog.io"
        # "https://static-haskell-nix.cachix.org"
      ];

      extra-trusted-public-keys = [
        "ryantrinkle.com-1:JJiAKaRv9mWgpVAz8dwewnZe0AzzEAzPkagE9SP5NWI=" # reflex
        "static-haskell-nix.cachix.org-1:Q17HawmAwaM1/BfIxaEDKAxwTOyRVhPG5Ji9K3+FvUU="
        "jappie.cachix.org-1:+5Liddfns0ytUSBtVQPUr/Wo6r855oNLgD4R8tm1AE4="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nix-cache.jappie.me:WjkKcvFtHih2i+n7bdsrJ3HuGboJiU2hA2CZbf9I9oc="
      ];
      post-build-hook = "${pushToCacheScript}";
      auto-optimise-store = false;
    };
  };

  # Restricted user for Claude container remote nix builds
  # No sudo, no wheel — only nix-daemon --stdio via SSH forced command
  # Shell must be bash (not nologin) because sshd runs forced commands via
  # the user's login shell: `$SHELL -c "nix-daemon --stdio"`.
  # nologin ignores -c, prints "This account is currently not available."
  # and exits — corrupting the nix ssh-ng protocol handshake.
  users.users.nix-builder = {
    isNormalUser = true;
    home = "/var/lib/nix-builder";
    createHome = true;
    group = "nogroup";
    shell = pkgs.bash + "/bin/bash";
    openssh.authorizedKeys.keys = [
      ''command="nix-daemon --stdio",no-port-forwarding,no-X11-forwarding,no-agent-forwarding ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF9jwwrWQthxzsIDXpE0oA6jMDjXIPwUPrN6Evm6DY2L jappeace-sloth-tablet''
    ];
  };

  system.nixos =
    let
      rev = pkgs.lib.substring 0 8 sources.nixpkgs.revision;
    in
    {
      versionSuffix = "-git:${rev}";
      distroName = "JappieOS"; # lmao, how many autism points? hmm?
      revision = rev;
    };
}
