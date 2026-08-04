#!/usr/bin/env bash
# Removes Batctl Battery Manager: the plasmoid kpackage (user-local) and the
# C++ QML plugin, bundled batctl binary, and polkit policy (system-wide,
# one pkexec prompt).

set -euo pipefail

PLUGIN_ID="org.batctl.plasma"
BATCTL_DIR="/usr/lib/batctl-plasma"
POLICY_DST="/usr/share/polkit-1/actions/${PLUGIN_ID}.policy"

QML_DIR="$(qmake6 -query QT_INSTALL_QML 2>/dev/null || echo /usr/lib/qt6/qml)"
QML_PLUGIN_DIR="${QML_DIR}/org/batctl"

kpackagetool6 --type Plasma/Applet --remove "$PLUGIN_ID" 2>/dev/null || true

# Remove the system C++ plugin dir, bundled batctl, and the polkit policy.
pkexec sh -c "
    rm -rf '${QML_PLUGIN_DIR}'
    rm -rf '${BATCTL_DIR}'
    rm -f '${POLICY_DST}'
"

echo "Uninstalled."
