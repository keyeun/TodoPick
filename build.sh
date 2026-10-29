#!/bin/zsh
# TodoPick build script — needs only the Xcode Command Line Tools (no Xcode).
#
#   ./build.sh               build build/TodoPick.app
#   ./build.sh install       build, copy to ~/Applications, launch, turn on launch at login
#   ./build.sh uninstall     turn off launch at login and remove the app (your data stays)
#   ./build.sh test          run the logic tests
#   ./build.sh screenshots   render docs/*.png from sample data (never your real data)
#   ./build.sh check-offline confirm the source contains no networking code
set -e
cd "$(dirname "$0")"

APP=build/TodoPick.app
DEST="$HOME/Applications/TodoPick.app"
TARGET="$(uname -m)-apple-macosx14.0"
SWIFTC=(swiftc -parse-as-library -swift-version 5 -target "$TARGET")

build_app() {
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  "${SWIFTC[@]}" -O Sources/*.swift -o "$APP/Contents/MacOS/TodoPick"

  # App icon: Resources/AppIcon.png (1024px) → AppIcon.icns
  ICONSET=build/AppIcon.iconset
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size*2)) $((size*2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

  cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>TodoPick</string>
  <key>CFBundleDisplayName</key><string>TodoPick</string>
  <key>CFBundleIdentifier</key><string>local.todopick.widget</string>
  <key>CFBundleExecutable</key><string>TodoPick</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

  # Ad-hoc signature: enough to run on the Mac that built it.
  xattr -cr "$APP"   # Finder/quarantine attributes make codesign fail
  codesign --force --sign - "$APP"
  echo "✅ Built $APP"
}

# Compiles the app sources plus one tool file (the app's @main is left out).
build_tool() {
  mkdir -p build
  "${SWIFTC[@]}" -D TODOPICK_TOOL Sources/*.swift "$1" -o "$2"
}

case "$1" in
  "")
    build_app
    ;;
  install)
    build_app
    pkill -x TodoPick || true
    sleep 1
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open "$DEST" --args --enable-login-item
    echo "✅ Installed $DEST (launch at login is on)"
    ;;
  uninstall)
    pkill -x TodoPick || true
    sleep 1
    if [[ -d "$DEST" ]]; then
      open -W "$DEST" --args --disable-login-item || true
      rm -rf "$DEST"
    fi
    echo "✅ Removed TodoPick. Your data is still in ~/Library/Application Support/TodoPick"
    echo "   Delete that folder too if you want to erase everything."
    ;;
  test)
    build_tool Tools/Tests.swift build/todopick-tests
    TMP=$(mktemp -d)
    TODOPICK_DIR="$TMP" build/todopick-tests
    rm -rf "$TMP"
    ;;
  screenshots)
    build_tool Tools/Screenshots.swift build/todopick-screenshots
    TMP=$(mktemp -d)
    mkdir -p docs
    TODOPICK_DIR="$TMP" build/todopick-screenshots docs
    rm -rf "$TMP"
    ;;
  check-offline)
    # Any of these would mean the app could talk to the internet.
    PATTERN='URLSession|URLRequest|NWConnection|NWPathMonitor|import Network|CFNetwork|WKWebView|NSURLConnection|CloudKit|NSUbiquitous|https?://'
    if grep -nE "$PATTERN" Sources/*.swift; then
      echo "❌ Networking code found above."
      exit 1
    fi
    echo "✅ No networking code in Sources/ — TodoPick never sends your data anywhere."
    ;;
  *)
    echo "usage: ./build.sh [install|uninstall|test|screenshots|check-offline]"
    exit 1
    ;;
esac
