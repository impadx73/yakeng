#!/bin/bash
# Biên dịch Yakeng thành Yakeng.app và đóng gói thành Yakeng.dmg (nhấp đúp file này để chạy)
set -e
cd "$(dirname "$0")"

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Chưa có Xcode Command Line Tools. Đang yêu cầu cài đặt..."
  xcode-select --install || true
  echo "Sau khi cài xong, hãy nhấp đúp build.command lần nữa."
  read -n 1 -s -r -p "Nhấn phím bất kỳ để đóng..."
  exit 1
fi

APP="Yakeng.app"
DMG="Yakeng.dmg"
rm -rf "$APP" "$DMG" dmg-root

echo "==> Đang biên dịch (Universal: Apple Silicon + Intel)..."
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if swiftc -O -target arm64-apple-macos11 Sources/main.swift -o Yakeng-arm64 2>/dev/null \
   && swiftc -O -target x86_64-apple-macos11 Sources/main.swift -o Yakeng-x86_64 2>/dev/null; then
  lipo -create Yakeng-arm64 Yakeng-x86_64 -output "$APP/Contents/MacOS/Yakeng"
  rm -f Yakeng-arm64 Yakeng-x86_64
else
  echo "   (Không build được universal, dùng kiến trúc hiện tại)"
  rm -f Yakeng-arm64 Yakeng-x86_64
  swiftc -O Sources/main.swift -o "$APP/Contents/MacOS/Yakeng"
fi

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Yakeng</string>
  <key>CFBundleDisplayName</key><string>Yakeng</string>
  <key>CFBundleIdentifier</key><string>com.impadx.yakeng</string>
  <key>CFBundleExecutable</key><string>Yakeng</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP"

echo "==> Đang tạo $DMG ..."
mkdir -p dmg-root
cp -R "$APP" dmg-root/
ln -s /Applications dmg-root/Applications
hdiutil create -volname "Yakeng" -srcfolder dmg-root -ov -format UDZO "$DMG" >/dev/null
rm -rf dmg-root

echo
echo "Xong!"
echo "  App: $PWD/$APP"
echo "  DMG: $PWD/$DMG"
echo
echo "Cài trên máy khác: mở Yakeng.dmg, kéo Yakeng vào Applications,"
echo "lần đầu nhấp chuột phải vào app -> Open, rồi bật quyền Accessibility khi được hỏi."
open -R "$DMG"
echo
read -n 1 -s -r -p "Nhấn phím bất kỳ để đóng cửa sổ này..."
