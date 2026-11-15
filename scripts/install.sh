#!/usr/bin/env bash
# Use a matching binary release, or compile the tagged source against the host's Qt.
set -euo pipefail

PLUGIN_ID="org.batctl.plasma"
REPO="BorisLord/batctl-plasma"
BATCTL="/usr/bin/batctl"
BATCTL_VERSION="v2026.3.13"
POLICY_DST="/usr/share/polkit-1/actions/${PLUGIN_ID}.policy"
SUPPORT_DIR="/usr/share/batctl-plasma"
PACKAGE_DIR="/usr/share/plasma/plasmoids/${PLUGIN_ID}"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}
need() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1; install prerequisites from https://github.com/${REPO}#development"; }

for command in curl tar kpackagetool6 pkexec qmake6 stat; do
    need "$command"
done

QML_DIR="$(qmake6 -query QT_INSTALL_QML)"
[[ "$QML_DIR" = /* && "$QML_DIR" != / ]] || die "qmake6 returned an invalid QML directory"
QML_PLUGIN_DIR="${QML_DIR}/org/batctl/plasma"

arch="$(uname -m)"
. /etc/os-release
baseline=""
if [[ "$arch" == x86_64 ]]; then
    case "${ID:-}" in
        fedora)
            if [[ "${VERSION_ID:-}" =~ ^[0-9]+$ ]] && ((10#$VERSION_ID >= 43)); then
                baseline="fedora43"
            fi
            ;;
        debian)
            if [[ "${VERSION_ID:-}" =~ ^[0-9]+$ ]] && ((10#$VERSION_ID >= 13)); then
                baseline="debian13"
            fi
            ;;
        ubuntu)
            if [[ "${VERSION_ID:-}" =~ ^([0-9]+)\.([0-9]+)$ ]] \
                && ((10#${BASH_REMATCH[1]} > 26 || (10#${BASH_REMATCH[1]} == 26 && 10#${BASH_REMATCH[2]} >= 4))); then
                baseline="debian13"
            fi
            ;;
    esac
fi

# A different program (including the batman-adv networking CLI) must never be replaced.
if [[ -e "$BATCTL" || -L "$BATCTL" ]]; then
    [[ -f "$BATCTL" && -x "$BATCTL" ]] || die "$BATCTL is not an executable file"
    [[ "$(stat -Lc %u "$BATCTL")" == 0 ]] || die "$BATCTL must be owned by root"
    mode="$(stat -Lc %a "$BATCTL")"
    (((8#$mode & 022) == 0)) || die "$BATCTL must not be group/other writable"
    help="$("$BATCTL" set --help)" || die "$BATCTL is not the battery charge manager"
    [[ "$help" == *--preset* && "$help" == *--start* && "$help" == *--stop* ]] || die "$BATCTL is not the battery charge manager; resolve the name conflict first"
elif [[ "$arch" != x86_64 && "$arch" != aarch64 ]]; then
    die "no bundled batctl for $arch; install the battery manager at $BATCTL first"
fi

tag="${BATCTL_PLASMA_TAG:-}"
if [[ -z "$tag" ]]; then
    release_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest")"
    tag="${release_url##*/}"
fi
[[ "$tag" =~ ^v[0-9][a-zA-Z0-9._-]*$ ]] || die "invalid release tag: $tag"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
stage="$tmp/staging"
mkdir -p "$stage"
if [[ -n "$baseline" ]]; then
    asset="batctl-plasma-${tag}-${baseline}-${arch}.tar.gz"
    printf 'Downloading %s...\n' "$asset"
    status="$(curl -sSL -o "$tmp/release.tar.gz" -w '%{http_code}' "https://github.com/${REPO}/releases/download/${tag}/${asset}")"
    case "$status" in
        200)
            tar -xzf "$tmp/release.tar.gz" -C "$stage"
            build_qt="$(<"$stage/qt-version")"
            [[ "$build_qt" =~ ^6\.([0-9]+)\. ]] || die "invalid package Qt version"
            build_minor="${BASH_REMATCH[1]}"
            host_qt="$(qmake6 -query QT_VERSION)"
            if [[ ! "$host_qt" =~ ^6\.([0-9]+)\. ]] || ((10#${BASH_REMATCH[1]} < 10#$build_minor)); then
                printf 'Package requires Qt %s; installed Qt is %s. Building from source instead.\n' "$build_qt" "$host_qt"
                baseline=""
            fi
            ;;
        404)
            printf 'No %s binary in %s; building from source instead.\n' "$baseline" "$tag"
            baseline=""
            ;;
        *) die "binary download failed (HTTP $status)" ;;
    esac
fi
if [[ -z "$baseline" ]]; then
    rm -rf "$stage"
    mkdir "$stage"
    for command in cmake ninja c++; do
        need "$command"
    done
    printf 'Building %s for %s %s (%s) with the installed Qt...\n' "$tag" "${ID:-Linux}" "${VERSION_ID:-}" "$arch"
    curl -fsSL -o "$tmp/source.tar.gz" "https://github.com/${REPO}/archive/refs/tags/${tag}.tar.gz"
    mkdir "$tmp/source"
    tar -xzf "$tmp/source.tar.gz" -C "$tmp/source" --strip-components=1
    cmake -S "$tmp/source" -B "$tmp/build" -G Ninja -DCMAKE_BUILD_TYPE=Release
    cmake --build "$tmp/build" --parallel
    ctest --test-dir "$tmp/build" --output-on-failure
    DESTDIR="$stage" cmake --install "$tmp/build"
fi

if [[ ! -e "$BATCTL" && ! -f "$stage/usr/bin/batctl" ]]; then
    curl -fsSL -o "$tmp/batctl.tar.gz" \
        "https://github.com/Ooooze/batctl/releases/download/${BATCTL_VERSION}/batctl-${BATCTL_VERSION#v}-linux-${arch}.tar.gz"
    mkdir -p "$stage/usr/bin"
    tar -xzf "$tmp/batctl.tar.gz" -C "$stage/usr/bin" batctl
fi

for file in "$QML_PLUGIN_DIR/libbatctlbackend.so" "$QML_PLUGIN_DIR/qmldir" \
    "$QML_PLUGIN_DIR/batctlbackend.qmltypes" "$POLICY_DST" "$SUPPORT_DIR/uninstall.sh" \
    "$PACKAGE_DIR/metadata.json"; do
    [[ -f "$stage$file" ]] || die "release missing $file"
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
' sh "$stage" "$QML_PLUGIN_DIR" "$POLICY_DST" "$SUPPORT_DIR"

if [[ -d "${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/$PLUGIN_ID" ]]; then
    kpackagetool6 --type Plasma/Applet --upgrade "$stage$PACKAGE_DIR"
else
    kpackagetool6 --type Plasma/Applet --install "$stage$PACKAGE_DIR"
fi
printf '\nInstalled. Add "Batctl Battery Manager" from the Plasma widget picker.\n'
printf 'To uninstall: bash %s/uninstall.sh\n' "$SUPPORT_DIR"
