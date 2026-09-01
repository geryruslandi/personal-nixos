{
  pkgs,
  lib,
  ...
}:
let
  # Lossless Scaling Frame Generation on Linux — implicit Vulkan layer.
  # Upstream (v2) lives at git.lsfg-vk.dev; pinned to the 2.0.0-rc1 tag
  # (94aa72c1bc3a41e072fde93ee885a941773e66b8). License is CC BY-NC-ND 4.0,
  # so we self-package here instead of nixpkgs.
  #
  # LSFGVK_LAYER_LIBRARY_PATH bakes the absolute store path of the layer
  # library into VkLayer_LSFGVK_frame_generation.json, which is what makes
  # layer discovery work on NixOS (and lets Steam's pressure-vessel import
  # it) — by default upstream installs a bare soname that only works with
  # system-wide /usr installs.
  # Built with clang: rc1's vulkan-hpp usage (`extent = { w, h }`) trips the
  # brace-init ambiguity in GCC 14+ ("ambiguous overload for operator="),
  # while clang — upstream's recommended compiler — accepts it.
  lsfg-vk = pkgs.clangStdenv.mkDerivation {
    pname = "lsfg-vk";
    version = "2.0.0-rc1";

    src = pkgs.fetchgit {
      url = "https://git.lsfg-vk.dev/lsfg-vk.git";
      rev = "94aa72c1bc3a41e072fde93ee885a941773e66b8";
      hash = "sha256-+2Zslbt4A3opMsCgu3/BMA2PJm6vzIFwhsS9Iml9H3Y=";
    };

    nativeBuildInputs = with pkgs; [
      cmake
      ninja
    ];

    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=Release"
      (lib.cmakeBool "LSFGVK_MANAGED" true)
      "-DLSFGVK_LAYER_LIBRARY_PATH=${placeholder "out"}/lib/liblsfg-vk-layer.so"
    ];

    meta = {
      description = "Lossless Scaling Frame Generation on Linux (Vulkan layer)";
      homepage = "https://lsfg-vk.dev";
      license = lib.licenses.unfree; # CC BY-NC-ND 4.0
      platforms = lib.platforms.linux;
    };
  };
in
{
  # Installs:
  #   lib/liblsfg-vk-layer.so
  #   share/vulkan/implicit_layer.d/VkLayer_LSFGVK_frame_generation.json
  #   bin/lsfg-vk-cli
  # The share path lands in /run/current-system/sw/share, which is in
  # XDG_DATA_DIRS, so the Vulkan loader finds the layer in native apps
  # (Lutris, Eden's AppImage bwrap sandbox) and Steam imports it into the
  # pressure-vessel container.
  environment.systemPackages = [ lsfg-vk ];
}
