# 📦 Zing Release Installers

Platform-specific installers for Zing.

## Quick Install

### Arch Linux
```bash
curl -fsSL https://raw.githubusercontent.com/ghostkellz/zing/main/release/arch/install.sh | bash
```

### Fedora / Nobara / Bazzite
```bash
curl -fsSL https://raw.githubusercontent.com/ghostkellz/zing/main/release/fedora/install.sh | bash
```

### Debian / Ubuntu
```bash
curl -fsSL https://raw.githubusercontent.com/ghostkellz/zing/main/release/debian/install.sh | bash
```

### Pop!_OS (COSMIC Desktop)
```bash
curl -fsSL https://raw.githubusercontent.com/ghostkellz/zing/main/release/popos/install.sh | bash
```

---

## Directory Structure

```
release/
├── arch/           # Arch Linux / Manjaro / EndeavourOS
│   ├── PKGBUILD    # AUR-ready PKGBUILD
│   └── install.sh  # One-liner installer
│
├── fedora/         # Fedora / Nobara / Bazzite
│   ├── zing.spec   # RPM spec file
│   └── install.sh  # One-liner installer
│
├── debian/         # Debian / Ubuntu / Mint
│   ├── control     # Debian control file
│   └── install.sh  # One-liner installer
│
├── popos/          # Pop!_OS (COSMIC Desktop)
│   └── install.sh  # COSMIC-optimized installer
│
└── shared/         # Shared resources
    ├── desktop/    # .desktop files
    │   └── zing.desktop
    └── icons/      # Application icons
        ├── zing-16.png
        ├── zing-24.png
        ├── zing-32.png
        ├── zing-48.png
        ├── zing-64.png
        ├── zing-128.png
        ├── zing-256.png
        └── zing-512.png
```

---

## Supported Platforms

| Distribution | Package Manager | Desktop | Status |
|-------------|-----------------|---------|--------|
| Arch Linux | pacman | Any | ✅ |
| Manjaro | pacman | Any | ✅ |
| EndeavourOS | pacman | Any | ✅ |
| Fedora | dnf | GNOME/KDE | ✅ |
| Nobara | dnf | GNOME/KDE | ✅ |
| Bazzite | dnf | KDE/GNOME | ✅ |
| Debian | apt | Any | ✅ |
| Ubuntu | apt | Any | ✅ |
| Linux Mint | apt | Cinnamon | ✅ |
| Pop!_OS | apt | COSMIC/GNOME | ✅ |

---

## What Gets Installed

- `/usr/local/bin/zing` - Main binary
- `/usr/local/share/doc/zing/` - Documentation
- `/usr/local/share/applications/zing.desktop` - Desktop entry
- `/usr/local/share/icons/hicolor/*/apps/zing.png` - Application icons

---

## Building Packages

### Arch Linux (PKGBUILD)
```bash
cd release/arch
makepkg -si
```

### Fedora (RPM)
```bash
cd release/fedora
rpmbuild -ba zing.spec
```

---

## Maintainer

Christopher Kelley <ckelley@ghostkellz.sh>
