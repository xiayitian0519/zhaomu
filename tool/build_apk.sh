#!/usr/bin/env bash
# 打包朝暮 release APK。
#
# 为什么不用 `flutter build apk`：
#   本机/沙箱直接跑 flutter.bat 会报 "CreateFile failed 231 所有的管道范例都在使用中"
#   （Windows 管道句柄被占），所以改成直接调 Gradle。
#
# 直接调 Gradle 会漏掉 Flutter 工具链做的一件事：
#   把 pubspec.yaml 的 version 同步进 android/local.properties。
#   漏了它，APK 的 versionName 会一直停在旧值（踩过：打了好几个包都是 2.6.1）。
#   所以第一步必须先跑 tool/sync_version.py。
#
# 用法：bash tool/build_apk.sh

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "=== 1/3 同步版本号 pubspec -> local.properties ==="
python tool/sync_version.py

echo
echo "=== 2/3 Gradle 打包 ==="
export GRADLE_USER_HOME=/d/gradle
export PUB_CACHE=/d/pub-cache
# 必须显式给 SDK 路径：local.properties 里的 sdk.dir Flutter 那边不读，
# compileFlutterBuildRelease 会去调 where.EXE 探 SDK，沙箱里探不到就报
# "Android SDK could not be found"
export ANDROID_HOME='D:\Android\Sdk'
export ANDROID_SDK_ROOT='D:\Android\Sdk'
cd android
./gradlew assembleRelease "$@"
cd "$ROOT"

APK=build/app/outputs/flutter-apk/app-release.apk
echo
echo "=== 3/3 核验 ==="
AAPT="$(ls -d /d/Android/Sdk/build-tools/*/aapt2.exe | tail -1)"
echo "-- APK 版本号 --"
"$AAPT" dump badging "$APK" | grep -E "^package:"
echo "-- 铃声资源（必须有 raw/ring_* 四条） --"
"$AAPT" dump resources "$APK" | grep "raw/" || echo "!! 没找到 raw 铃声，检查 res/raw/keep.xml"

VERSION="$(grep -E '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)"
OUT="zhaomu-${VERSION}.apk"   # 带版本号（2026-10-17 用户要求：固定名会互相覆盖分不清版本）
cp "$APK" "$OUT"
echo
echo "产物：$ROOT/$OUT"
