#!/usr/bin/env bash
# batctl and its persistence configuration remain available to independent CLI users.
set -euo pipefail

PLUGIN_ID="org.batctl.plasma"
QML_DIR="$(qmake6 -query QT_INSTALL_QML)"
[[ "$QML_DIR" = /* && "$QML_DIR" != / ]] || {
    printf 'Invalid QML directory\n' >&2
    exit 1
}

if [[ -d "${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/$PLUGIN_ID" ]]; then
    kpackagetool6 --type Plasma/Applet --remove "$PLUGIN_ID"
fi

# The privileged shell expands its positional arguments.
# shellcheck disable=SC2016
pkexec sh -eu -c '
    rm -rf -- "$1/org/batctl/plasma" /usr/share/plasma/plasmoids/org.batctl.plasma
    rm -f -- /usr/share/polkit-1/actions/org.batctl.plasma.policy
    rm -rf -- /usr/share/batctl-plasma /usr/share/doc/batctl-plasma
' sh "$QML_DIR"

printf 'Uninstalled. /usr/bin/batctl and its persistence configuration were kept.\n'
