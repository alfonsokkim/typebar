#!/bin/zsh
set -euo pipefail
root="${0:A:h}"
mkdir -p "$root/dist"
architectures=()
if [[ "${1:-}" == "--universal" ]]; then
    architectures=(--arch arm64 --arch x86_64)
fi
swift build --package-path "$root" -c release "${architectures[@]}"
bin="$(swift build --package-path "$root" -c release "${architectures[@]}" --show-bin-path)"
app="$root/dist/Typebar.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Typebar" "$app/Contents/MacOS/Typebar"
cp "$root/Sources/TypingCore/Resources/english.json" "$app/Contents/Resources/english.json"
cp "$root/Sources/TypingCore/Resources/themes.json" "$app/Contents/Resources/themes.json"
cp "$root/LICENSE" "$root/THIRD_PARTY_NOTICES.md" "$app/Contents/Resources/"
swiftc -parse-as-library "$root/Sources/Typebar/TypebarMark.swift" "$root/scripts/make-icon.swift" -o "$root/dist/make-icon"
"$root/dist/make-icon" "$root/dist/Typebar.iconset"
iconutil -c icns "$root/dist/Typebar.iconset" -o "$app/Contents/Resources/Typebar.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Typebar</string>
<key>CFBundleDisplayName</key><string>Typebar</string>
<key>CFBundleIdentifier</key><string>com.alfonsokim.typebar</string>
<key>CFBundleExecutable</key><string>Typebar</string>
<key>CFBundleIconFile</key><string>Typebar.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.1</string>
<key>CFBundleVersion</key><string>8</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSAccessibilityUsageDescription</key><string>Typebar detects the Control, Option, and Command shortcut so you can open the typing overlay from any app.</string>
</dict></plist>
PLIST
codesign --force --sign - --identifier com.alfonsokim.typebar --requirements '=designated => identifier "com.alfonsokim.typebar"' "$app"
print "$app"
