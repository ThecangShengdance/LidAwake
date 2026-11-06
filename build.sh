#!/bin/bash
# 构建 LidAwake.app 到 Dist/ 目录
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-Release}"
DERIVED=".build/dd"
OUT="Dist"

xcodebuild \
  -project LidAwake.xcodeproj \
  -scheme LidAwake \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  build

mkdir -p "$OUT"
rm -rf "$OUT/LidAwake.app"
cp -R "$DERIVED/Build/Products/$CONFIG/LidAwake.app" "$OUT/LidAwake.app"
xattr -cr "$OUT/LidAwake.app" 2>/dev/null || true
codesign --force --deep --sign - "$OUT/LidAwake.app" >/dev/null 2>&1 || true

echo "✅ 已生成: $(pwd)/$OUT/LidAwake.app"
echo "   安装：拖到「应用程序」文件夹后双击运行（菜单栏会出现笔记本图标）"
