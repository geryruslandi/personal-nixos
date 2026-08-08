{
  description = "A very basic flake";

  nixConfig = {
    extra-substituters = [ "https://noctalia.cachix.org" ];
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

    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";

    silentSDDM.url = "github:uiriansan/SilentSDDM";
    silentSDDM.inputs.nixpkgs.follows = "nixpkgs";

    aethertune.url = "github:nevermore23274/AetherTune";

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
