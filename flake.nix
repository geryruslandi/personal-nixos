{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    hyprland.url = "github:hyprwm/Hyprland";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    quickshell.url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
    quickshell.inputs.nixpkgs.follows = "nixpkgs";

    noctalia.url = "github:noctalia-dev/noctalia/legacy-v4";
    noctalia.inputs.nixpkgs.follows = "nixpkgs";

    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";

    silentSDDM.url = "github:uiriansan/SilentSDDM";
    silentSDDM.inputs.nixpkgs.follows = "nixpkgs";

    reasonix.url = "github:esengine/DeepSeek-Reasonix/main-v2";
    reasonix.flake = false;
  };

  outputs =
    inputs@{
      nixpkgs,
      home-manager,
      nix-flatpak,
      reasonix,
      ...
    }:
    let
      lib = nixpkgs.lib;
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      reasonixPkg = pkgs.buildGoModule {
        pname = "reasonix";
        version = "unstable-2026-07-22";
        src = inputs.reasonix;
        vendorHash = "sha256-aCkpuj75e4B0kC9PibDir8fo68EvVNlC5B0NQrEJK3M=";
        subPackages = [ "./cmd/reasonix" ];
      };
    in
    {
      packages.${system}.default = reasonixPkg;

      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs reasonixPkg; }; # this is the important part
        modules = [
          ./configuration.nix
          ./flatpak.nix
          home-manager.nixosModules.home-manager
          nix-flatpak.nixosModules.nix-flatpak
          {
            home-manager.extraSpecialArgs = { inherit inputs reasonixPkg; };
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
