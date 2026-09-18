{
  description = "A very basic flake";

  nixConfig = {
    extra-substituters = [
      "https://noctalia.cachix.org"
    ];
    extra-trusted-public-keys = [
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    hyprland.url = "github:hyprwm/Hyprland";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Noctalia v5 (standalone native shell). The `cachix` branch always points
    # to the latest commit that has prebuilt binaries on noctalia.cachix.org.
    # Do NOT add `inputs.nixpkgs.follows` here — it disables the binary cache.
    noctalia.url = "github:noctalia-dev/noctalia/cachix";

    # Noctalia Greeter (greetd greeter). Unlike the noctalia shell input this
    # has no prebuilt-binary cache, so following our nixpkgs is fine and avoids
    # a second independent nixpkgs pin.
    noctalia-greeter = {
      url = "github:noctalia-dev/noctalia-greeter";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";

    # OpenCode built from its own flake at release v1.18.31 (always use this
    # fork's flake, not nixpkgs). Keep nixpkgs independent — its node_modules
    # build is tuned for its own nixpkgs-unstable pin (same reasoning as the
    # noctalia input). Bump the ref manually to upgrade releases.
    opencode.url = "github:anomalyco/opencode/v1.18.31";

    aethertune.url = "github:nevermore23274/AetherTune";
    # AetherTune pins an old nixpkgs whose importCargoLock still fetches from
    # crates.io/api — that endpoint now 403s non-identifying User-Agents.
    # Follow our pinned nixpkgs, which fetches from static.crates.io instead.
    aethertune.inputs.nixpkgs.follows = "nixpkgs";

    # Headroom (LLM token-compression proxy), packaged from its own uv.lock
    # via uv2nix — see nix/headroom.nix and home-modules/headroom.nix.
    headroom = {
      # Pinned: v0.37.0 (2c56a1b3) has a broken cargo vendoring hash upstream
      # ("hash mismatch in fixed-output derivation ... headroom-cargo-0.37.0-vendor-staging").
      # Unpin once upstream ships a release with fixed Cargo.lock/vendor hashes.
      url = "github:headroomlabs-ai/headroom/e67b3c8a29443a60d6b0018fb22f525c5cd7e709";
      flake = false; # source repo: pyproject.toml + uv.lock + Cargo.lock
    };

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs =
    inputs@{
      nixpkgs,
      home-manager,
      nix-flatpak,
      ...
    }:
    let
      lib = nixpkgs.lib;
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

    in
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; }; # this is the important part
        modules = [
          ./configuration.nix
          ./flatpak.nix
          home-manager.nixosModules.home-manager
          nix-flatpak.nixosModules.nix-flatpak
          {
            home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.users.geryruslandi.imports = [
              ./home.nix
            ];
          }
        ];
      };
    };
}
