# Batctl Battery Manager for Plasma

A Plasma 6 panel widget that presents the capabilities of [`batctl`](https://github.com/Ooooze/batctl) through a native GUI.

The widget does not define hardware support or charging presets. It reads status from `batctl status`, discovers presets from `batctl set --help`, and applies the selected identifier with `batctl set --preset`. The widget uses the root-owned `/usr/bin/batctl`, the same executable used by Polkit and batctl's persistence services. It must be the battery manager, not the unrelated batman-adv networking tool.

## Requirements

- KDE Plasma 6 with Qt 6.6 or newer. Plasma 5 is not supported.
- x86_64 packages use Fedora 43 and Debian 13 as build baselines. The installer selects them for Fedora 43+, Debian 13+, and Ubuntu/Kubuntu 26.04+. Each package records its actual build Qt version; an older host Qt triggers a local build instead.
- On other distributions (including derivatives without a matching distribution ID) and architectures, the same installer compiles the tagged source against the installed Qt. This requires CMake, Ninja, a C++20 compiler and Qt 6.6+ development packages; see Development below. It does not install system packages automatically.

The installer requires `curl`, `tar`, `kpackagetool6`, `pkexec`, and `qmake6`. It uses a matching precompiled package when available; otherwise it builds and tests the source before installation. A release without the selected baseline archive also falls back to source; other download failures stop installation. An existing `/usr/bin/batctl` is kept only if it is the root-owned battery manager and cannot be modified by other users. A conflicting executable stops installation; it is never overwritten. If this path is absent, the installer adds batctl v2026.3.13 on x86_64 or aarch64. On other architectures, install the battery manager at that path first.

## Install

One-liner (downloads a binary or builds locally, then asks for your password once to install the C++ plugin, `batctl` if missing, and the Polkit policy):

```bash
curl -fsSL https://github.com/BorisLord/batctl-plasma/releases/latest/download/install.sh | bash
```

Or download `install.sh` from the latest release and run it:

```bash
bash install.sh
```

Then open Plasma's widget picker (right-click a panel → Add Widgets) and add **Batctl Battery Manager**.

The download link uses the latest published release, not the latest repository changes. New installer changes become available after a `v*` tag is pushed and the release workflow succeeds.

The release workflow builds and tests the two baseline packages, then publishes them only after both builds succeed. Loading the unchanged Fedora 43 plugin was also verified on Fedora 44, and the unchanged Debian 13 plugin on Ubuntu 26.10. These checks cover plugin loading, not every desktop or hardware configuration.

## Development

Building from source works across distributions and architectures with Plasma 6, CMake, Ninja, a C++20 compiler, and Qt 6.6+ development packages. These are also the prerequisites for the installer's automatic source build. A manual `cmake --install` does not download batctl; install the battery manager at `/usr/bin/batctl` before using the widget.

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
