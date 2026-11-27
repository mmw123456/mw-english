#!/usr/bin/env bash
# 构建 release APK。
#
# 项目真身已迁到纯英文路径 D:\ai-projects\mw-english，AOT 编译器（gen_snapshot）不再把
# 中文路径读成 ANSI 乱码，所以直接在工程目录构建，不再需要同步副本。
# 脚本只做两件事：校验路径是纯 ASCII，然后调 flutter build apk。
#
# 用法：bash _source/build_release.sh [--abi arm64-v8a]
set -euo pipefail

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export JAVA_HOME="${JAVA_HOME:-D:/Develop/JDK21}"
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
FLUTTER="${FLUTTER:-/d/Develop/flutter/bin/flutter.bat}"

# 路径守卫：Dart AOT 按 ANSI 读路径，含非 ASCII 字符必挂（踩坑 15）。
# 真身若被搬回中文目录，这里直接拒绝，避免又出现「build 报成功但产物没变」的假象。
# 注意：不要用 bash 的 [[ =~ [^\x00-\x7F] ]] —— ERE 不认 \x 转义，会退化成
# 字符集合 [^\ x 0 - 7 F]，普通 ASCII 路径也会被判成非 ASCII（踩坑 24）。
if printf '%s' "$PROJ" | LC_ALL=C grep -q '[^ -~]'; then
  echo "项目路径含非 ASCII 字符，release 构建会挂：$PROJ" >&2
  echo "请把工程放到纯英文路径（当前约定 D:\\mw-english）。" >&2
  exit 1
fi

cd "$PROJ/app"
echo "构建目录: $PROJ/app"
"$FLUTTER" build apk --release --split-per-abi "${@}"

echo
echo "产物："
ls -lh "$PROJ/app/build/app/outputs/flutter-apk/"*release.apk
