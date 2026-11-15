#!/usr/bin/env bash
# Install the release matching this host. Other Plasma 6 systems build from source.
set -euo pipefail

PLUGIN_ID="org.batctl.plasma"
REPO="BorisLord/batctl-plasma"
BATCTL="/usr/bin/batctl"
POLICY_DST="/usr/share/polkit-1/actions/${PLUGIN_ID}.policy"
SUPPORT_DIR="/usr/share/batctl-plasma"
PACKAGE_DIR="/usr/share/plasma/plasmoids/${PLUGIN_ID}"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}
need() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

for command in curl tar kpackagetool6 pkexec qmake6 stat; do
    need "$command"
done

QML_DIR="$(qmake6 -query QT_INSTALL_QML)"
[[ "$QML_DIR" = /* && "$QML_DIR" != / ]] || die "qmake6 returned an invalid QML directory"
QML_PLUGIN_DIR="${QML_DIR}/org/batctl/plasma"

arch="$(uname -m)"
[[ "$arch" == x86_64 ]] || die "no precompiled package for $arch; build from source (README)"
. /etc/os-release
case "${ID:-}:${VERSION_ID:-}" in
    fedora:45) distro_family="fedora" ;;
    ubuntu:26.10) distro_family="ubuntu" ;;
    *) die "no precompiled package for ${ID:-unknown} ${VERSION_ID:-}; build from source (README)" ;;
esac

# A different program (including the batman-adv networking CLI) must never be replaced.
if [[ -e "$BATCTL" || -L "$BATCTL" ]]; then
    [[ -f "$BATCTL" && -x "$BATCTL" ]] || die "$BATCTL is not an executable file"
    [[ "$(stat -Lc %u "$BATCTL")" == 0 ]] || die "$BATCTL must be owned by root"
    mode="$(stat -Lc %a "$BATCTL")"
    (((8#$mode & 022) == 0)) || die "$BATCTL must not be group/other writable"
    help="$("$BATCTL" set --help)" || die "$BATCTL is not the battery charge manager"
    [[ "$help" == *--preset* && "$help" == *--start* && "$help" == *--stop* ]] || die "$BATCTL is not the battery charge manager; resolve the name conflict first"
fi

tag="${BATCTL_PLASMA_TAG:-}"
if [[ -z "$tag" ]]; then
    release_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest")"
    tag="${release_url##*/}"
fi
[[ "$tag" =~ ^v[0-9][a-zA-Z0-9._-]*$ ]] || die "invalid release tag: $tag"
asset="batctl-plasma-${tag}-${distro_family}-${arch}.tar.gz"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf 'Downloading %s...\n' "$asset"
curl -fsSL -o "${tmp}/release.tar.gz" "https://github.com/${REPO}/releases/download/${tag}/${asset}"
tar -xzf "${tmp}/release.tar.gz" -C "$tmp"

for file in "$QML_PLUGIN_DIR/libbatctlbackend.so" "$QML_PLUGIN_DIR/qmldir" \
    "$QML_PLUGIN_DIR/batctlbackend.qmltypes" "$POLICY_DST" "$SUPPORT_DIR/uninstall.sh" \
    "$PACKAGE_DIR/metadata.json" /usr/bin/batctl; do
    [[ -f "$tmp$file" ]] || die "release missing $file"
done

# Authenticate and install the system dependencies before replacing the user's widget.
# Pass paths as arguments, never interpolate them into privileged shell code.
# The privileged shell expands its positional arguments.
# shellcheck disable=SC2016
pkexec sh -eu -c '
    root=$1 qml=$2 policy=$3 support=$4
    install -d -o root -g root -m 0755 "$qml" "$support"
    install -o root -g root -m 0755 "$root$qml/libbatctlbackend.so" "$qml/"
    install -o root -g root -m 0644 "$root$qml/qmldir" "$root$qml/batctlbackend.qmltypes" "$qml/"
    if [ ! -e /usr/bin/batctl ] && [ ! -L /usr/bin/batctl ]; then
        install -o root -g root -m 0755 "$root/usr/bin/batctl" /usr/bin/batctl
    fi
    install -o root -g root -m 0644 "$root$policy" "$policy"
    install -o root -g root -m 0755 "$root$support/uninstall.sh" "$support/"
    install -d -o root -g root -m 0755 /usr/share/doc/batctl-plasma
    install -o root -g root -m 0644 "$root/usr/share/doc/batctl-plasma/"* /usr/share/doc/batctl-plasma/
' sh "$tmp" "$QML_PLUGIN_DIR" "$POLICY_DST" "$SUPPORT_DIR"

if [[ -d "${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/$PLUGIN_ID" ]]; then
    kpackagetool6 --type Plasma/Applet --upgrade "$tmp$PACKAGE_DIR"
else
    kpackagetool6 --type Plasma/Applet --install "$tmp$PACKAGE_DIR"
fi
printf '\nInstalled. Add "Batctl Battery Manager" from the Plasma widget picker.\n'
printf 'To uninstall: bash %s/uninstall.sh\n' "$SUPPORT_DIR"
