#!/bin/bash

# NotchPomodoro 构建脚本
# 创建 .app 包结构

set -e

APP_NAME="NotchPomodoro"
BUILD_DIR=".build/release"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "🔨 编译 Release 版本..."
swift build -c release

echo "📦 创建 .app 包..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# 复制可执行文件
cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/"

# 复制 Info.plist
cp "Sources/App/Info.plist" "${CONTENTS_DIR}/"

# 复制 entitlements（用于签名）
cp "Sources/App/NotchPomodoro.entitlements" "${CONTENTS_DIR}/"

# 复制应用图标
cp "Sources/Resources/AppIcon.icns" "${RESOURCES_DIR}/"

echo "✅ 构建完成: ${APP_BUNDLE}"
echo ""
echo "运行方式:"
echo "  open ${APP_BUNDLE}"
echo ""
echo "或复制到 Applications:"
echo "  cp -r ${APP_BUNDLE} /Applications/"
