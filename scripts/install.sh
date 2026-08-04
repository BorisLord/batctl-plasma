#!/usr/bin/env bash
# Installs Batctl Battery Manager for the current user.
#
# End-user flow (curl | bash):
#   curl -fsSL https://github.com/BorisLord/batctl-plasma/releases/latest/download/install.sh | bash
#
# The script downloads a precompiled tarball from the GitHub release that
# matches this host's distribution and architecture, installs the plasmoid
# for the current user via kpackagetool6, then installs the C++ plugin and
# the polkit policy system-wide (one pkexec prompt). batctl itself is
# installed to /usr/bin/batctl only if it is not already on the PATH; an
# existing batctl is used as-is and never overwritten.
#
# No build toolchain is required on the host. Set BATCTL_PLASMA_TAG=<tag> to
# install a specific release instead of latest.

set -euo pipefail

PLUGIN_ID="org.batctl.plasma"
POLICY_DST="/usr/share/polkit-1/actions/${PLUGIN_ID}.policy"
REPO="BorisLord/batctl-plasma"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

need() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

need curl
need tar
need kpackagetool6
need pkexec
need qmake6

# Resolve the host's QML module dir (mirrors the CMake logic at build time).
QML_DIR="$(qmake6 -query QT_INSTALL_QML)"
[[ -n "$QML_DIR" ]] || QML_DIR="/usr/lib/qt6/qml"
QML_PLUGIN_DIR="${QML_DIR}/org/batctl/plasma"

# ---- host detection ---------------------------------------------------------

arch="$(uname -m)"
case "$arch" in
    x86_64) asset_arch="x86_64" ;;
    aarch64) asset_arch="aarch64" ;;
    *) die "unsupported architecture: $arch" ;;
esac

. /etc/os-release 2>/dev/null || die "cannot read /etc/os-release; unsupported distribution"
distro_id="${ID:-}"
distro_family=""
case "$distro_id" in
    fedora) distro_family="fedora" ;;
    ubuntu | debian | linuxmint | pop) distro_family="ubuntu" ;;
    *) die "unsupported distribution: ${distro_id:-unknown}. Use the manual build from the README." ;;
esac

# ---- resolve release tag ----------------------------------------------------

tag="${BATCTL_PLASMA_TAG:-}"
if [[ -z "$tag" ]]; then
    tag="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
        | grep -m1 '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')"
    [[ -n "$tag" ]] || die "could not determine latest release tag"
fi

asset="batctl-plasma-${tag}-${distro_family}-${asset_arch}.tar.gz"
url="https://github.com/${REPO}/releases/download/${tag}/${asset}"

# ---- download + extract -----------------------------------------------------

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

printf 'Downloading %s...\n' "$asset"
curl -fsSL -o "${tmp}/${asset}" "$url" || die "download failed: $url"
tar -xzf "${tmp}/${asset}" -C "$tmp"

[[ -d "${tmp}/package" ]] || die "tarball missing package/ directory"
[[ -d "${tmp}/qml" ]] || die "tarball missing qml/ directory (C++ plugin)"
[[ -f "${tmp}/qml/libbatctlbackend.so" ]] || die "tarball missing libbatctlbackend.so"
[[ -f "${tmp}/qml/qmldir" ]] || die "tarball missing qml/qmldir"
[[ -f "${tmp}/qml/batctlbackend.qmltypes" ]] || die "tarball missing qml/batctlbackend.qmltypes"
[[ -f "${tmp}/batctl" ]] || die "tarball missing bundled batctl binary"
[[ -f "${tmp}/${PLUGIN_ID}.policy" ]] || die "tarball missing polkit policy"
[[ -f "${tmp}/THIRD_PARTY_LICENSES.md" ]] || die "tarball missing THIRD_PARTY_LICENSES.md"

# ---- install plasmoid kpackage (user-local) --------------------------------

if kpackagetool6 --type Plasma/Applet --show "$PLUGIN_ID" >/dev/null 2>&1; then
    kpackagetool6 --type Plasma/Applet --upgrade "${tmp}/package"
else
    kpackagetool6 --type Plasma/Applet --install "${tmp}/package"
fi

# ---- install C++ plugin + batctl (if missing) + polkit policy (system) ------

# Convention Plasma: use the host's batctl if present, never overwrite it.
# Only install our bundled copy to /usr/bin/batctl when none is on the PATH.
existing_batctl="$(command -v batctl 2>/dev/null || true)"
if [[ -n "$existing_batctl" ]]; then
    printf 'batctl found at %s; using it as-is.\n\n' "$existing_batctl"
    install_batctl=""
else
    printf 'batctl not found; will install to /usr/bin/batctl.\n\n'
    install_batctl="install -o root -g root -m 0755 '${tmp}/batctl' '/usr/bin/batctl'"
fi

# Single pkexec invocation so the user authenticates once. The C++ QML plugin
# goes to the host QML module dir; batctl (if missing) to /usr/bin; the policy
# to its canonical system location.
pkexec sh -c "
    set -e
    install -d -o root -g root -m 0755 '${QML_PLUGIN_DIR}'
    install -o root -g root -m 0755 '${tmp}/qml/libbatctlbackend.so' '${QML_PLUGIN_DIR}/libbatctlbackend.so'
    install -o root -g root -m 0644 '${tmp}/qml/qmldir' '${QML_PLUGIN_DIR}/qmldir'
    install -o root -g root -m 0644 '${tmp}/qml/batctlbackend.qmltypes' '${QML_PLUGIN_DIR}/batctlbackend.qmltypes'
    ${install_batctl}
    install -o root -g root -m 0644 '${tmp}/${PLUGIN_ID}.policy' '${POLICY_DST}'
"

cat <<'EOF'

Installed. Add "Batctl Battery Manager" from Plasma's widget picker
(right-click the panel → Add Widgets).

To uninstall: ./scripts/uninstall.sh
EOF
