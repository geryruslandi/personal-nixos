{ pkgs, lib, ... }:

let
  # Pinned to the audited commit (v1.4.0). Build from source = reproducible and
  # checksum-verified, unlike the AUR -bin tarball (whose PKGBUILD uses
  # sha256sums=('SKIP')).
  src = pkgs.fetchFromGitHub {
    owner = "akitaonrails";
    repo = "ai-usagebar";
    rev = "526ea17c36b081894d18f4b72246b590f390ab1e";
    hash = "sha256-K1Ch+13kFXzNZh5vm/fKMiQrCKFuPMFoIXCpK6DkHx8=";
  };

  aiUsagebar = pkgs.rustPlatform.buildRustPackage {
    pname = "ai-usagebar";
    version = "1.4.0";

    inherit src;
    cargoLock.lockFile = "${src}/Cargo.lock";

    # ring (via rustls) needs NASM for x86_64 assembly; rusqlite[bundled] builds
    # SQLite via the C compiler that rustPlatform already provides.
    nativeBuildInputs = [ pkgs.nasm ];

    # Upstream unit tests shell out to `tar` (a test-only dep irrelevant to the
    # shipped binaries); skip them so the package builds cleanly.
    doCheck = false;

    # Layer a local patch (kept next to this file) so the OpenRouter highlight
    # in the `--json` report (consumed by the Noctalia plugin) tracks the
    # per-key limit as a daily budget instead of credit consumption. Applies on
    # top of the pinned commit.
    patches = [ ./openrouter-daily-limit.patch ];

    meta = with lib; {
      description = "AI plan usage CLI (Claude, OpenAI, Cursor, etc.) for waybar/noctalia";
      homepage = "https://github.com/akitaonrails/ai-usagebar";
      license = licenses.mit;
      mainProgram = "ai-usagebar";
    };
  };
in
{
  home.packages = [
    aiUsagebar
    pkgs.xdg-utils # satisfies the plugin's declared `xdg-open` dependency
  ];
}
