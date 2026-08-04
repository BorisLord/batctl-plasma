#!/usr/bin/env bash
# Installs Batctl Battery Manager for the current user.
#
# End-user flow (curl | bash):
#   curl -fsSL https://github.com/OWNER/REPO/releases/latest/download/install.sh | bash
#
# The script downloads a precompiled tarball from the GitHub release that
# matches this host's distribution and architecture, installs the plasmoid
# for the current user via kpackagetool6, then installs the bundled batctl
# binary and the polkit policy system-wide (one pkexec prompt).
#
# No build toolchain is required on the host. Set BATCTL_PLASMA_TAG=<tag> to
# install a specific release instead of latest.

set -euo pipefail

PLUGIN_ID="org.batctl.plasma"
BATCTL_DIR="/usr/lib/batctl-plasma"
POLICY_DST="/usr/share/polkit-1/actions/${PLUGIN_ID}.policy"
# REPLACE ME: set this to OWNER/REPO before publishing the first release.
REPO="REPLACE_ME/batctl-plasma"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

if [[ "$REPO" == REPLACE_ME/* ]]; then
    die "REPO is a placeholder. Set OWNER/REPO in scripts/install.sh and .github/workflows/release.yml before publishing."
fi

need curl
need tar
need kpackagetool6
need pkexec

# ---- host detection ---------------------------------------------------------

arch="$(uname -m)"
case "$arch" in
    x86_64)  asset_arch="x86_64"  ;;
    aarch64) asset_arch="aarch64" ;;
    *)       die "unsupported architecture: $arch" ;;
esac

. /etc/os-release 2>/dev/null || die "cannot read /etc/os-release; unsupported distribution"
distro_id="${ID:-}"
distro_family=""
case "$distro_id" in
    fedora)                       distro_family="fedora" ;;
    ubuntu|debian|linuxmint|pop)  distro_family="ubuntu" ;;
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

[[ -d "${tmp}/package" ]]             || die "tarball missing package/ directory"
[[ -f "${tmp}/batctl" ]]              || die "tarball missing bundled batctl binary"
[[ -f "${tmp}/${PLUGIN_ID}.policy" ]] || die "tarball missing polkit policy"
[[ -f "${tmp}/THIRD_PARTY_LICENSES.md" ]] || die "tarball missing THIRD_PARTY_LICENSES.md"

# ---- install plasmoid (user-local) -----------------------------------------

if kpackagetool6 --type Plasma/Applet --show "$PLUGIN_ID" >/dev/null 2>&1; then
    kpackagetool6 --type Plasma/Applet --upgrade "${tmp}/package"
else
    kpackagetool6 --type Plasma/Applet --install "${tmp}/package"
fi

# ---- install bundled batctl + polkit policy (system, one prompt) -----------

# Single pkexec invocation installs both files so the user authenticates once.
pkexec sh -c "
    set -e
    install -d -o root -g root -m 0755 '${BATCTL_DIR}'
    install -o root -g root -m 0755 '${tmp}/batctl' '${BATCTL_DIR}/batctl'
    install -o root -g root -m 0644 '${tmp}/THIRD_PARTY_LICENSES.md' '${BATCTL_DIR}/THIRD_PARTY_LICENSES.md'
    install -o root -g root -m 0644 '${tmp}/${PLUGIN_ID}.policy' '${POLICY_DST}'
"

cat <<'EOF'

Installed. Add "Batctl Battery Manager" from Plasma's widget picker
(right-click the panel → Add Widgets).

To uninstall: ./scripts/uninstall.sh
EOF
