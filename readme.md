# ❄️ NixOS Hyprland Config

A fully declarative, Flake-based NixOS configuration featuring a high-performance Wayland environment and specialized development stacks.

## 🚀 Key Components

* **Window Manager:** [Hyprland](https://hyprland.org/) (Wayland Compositor)
* **Shell & UI:** [Noctalia-shell](https://github.com/Noctalia/noctalia-shell) for the bar, widgets, and notifications.
* **User Management:** [Home Manager](https://github.com/nix-community/home-manager) for dotfile and per-user state.
* **Flatpaks:** Managed declaratively via [flatpak-nix](https://github.com/gjtaylor/flatpak-nix).
* **Dev Stacks:** Out-of-the-box support for **React Native**, **PHP**, **MySQL**, and **Podman**.

---

## 📂 Project Structure

```text
.
├── configuration.nix        # Core system-level configuration
├── flake.lock               # Lockfile for nix inputs
├── flake.nix                # System entry point & input definitions
├── flatpak.nix              # Declarative Flatpak applications
├── homedir/                 # Static assets/files for the home directory
├── home.nix                 # Main Home Manager entry point
├── nix
│   ├── homes/               # Home Manager modules (User-space)
│   │   ├── hyprland.nix
│   │   ├── kanshi.nix
│   │   ├── kde-associations.nix
│   │   ├── mysql.nix
│   │   ├── noctalia.nix
│   │   ├── php.nix
│   │   ├── podman.nix
│   │   ├── react-native-setup.nix
│   │   ├── theme.nix
│   │   └── zsh.nix
│   └── modules/             # System-level modules (Root-space)
│       ├── audio.nix
│       ├── bluetooth.nix
│       ├── hyprland.nix
│       ├── mysql.nix
│       ├── noctalia.nix
│       ├── nvidia.nix
│       ├── packages.nix
│       ├── power.nix
│       ├── theme.nix
│       ├── users.nix
│       ├── waydroid.nix
│       └── xdg.nix
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

---

## 💻 Development Environment

This setup includes specialized modules for a full-stack development workflow:
* **Mobile:** React Native setup via `nix/homes/react-native-setup.nix`.
* **Backend:** PHP and MySQL (managed via both System and Home modules for flexible environments).
* **Virtualization:** Podman for rootless containers and Waydroid for running Android applications natively.

---

## 🎨 Theme & Appearance
System-wide consistency is maintained through the `theme.nix` modules found in both `homes` and `modules`:
* **GTK/QT:** Unified via Home Manager to ensure a cohesive look across toolkit boundaries.
* **Displays:** Handled by **Kanshi** for dynamic output and monitor profile switching.

---

## 📝 To-Do List

- [ ] **Flatpak Theming:** Integrate Home Manager GTK and QT themes into Flatpak environment.
- [ ] **Kanshi Update:** Refactor deprecated declarations in `nix/homes/kanshi.nix` to the new syntax.
- [ ] **Idle Management:** Debug and fix the non-functional idle/sleep features.
- [ ] **SDDM Multi-screen:** Make sddm work on multi screen.
- [ ] **Bootloader Migration:** Change bootloader to grub.
