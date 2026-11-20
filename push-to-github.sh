#!/bin/bash
# อัปโหลดโปรเจกต์ Iris ขึ้น GitHub (repo แบบ private)
# ใช้: ./push-to-github.sh [ชื่อ-repo]   (ค่าเริ่มต้น iris-image-viewer)
set -e
cd "$(dirname "$0")"
REPO="${1:-iris-image-viewer}"

if ! command -v gh >/dev/null 2>&1; then
  echo "❌ ยังไม่มีคำสั่ง gh (GitHub CLI)"
  echo "   ติดตั้งด้วย:  brew install gh   แล้วรัน  gh auth login  จากนั้นรันสคริปต์นี้อีกครั้ง"
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "▸ ยังไม่ได้ล็อกอิน GitHub — กำลังเปิดหน้าล็อกอิน"
  gh auth login --web --git-protocol https
fi

if [ ! -d .git ]; then
  git init -q -b main
fi
git add -A
if ! git diff --cached --quiet; then
  git commit -q -m "Iris: ACDSee-style image viewer for macOS (Phase 1–4, builds on macOS 26)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017QFZezzZJ3Yetu3krjMG4J"
fi

if git remote get-url origin >/dev/null 2>&1; then
  git push -u origin main
else
  gh repo create "$REPO" --private --source . --remote origin --push \
    --description "Iris — โปรแกรมดูรูปภาพแนว ACDSee สำหรับ macOS (Swift + SwiftUI)"
fi
echo "✅ เสร็จแล้ว: $(gh repo view --json url -q .url)"
