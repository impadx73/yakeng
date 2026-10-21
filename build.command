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
VERSION="2.9"
OUT="$PWD"
pkill -x Yakeng 2>/dev/null || true
sleep 0.5
rm -rf "$OUT/$APP" "$OUT/$DMG" "$OUT/dmg-root" "$OUT/build.log"

# Build và ký trong thư mục tạm: Desktop/iCloud hay gắn thuộc tính Finder khiến codesign từ chối
WORK="$(mktemp -d /tmp/yakeng-build.XXXXXX)"
mkdir -p "$WORK/$APP/Contents/MacOS" "$WORK/$APP/Contents/Resources"

echo "==> Đang biên dịch Yakeng $VERSION (Apple Silicon) ..."
set -o pipefail
if ! swiftc -O -target arm64-apple-macos12.0 -module-name Yakeng Sources/*.swift \
     -o "$WORK/$APP/Contents/MacOS/Yakeng" 2>&1 | tee "$OUT/build.log"; then
  echo
  echo "!!! LỖI BIÊN DỊCH – xem build.log"
  grep -n "error:" "$OUT/build.log" | head -30
  read -n 1 -s -r -p "Nhấn phím bất kỳ để đóng..."
  exit 1
fi

cat > "$WORK/$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Yakeng</string>
  <key>CFBundleDisplayName</key><string>Yakeng</string>
  <key>CFBundleIdentifier</key><string>com.impadx.yakeng</string>
  <key>CFBundleExecutable</key><string>Yakeng</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>github.com/impadx73/yakeng</string>
</dict>
</plist>
PLIST

xattr -cr "$WORK/$APP" 2>/dev/null || true

# --- Chứng chỉ tự ký "Yakeng Dev": tạo một lần, lưu trong Keychain đăng nhập.
# Ký bằng chứng chỉ cố định thì chữ ký không đổi giữa các lần build,
# nên quyền Accessibility/Screen Recording đã cấp được giữ nguyên.
IDENTITY="Yakeng Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
if ! security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "\"$IDENTITY\""; then
  echo "==> Tạo chứng chỉ tự ký '$IDENTITY' (chỉ lần đầu)..."
  CERTDIR="$(mktemp -d /tmp/yakeng-cert.XXXXXX)"
  cat > "$CERTDIR/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY
[v3]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
subjectKeyIdentifier = hash
CNF
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$CERTDIR/cert.cnf" \
    -keyout "$CERTDIR/key.pem" -out "$CERTDIR/cert.pem" >/dev/null 2>&1
  openssl pkcs12 -export -inkey "$CERTDIR/key.pem" -in "$CERTDIR/cert.pem" \
    -out "$CERTDIR/yakeng.p12" -passout pass:yakeng -name "$IDENTITY" >/dev/null 2>&1
  security import "$CERTDIR/yakeng.p12" -k "$KEYCHAIN" -P yakeng \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null
  echo "   macOS có thể hỏi mật khẩu đăng nhập để tin cậy chứng chỉ – hãy nhập và bấm Luôn cho phép."
  security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$CERTDIR/cert.pem" || true
  rm -rf "$CERTDIR"
fi

if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "\"$IDENTITY\"" \
   && codesign --force --sign "$IDENTITY" --identifier com.impadx.yakeng "$WORK/$APP" 2>/dev/null; then
  echo "   Đã ký bằng chứng chỉ '$IDENTITY'."
else
  echo "   (Không dùng được chứng chỉ, ký ad-hoc – mỗi lần build sẽ phải cấp lại quyền Accessibility)"
  codesign --force --sign - "$WORK/$APP"
fi

echo "==> Đang tạo $DMG ..."
mkdir -p "$WORK/dmg-root"
cp -R "$WORK/$APP" "$WORK/dmg-root/"
ln -s /Applications "$WORK/dmg-root/Applications"
hdiutil create -volname "Yakeng" -srcfolder "$WORK/dmg-root" -ov -format UDZO "$WORK/$DMG" >/dev/null 2>&1

ditto "$WORK/$APP" "$OUT/$APP"
cp "$WORK/$DMG" "$OUT/$DMG"
rm -rf "$WORK"

echo
echo "Xong!"
echo "  App: $OUT/$APP"
echo "  DMG: $OUT/$DMG"
echo
echo "Cài trên máy khác: mở Yakeng.dmg, kéo Yakeng vào Applications,"
echo "lần đầu nhấp chuột phải vào app -> Open, rồi bật quyền Accessibility khi được hỏi."
open "$OUT/$APP"
open -R "$OUT/$DMG"
echo
read -n 1 -s -r -p "Nhấn phím bất kỳ để đóng cửa sổ này..."
