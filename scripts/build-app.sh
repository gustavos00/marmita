#!/bin/zsh
# Builds Marmita.app in ./build. Signs ad hoc unless SIGN_IDENTITY names a
# codesigning identity (or .sign-identity holds one); with ad hoc signing macOS
# forgets the Accessibility permission after every rebuild, with a real
# identity it keeps it.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-release}"
APP="build/Marmita.app"

if [[ -z "${SIGN_IDENTITY:-}" && -f .sign-identity ]]; then
    SIGN_IDENTITY="$(<.sign-identity)"
fi

swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Marmita" "$APP/Contents/MacOS/Marmita"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --options runtime --sign "${SIGN_IDENTITY:--}" "$APP"

echo "Built $APP"
