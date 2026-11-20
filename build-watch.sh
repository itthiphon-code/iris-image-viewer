#!/bin/bash
# ตัวรอ build สำหรับให้ Claude วนแก้ error
# - เมื่อไฟล์ .rebuild เปลี่ยน จะรัน swift build แล้วเขียนผลไว้ที่ build.log / build.status
# - เมื่อไฟล์ .launch เปลี่ยน จะสร้าง Iris.app แล้วเปิดดูว่า crash หรือไม่ (ผลอยู่ที่ launch.log)
# กด Control+C เพื่อหยุด
cd "$(dirname "$0")"
{
  echo "swift: $(swift --version 2>&1 | head -2 | tr '\n' ' ')"
  echo "xcode-select: $(xcode-select -p 2>&1)"
  sw_vers
  uname -m
} > build.env 2>&1
cat build.env

[ -f .rebuild ] || date +%s > .rebuild
[ -f .launch ] || echo 0 > .launch
last_build=""
last_launch=$(cat .launch)

while true; do
  cur=$(cat .rebuild 2>/dev/null)
  if [ "$cur" != "$last_build" ]; then
    last_build=$cur
    echo "=== build $(date '+%H:%M:%S') ==="
    echo running > build.status
    swift build > build.log 2>&1
    code=$?
    echo $code > build.status
    echo "ผล: $code ($(grep -c 'error:' build.log) errors)"
  fi

  cur=$(cat .launch 2>/dev/null)
  if [ "$cur" != "$last_launch" ]; then
    last_launch=$cur
    echo "=== package + launch $(date '+%H:%M:%S') ==="
    {
      ./build-app.sh 2>&1
      pkill -x Iris 2>/dev/null
      sleep 1
      open build/Iris.app
      sleep 10
      if pgrep -x Iris >/dev/null; then echo "LAUNCH: running"; else echo "LAUNCH: not running"; fi
      crash=$(ls -t ~/Library/Logs/DiagnosticReports/Iris* 2>/dev/null | head -1)
      if [ -n "$crash" ] && [ $(( $(date +%s) - $(stat -f %m "$crash") )) -lt 60 ]; then
        echo "CRASH REPORT: $crash"
        head -120 "$crash"
      fi
    } > launch.log 2>&1
    tail -3 launch.log
  fi
  sleep 2
done
