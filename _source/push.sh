#!/usr/bin/env bash
# 推 main 到 GitHub，并核对远端真的更新了。
#
# 为什么不直接 python api_push.py：
# 2026-11-26 出现过「脚本退出码 0、但远端 main 没动」的情况（输出停在半途，
# 被管道 tail 截断后看不出来）。发布前必须确认远端头提交，不能凭退出码。
#
# 用法：bash _source/push.sh "提交说明"
set -uo pipefail
cd "$(dirname "$0")/.."

MSG="${1:-chore: sync}"
LOG=/tmp/mw_push.log

python _source/api_push.py --message "$MSG" >"$LOG" 2>&1
RC=$?
tail -6 "$LOG"
if [ $RC -ne 0 ]; then
  echo "推送失败（exit=$RC），完整日志：$LOG"
  exit $RC
fi

python - "$MSG" <<'PY'
import json, subprocess, sys, urllib.request

want = sys.argv[1]
tok = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True, check=True).stdout.strip()
req = urllib.request.Request("https://api.github.com/repos/mmw123456/mw-english/commits/main")
req.add_header("Authorization", "Bearer " + tok)
d = json.load(urllib.request.urlopen(req, timeout=60))
got = d["commit"]["message"].splitlines()[0]
print(f"远端 main: {d['sha'][:7]}  {got}")
if got != want:
    print("远端头提交与本次说明不一致 —— 推送没生效")
    sys.exit(1)
print("核对通过：远端已更新")
PY
