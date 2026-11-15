# Batctl Battery Manager for Plasma

A Plasma 6 panel widget that presents the capabilities of [`batctl`](https://github.com/Ooooze/batctl) through a native GUI.

The widget does not define hardware support or charging presets. It reads status from `batctl status`, discovers presets from `batctl set --help`, and applies the selected identifier with `batctl set --preset`. The widget uses the root-owned `/usr/bin/batctl`, the same executable used by Polkit and batctl's persistence services. It must be the battery manager, not the unrelated batman-adv networking tool.

## Requirements

- KDE Plasma 6 with Qt 6.6 or newer. Plasma 5 is not supported.
- Precompiled packages target Fedora 45 and Ubuntu/Kubuntu 26.10 on x86_64.
- Other distributions and architectures use the source build below with their native Qt 6 development packages.

The binary installer requires `curl`, `tar`, `kpackagetool6`, `pkexec`, and `qmake6`. It downloads a precompiled package containing the Qt6 backend and a `batctl` binary. The Qt libraries must be compatible with the package's build distribution; a shared distribution family alone does not guarantee compatibility. An existing `/usr/bin/batctl` is kept only if it is the root-owned battery manager and cannot be modified by other users. A conflicting executable stops installation; it is never overwritten. If this path is absent, the installer adds the bundled binary there.

## Install

One-liner (downloads and installs everything, asks for your password once to install the C++ plugin, `batctl` if missing, and the Polkit policy):

```bash
curl -fsSL https://github.com/BorisLord/batctl-plasma/releases/latest/download/install.sh | bash
```

Or download `install.sh` from the latest release and run it:

```bash
bash install.sh
```

Then open Plasma's widget picker (right-click a panel → Add Widgets) and add **Batctl Battery Manager**.

The download link uses the latest published release, not the latest repository changes. New installer changes become available after a `v*` tag is pushed and the release workflow succeeds.

## Development

Building from source works across distributions and architectures with Plasma 6, CMake, a C++20 compiler, and Qt 6.6+ development packages. Install the battery manager at `/usr/bin/batctl` before using the widget; source installation does not download batctl.

Fedora:

```bash
sudo dnf install qt6-qtbase-devel qt6-qtdeclarative-devel cmake ninja-build gcc-c++
```

Debian/Ubuntu derivatives with Plasma 6:

```bash
sudo apt install qt6-base-dev qt6-declarative-dev cmake ninja-build g++
```

Use your distribution’s Qt 6 development packages on other systems. The build queries Qt for its native QML installation directory; it does not assume Fedora or Debian library paths.

With [mise](https://mise.jdx.dev) installed, the common tasks are wrapped:

```bash
mise run build      # configure + compile
mise run test       # unit tests
mise run lint       # shellcheck + clang-format + clang-tidy + qmllint + qmlformat
mise run format     # apply all formatters
mise run install-dev # system-wide plugin + widget + Polkit policy
mise run check      # clean build + tests + lint (local CI gate)
```

Otherwise, the manual commands:

```bash
cmake -S . -B build -G Ninja
cmake --build build --parallel
ctest --test-dir build --output-on-failure

# Install the plugin, widget and Polkit policy to their system locations.
sudo cmake --install build
plasmawindowed org.batctl.plasma
```

If switching from the binary installer to a source installation, first remove the user-local copy with `kpackagetool6 --type Plasma/Applet --remove org.batctl.plasma`; otherwise it takes precedence over the system widget.

## Uninstall

```bash
bash /usr/share/batctl-plasma/uninstall.sh
```

Removes the widget, C++ plugin, Polkit policy and supporting files. `batctl` and its persistence configuration are kept because they can be used independently. A user-local widget is removed for the current user; system installation files are shared by all users.

## License

MIT. Bundled `batctl` is also MIT; see [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
