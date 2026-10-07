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

    # Layer local patches (kept next to this file) on top of the pinned commit:
    #   - openrouter-daily-limit.patch: OpenRouter in the `--json` report
    #     (consumed by the Noctalia plugin) shows a highlighted "Daily Key
    #     Limit" card when a per-key limit is set, plus an unhighlighted
    #     "Credit balance" card for total account credits.
    #   - bifrost.patch: adds a Bifrost vendor — the new src/bifrost module plus
    #     the wiring into VendorId / config / panels / widget. The panel renders
    #     three pace-gauge cards (1d, 7d, 30d), each from the same
    #     `{base_url}/usage?period=Xd` endpoint; the 30d card is the headline
    #     (bar capsule, budget %, Waybar output) and reads the full budget
    #     while the shorter cards pace against their share of the month. The
    #     bottom text rows (requests/tokens/models/key) are gone. Windows fail
    #     independently: one bad period renders as a named text row, not a
    #     failed vendor. Applies on top of the pinned commit.
    #   - deepseek-peak-hours.patch: the OpenCode Go report opens with a
    #     "DeepSeek V4 Peak Hours" block (above the Rolling/Weekly/Monthly
    #     cards) with the UTC peak schedule (Mon–Fri
    #     01:00–04:00, 06:00–10:00), whether `now` is peak or off-peak with
    #     the local and UTC clock time, and the countdown to the next boundary.
    #     The block also carries a machine-readable `severity` ("critical"
    #     during peak) that the vendored panel fork tints the card with.
    #   - OpenCode Go's USD cards are NOT patched here: the API only reports a
    #     percent, and the vendored Noctalia plugin derives the dollars from a
    #     user-tunable monthly budget (see
    #     home-sync/.../plugins/ai-usagebar/service.luau), so there are no
    #     constants to reprice here.
    patches = [
      ./openrouter-daily-limit.patch
      ./bifrost.patch
      ./deepseek-peak-hours.patch
    ];

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
