#!/usr/bin/env bash
# 构建 release APK。
#
# 为什么不在项目目录直接构建：AOT 编译器 gen_snapshot 按 ANSI 读路径，
# 项目路径含中文时 release 必挂（debug 走 JIT 不受影响）。所以同步到英文路径再编。
#
# 用法：bash _source/build_release.sh [--abi arm64-v8a]
set -euo pipefail

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-/d/build/mw_english}"
export JAVA_HOME="${JAVA_HOME:-D:/Develop/JDK21}"
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
FLUTTER="${FLUTTER:-/d/Develop/flutter/bin/flutter.bat}"

if [[ "$PROJ" =~ [^\x00-\x7F] ]]; then
  echo "项目路径含非 ASCII 字符，需经英文路径构建：$PROJ"
  echo "同步到 $BUILD_DIR ..."
  mkdir -p "$BUILD_DIR"
  # 注意：不要用 robocopy —— 经 bash 传中文路径会编码错误且静默失败，
  # 结果目标目录一直是旧的，构建产出看似成功但内容没更新。
  # 源码目录整体替换，避免旧文件残留（如上一版字体）。
  rm -rf "$BUILD_DIR/lib" "$BUILD_DIR/assets" "$BUILD_DIR/test"
  cp -r "$PROJ/app/lib" "$PROJ/app/assets" "$BUILD_DIR/"
  cp "$PROJ/app/pubspec.yaml" "$PROJ/app/pubspec.lock" "$BUILD_DIR/"
  [[ -d "$PROJ/app/test" ]] && cp -r "$PROJ/app/test" "$BUILD_DIR/"

  # 校验同步结果，防止再次静默失配
  if ! diff -rq "$PROJ/app/lib" "$BUILD_DIR/lib" >/dev/null; then
    echo "同步校验失败：$BUILD_DIR/lib 与源码不一致" >&2
    exit 1
  fi
else
  BUILD_DIR="$PROJ/app"
fi

cd "$BUILD_DIR"
echo "构建目录: $BUILD_DIR"
"$FLUTTER" build apk --release --split-per-abi "${@}"

echo
echo "产物："
ls -lh "$BUILD_DIR/build/app/outputs/flutter-apk/"*release.apk
