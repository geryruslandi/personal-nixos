{ pkgs, ... }:

let
  # Pinned to the audited release tag (v2026.8.1). The upstream repo ships its
  # own package.nix (rustPlatform.buildRustPackage with a committed Cargo.lock),
  # so we call that rather than duplicating the derivation here — it stays
  # checksum-verified and reproducible.
  src = pkgs.fetchFromGitHub {
    owner = "webstonehq";
    repo = "tuxedo";
    rev = "v2026.8.1";
    hash = "sha256-E7zjvg5EMBq9hDjILKsNHb7ig90DcS28x/db8v0b5x0=";
  };

  tuxedo = pkgs.callPackage "${src}/package.nix" { };
in
{
  # The Noctalia plugin `gery/note-tuxedo` shells out to this binary; it resolves
  # `tuxedo` from the session PATH (or an absolute path set in its settings).
  home.packages = [ tuxedo ];
}
