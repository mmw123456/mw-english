#!/usr/bin/env bash
# 跑 flutter test，并且先把代理变量摘掉。
#
# 为什么需要这个脚本：flutter_tester 通过本地回环 WebSocket 跟测试进程通信，
# 设了 http_proxy / https_proxy 时连接会被代理劫持，报
#   Unable to connect to flutter_tester process: WebSocketException:
#   Invalid WebSocket upgrade request
# 四个测试文件会全部「加载失败」，看起来像代码坏了。踩坑 18 / 踩坑 44 各撞过一次，
# 所以做成脚本，别再靠记性。
#
# 用法：bash _source/test.sh            # 全部测试
#       bash _source/test.sh test/choice_test.dart
set -euo pipefail

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export JAVA_HOME="${JAVA_HOME:-D:/Develop/JDK21}"
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
FLUTTER="${FLUTTER:-/d/Develop/flutter/bin/flutter.bat}"

cd "$PROJ/app"
exec env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY \
  -u all_proxy -u ALL_PROXY "$FLUTTER" test "$@"
