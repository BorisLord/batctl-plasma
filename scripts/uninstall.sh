#!/usr/bin/env bash
# Removes Batctl Battery Manager: the plasmoid (user-local) and the bundled
# batctl binary plus polkit policy (system-wide, one pkexec prompt).

set -euo pipefail

PLUGIN_ID="org.batctl.plasma"
BATCTL_DIR="/usr/lib/batctl-plasma"
POLICY_DST="/usr/share/polkit-1/actions/${PLUGIN_ID}.policy"

kpackagetool6 --type Plasma/Applet --remove "$PLUGIN_ID" 2>/dev/null || true

pkexec sh -c "
    rm -rf '${BATCTL_DIR}'
    rm -f '${POLICY_DST}'
"

echo "Uninstalled."
