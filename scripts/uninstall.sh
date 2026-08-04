#!/usr/bin/env bash
# Removes Batctl Battery Manager: the plasmoid kpackage (user-local) and the
# C++ QML plugin + polkit policy (system-wide, one pkexec prompt).
#
# batctl itself is NOT removed: it may be used independently as a CLI tool and
# may have been installed by the user's package manager. Remove it via your
# package manager if desired.

set -euo pipefail

PLUGIN_ID="org.batctl.plasma"
POLICY_DST="/usr/share/polkit-1/actions/${PLUGIN_ID}.policy"

QML_DIR="$(qmake6 -query QT_INSTALL_QML 2>/dev/null || echo /usr/lib/qt6/qml)"
QML_PLUGIN_DIR="${QML_DIR}/org/batctl"

kpackagetool6 --type Plasma/Applet --remove "$PLUGIN_ID" 2>/dev/null || true

# Remove the system C++ plugin dir and the polkit policy. batctl is left in
# place (see header comment).
pkexec sh -c "
    rm -rf '${QML_PLUGIN_DIR}'
    rm -f '${POLICY_DST}'
"

echo "Uninstalled. batctl itself was not removed; uninstall it via your package manager if desired."
