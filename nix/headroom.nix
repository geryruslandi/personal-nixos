{
  inputs,
  pkgs,
  # Extra headroom-ai pyproject extras to build in. "proxy" is the local
  # compression proxy runtime; "code" adds tree-sitter AST CodeCompressor.
  headroomExtras ? [
    "proxy"
    "code"
  ],
}:
let
  inherit (pkgs.lib) composeManyExtensions;

  python = pkgs.python313;

  # headroom's own repo: pyproject.toml + uv.lock + Cargo.lock are used as-is.
  workspace = inputs.uv2nix.lib.workspace.loadWorkspace {
    workspaceRoot = inputs.headroom;
  };

  # Prefer manylinux wheels for every dep that ships them (onnxruntime,
  # orjson, sqlite-vec, tree-sitter... have cp313 x86_64 wheels).
  wheelOverlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };

  # Build-system overlay (must come first in composeManyExtensions).
  # headroom has NO wheel in its own uv.lock (workspace-root editable
  # entry), so it builds from source via its maturin backend. The pyproject-
  # build-systems overlay provides a python `maturin` built from nixpkgs.
  buildSystemsOverlay = inputs.pyproject-build-systems.overlays.wheel;

  # Fixups for headroom-ai's maturin source build: vendor its Cargo.lock and
  # wire the rust build hooks
  headroomFixups = final: prev: {
    headroom-ai = prev.headroom-ai.overrideAttrs (old: {
      nativeBuildInputs =
        (old.nativeBuildInputs or [ ])
        ++ [
          pkgs.rustPlatform.cargoSetupHook
          pkgs.rustPlatform.maturinBuildHook
          pkgs.cargo
          pkgs.rustc
        ];
      cargoRoot = ".";
      cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
        inherit (old) src;
        name = "headroom-cargo-${old.version}";
        hash = "sha256-iEvap6uLsAqCSv+l/S7K7osxL+yV7Y8pE6Dhaqt2AIA=";
      };
    });
  };

  pythonSet =
    (pkgs.callPackage inputs.pyproject-nix.build.packages {
      inherit python;
    }).overrideScope
      (composeManyExtensions [
        buildSystemsOverlay
        wheelOverlay
        headroomFixups
      ]);

  # Dependency spec: headroom-ai base deps + the selected extras (base deps
  # are implicit — the list only adds optional-dependency extras).
  headroomSpec = {
    headroom-ai = headroomExtras;
  };

  headroomVenv = pythonSet.mkVirtualEnv "headroom-ai-env" headroomSpec;

  # The venv bundles its own python interpreter symlinks — do NOT put the
  # whole venv into home.packages: colliding bin/python3 with other python
  # environments in the user profile. The consumer module links only
  # binHeadroom instead. Entry-point scripts resolve python via the venv's
  # store path (absolute), so they work from anywhere.
  headroomPkg = headroomVenv;

  # The self-contained opencode transport plugin bundle committed in the
  # source tree — patches opencode's fetch to reroute every provider through
  # the local proxy (tags real upstream via x-headroom-base-url).
  opencodePlugin = "${headroomPkg}/lib/python3.13/site-packages/headroom/providers/opencode/_dist/entry.opencode.js";
  binHeadroom = "${headroomPkg}/bin/headroom";
in
headroomPkg
// {
  inherit opencodePlugin binHeadroom;
}
