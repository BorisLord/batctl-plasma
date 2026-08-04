# Batctl Battery Manager for Plasma

A Plasma 6 panel widget that presents the capabilities of the bundled [`batctl`](https://github.com/Ooooze/batctl) through a native GUI.

The widget does not define hardware support or charging presets. It reads status from `batctl status`, discovers presets from `batctl set --help`, and applies the selected identifier with `batctl set --preset`. The `batctl` binary ships inside the plugin; no separate install is required.

## Requirements

- KDE Plasma 6
- Supported distribution: Fedora, or Ubuntu/Debian and derivatives
- x86_64 or aarch64

No build toolchain is needed. The installer downloads a precompiled package that already includes `batctl` and the Qt6 backend compiled against your distribution's Qt6.

## Install

One-liner (downloads and installs everything, asks for your password once to install the bundled `batctl` and the Polkit policy):

```bash
curl -fsSL https://github.com/OWNER/REPO/releases/latest/download/install.sh | bash
```

Replace `OWNER/REPO` with this project's GitHub slug, or download `install.sh` from the latest release and run it:

```bash
./install.sh
```

Then open Plasma's widget picker (right-click a panel → Add Widgets) and add **Batctl Battery Manager**.

## Development

Building from source requires CMake, a C++20 compiler, and Qt 6 development packages.

Fedora:

```bash
sudo dnf install qt6-qtbase-devel qt6-qtdeclarative-devel cmake ninja-build gcc-c++
```

```bash
cmake -S . -B build -G Ninja
cmake --build build --parallel
ctest --test-dir build --output-on-failure
plasmawindowed org.batctl.plasma
```

## Uninstall

```bash
./scripts/uninstall.sh
```

## License

MIT. Bundled `batctl` is also MIT; see [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
