#!/bin/sh
# Confirms App Store sandbox serves the Pro product, which is what App Review
# sees: builds the MonthlioSandbox scheme (no local StoreKit configuration),
# launches it on a simulator and watches the store log. Pass a simulator UDID,
# or the first available iPhone is used. Exits 1 when the product is missing.
set -e
UDID=${1:-$(xcrun simctl list devices available -j | python3 -c "import json,sys; d=json.load(sys.stdin)['devices']; print(next(x['udid'] for k,v in d.items() if 'iOS' in k for x in v if x['name'].startswith('iPhone')))")}
DD=${DD:-$(mktemp -d)/dd}
LOG=$(mktemp)
cd "$(dirname "$0")/.."
xcrun simctl boot "$UDID" 2>/dev/null || true
xcodebuild build -project Monthlio.xcodeproj -scheme MonthlioSandbox -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DD" -quiet
APP=$(find "$DD/Build/Products" -maxdepth 2 -name "Monthlio.app" | head -1)
xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" com.monthlio.app 2>/dev/null || true
# Info-level lines are not kept in the log store, so watch them live.
xcrun simctl spawn "$UDID" log stream --level info --predicate 'subsystem == "com.monthlio.app" AND category == "store"' > "$LOG" 2>&1 &
STREAM=$!
sleep 3
xcrun simctl launch "$UDID" com.monthlio.app >/dev/null
sleep 15
kill "$STREAM" 2>/dev/null || true
LINE=$(grep -E "Loaded com.monthlio.app.pro|has no product|failed" "$LOG" | tail -1)
echo "${LINE:-no store log line found}"
case "$LINE" in
  *"Loaded com.monthlio.app.pro"*) echo "SANDBOX OK"; exit 0 ;;
  *) echo "SANDBOX NOT OK: the product did not load (check the Paid Apps Agreement and the product state in App Store Connect)"; exit 1 ;;
esac
