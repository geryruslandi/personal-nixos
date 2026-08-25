# ❄️ NixOS Hyprland Config

A fully declarative, Flake-based NixOS configuration featuring a high-performance Wayland environment and specialized development stacks.

## 🚀 Key Components

* **Window Manager:** [Hyprland](https://hyprland.org/) (Wayland Compositor)
* **Shell & UI:** [Noctalia v5](https://github.com/noctalia-dev/noctalia) — native C++23 Wayland shell for the bar, widgets, notifications, lockscreen and theming.
* **Launcher:** [Vicinae](https://github.com/vicinaehq/vicinae) — launcher + clipboard history (`Super+Space` / `Super+V`), replaces the Noctalia launcher panels.
* **Lockscreen:** Noctaria lock + [Qylock](https://github.com/Darkkal44/qylock) (theme `pixel-dusk-city`).
* **User Management:** [Home Manager](https://github.com/nix-community/home-manager) for dotfile and per-user state.
* **Flatpaks:** Managed declaratively via [nix-flatpak](https://github.com/gmodena/nix-flatpak).
* **Dev Stacks:** Out-of-the-box support for **React Native**, **PHP**, **MySQL/PostgreSQL**, and **Docker**.

---

## 📂 Project Structure

```text
.
├── configuration.nix        # Core system-level configuration
├── flake.lock               # Lockfile for nix inputs
├── flake.nix                # System entry point & input definitions
├── secrets.nix              # Local configuration, refer to secrets.example.nix
├── flatpak.nix              # Declarative Flatpak applications
├── rebuild.sh               # Build & switch wrapper (auto-stages secrets.nix)
├── tmux-start.sh            # Attach/create the `nixos` dev session (nvim + opencode)
├── home-sync/               # Editable symlinks into $HOME (edits write back to the repo)
│   ├── .config/             # nvim config, wallpapers/avatar (merged into ~/.config)
│   └── .local/share/noctalia/plugins/services/   # local `gery/services` Noctalia plugin
├── home.nix                 # Main Home Manager entry point
├── home-modules/            # Home Manager modules (User-space)
│   ├── ai-usagebar/         # builds the ai-usagebar CLI for its Noctalia plugin
│   ├── hyprland.nix
│   ├── kanshi.nix
│   ├── kde-associations.nix
│   ├── noctalia.nix
│   ├── vicinae.nix
│   ├── php.nix
│   ├── react-native-setup.nix
│   ├── theme.nix
│   └── zsh.nix
├── system-modules/          # System-level modules (Root-space)
│   ├── audio.nix
│   ├── bluetooth.nix
│   ├── hyprland.nix
│   ├── mysql.nix
│   ├── noctalia.nix
│   ├── nvidia.nix
│   ├── packages.nix
│   ├── power.nix
│   ├── theme.nix            # qylock lockscreen
│   ├── users.nix
│   └── waydroid.nix
└── readme.md
```

---

## 🏁 Getting Started

Follow these steps to initialize the configuration on a new system:

1. **Handle Secrets:**
   Create your local secrets file by referencing the example provided:
   ```bash
   cp secrets.example.nix secrets.nix
   ```
   *Note: Edit `secrets.nix` with your specific credentials/keys.*

2. **Register Secrets with Git:**
   Since Flakes only see files tracked by Git, run:
   ```bash
   git add --intent-to-add secrets.nix -f
   ```
   *(Or just use `./rebuild.sh` — it stages `secrets.nix` for the evaluation and unstages it afterwards.)*

---

## 🛠️ Installation & Deployment

### 1. Hardware Detection
This configuration expects your machine-specific hardware settings to be located at the default system path. Before building, ensure your hardware file is generated:

```bash
sudo nixos-generate-config --show-hardware-config > /etc/nixos/hardware-configuration.nix
```

### 2. Build & Switch
To compile and apply the configuration, run the following command from the root of this repository. The `--impure` flag is required to allow the flake to reference the hardware configuration located at `/etc/nixos/`.

```bash
sudo nixos-rebuild switch --flake . --impure
```

### 3. Fingerprint Enrollment
If your system has a fingerprint reader, enroll your fingerprints to enable fingerprint authentication for sudo and SDDM login:

```bash
fprintd-enroll
```

This will guide you through scanning your fingers. After enrollment:
- Sudo will prompt for fingerprint authentication when required
- SDDM login screen will offer fingerprint as an authentication option
- Terminal login (TTY) will also support fingerprint authentication

**Note:** Fingerprint authentication is enabled by default if `services.fprintd.enable` is set to `true`. Check your fingerprint reader compatibility and ensure your fingerprints are enrolled before attempting to use fingerprint-based authentication.

### 4. Test SDDM Theme Changes
To preview SilentSDDM theme changes without rebooting, run:

```bash
sddm-greeter-qt6 --test-mode --theme /run/current-system/sw/share/sddm/themes/silent/
```

Press `Ctrl+C` or close the window to exit the preview.

### 5. Populate dolphin XDG Application menus (dolphin 'open with' application entries)
To populate app entries on dolphin, you need to run commands:

- `rm -rf ~/.cache/ksycoca6*`
- `kbuildsycoca6 --noincremental`
---

## 💻 Development Environment

This setup includes specialized modules for a full-stack development workflow:
* **Mobile:** React Native setup via `home-modules/react-native-setup.nix`.
* **Backend:** PHP and MySQL (managed via both System and Home modules for flexible environments).
* **Virtualization:** Docker for containers and Waydroid for running Android applications natively.

---

## 🎨 Theme & Appearance
Theming is driven by **Noctalia v5**: the community palette `Catppuccin Frappe Blue` feeds Noctalia's template engine, which generates kitty/GTK3/GTK4/KDE-colorscheme/Qt themes at login (see `home-modules/noctalia.nix`). The Vicinae launcher and tmux carry matching hand-pinned Frappe colors.
* **GTK/QT:** Unified via the generated KDE color scheme + Qt platform theme to ensure a cohesive look across toolkit boundaries.
* **Displays:** Handled by **Kanshi** for dynamic output and monitor profile switching.

---

## Automatic Mount of SSD

To automatically mount SSDs or other storage devices in your NixOS configuration, follow these steps:

1. **Identify Available Devices:**
  Run `lsblk` to list all block devices and identify your SSD (e.g., `/dev/sda1` or `/dev/nvme0n1p1`).

2. **Retrieve the UUID:**
  Use `lsblk -f /dev/{storagePath}` (replace `{storagePath}` with the actual path, like `sda1`) to get the filesystem UUID. This ensures reliable mounting even if device names change.

3. **Configure in Secrets:**
  Add the mount configuration to your `secrets.nix` file under a `storageMount` list. Each entry should include:
  - `mountPath`: The directory where the device will be mounted (ensure it exists or is created).
  - `fsType`: The filesystem type (e.g., `ext4`, `btrfs`).
  - `storageUUID`: The UUID obtained from the previous step.

  Example configuration:
  ```nix
  storageMount = [
    {
     mountPath = "/mnt/data-ssd";
     fsType = "ext4";
     storageUUID = "09e384ed-b4aa-4a15-bab5-8d94e27349ca";
    }
  ];
  ```

4. **Additional Notes:**
  - Ensure the mount path is created if it doesn't exist (you can add it to your NixOS config).
  - Test the mount manually first with `sudo mount UUID={storageUUID} {mountPath}` to verify.
  - For encrypted devices, additional setup may be required (e.g., via LUKS).
  - Rebuild your NixOS configuration after changes: `sudo nixos-rebuild switch --flake . --impure`.

## Common Issues & Fixes (Personal Notes)
### Bad Storage Block
If you encounter storage issues, run `lsblk`, then execute `e2fsck /dev/sd***` with the correct device id given from `lsblk`.

## 📝 To-Do List

- [x] **Flatpak Theming:** Integrate Home Manager GTK and QT themes into Flatpak environment.
- [x] **Idle Management:** Debug and fix the non-functional idle/sleep features.
- [x] **Flatpak ZenBrowser:** Fix downloaded files appears and stored on `~/Downloads`
- [x] **Flatpak app open url:** Fix flatpak app to open url with default browser.
- [x] **Screen Brightness keybind:** Add hyprland keyboard binding to increase/decrease screen brightness.
- [x] **Flatpak Apps Timezone:** Change flatpak apps timezone to local timezone instead of UTC timezone
- [x] **XDG App Menu Integration:** Integrate XDG App Menu with dolphin, so entries of `open with` on dolphin will be populated with existing apps
- [x] **Bootloader Migration:** Change bootloader to grub.
- [x] **SDDM Multi-screen:** Make sddm work on multi screen.
- [x] **Kanshi Update:** Refactor deprecated declarations in `home-modules/kanshi.nix` to the new syntax.
- [ ] **Integrate Optimus:** For seamless graphic card switching, integrate optimus app and prime-select
