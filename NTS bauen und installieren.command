#!/usr/bin/env bash
# Baut das NTS-Widget mit Xcode und installiert es nach /Applications.
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

echo "== Baue NTS Radio …"
./scripts/package-release.sh 1.0.3

echo "== Installiere nach /Applications …"
pkill -f "NTS Radio.app" || true
rm -rf "/Applications/NTS Radio.app"
ditto "dist/stage/NTS Radio.app" "/Applications/NTS Radio.app"
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R "/Applications/NTS Radio.app"
killall NTSWidgetExtension NTSWidgetHost NotificationCenter chronod 2>/dev/null || true
open -a "/Applications/NTS Radio.app"

echo ""
echo "Fertig. Falls das Widget noch alt aussieht: Widget vom Schreibtisch entfernen und neu hinzufügen."
read -n 1 -s -r -p "Taste drücken zum Schließen …"
