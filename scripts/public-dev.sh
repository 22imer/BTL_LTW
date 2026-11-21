#!/usr/bin/env bash
# Cloudflare Quick Tunnel cho chế độ dev (Vite, cổng 5173) để điện thoại quét QR qua HTTPS.
# Việc làm: chạy cloudflared nền, lấy URL, ghi PUBLIC_APP_URL/COOKIE_SECURE vào server/.env.
# Sau khi chạy xong cần khởi động lại `npm run dev` để server đọc env mới.
# Dùng: scripts/public-dev.sh        (bật)   |   scripts/public-dev.sh stop   (tắt + trả env về localhost)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/server/.env"
LOG="$ROOT/.cache/tunnel.log"
CF="${CLOUDFLARED:-cloudflared}"
LOCAL_URL="http://localhost:5173"

set_env() {
  local key="$1" val="$2"
  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$val" >> "$ENV_FILE"
  fi
}

[ -f "$ENV_FILE" ] || { echo "Thiếu $ENV_FILE (tạo từ .env.example trước)" >&2; exit 1; }
pkill -f "cloudflared tunnel --no-autoupdate" 2>/dev/null || true

if [ "${1:-}" = "stop" ]; then
  set_env PUBLIC_APP_URL "$LOCAL_URL"
  set_env COOKIE_SECURE false
  echo "Đã tắt tunnel, PUBLIC_APP_URL=$LOCAL_URL. Khởi động lại npm run dev."
  exit 0
fi

command -v "$CF" >/dev/null || { echo "Không thấy cloudflared (đặt biến CLOUDFLARED=/đường/dẫn)" >&2; exit 1; }
mkdir -p "$ROOT/.cache"
: > "$LOG"
setsid nohup "$CF" tunnel --no-autoupdate --url "$LOCAL_URL" > "$LOG" 2>&1 < /dev/null &

url=""
for _ in $(seq 1 40); do
  url="$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG" | head -1 || true)"
  [ -n "$url" ] && break
  sleep 1
done
[ -n "$url" ] || { echo "Không lấy được URL tunnel, xem $LOG" >&2; exit 1; }

# Khách đi qua URL công khai; Staff/Admin vẫn dùng localhost (cùng cổng dev, đều nằm trong allowedOrigins).
set_env PUBLIC_APP_URL "$url"
set_env STAFF_APP_URL "$LOCAL_URL"
set_env ADMIN_APP_URL "$LOCAL_URL"
set_env COOKIE_SECURE true
echo "$url" > "$ROOT/.cache/public-url.txt"

echo "Tunnel: $url"
echo "Đã cập nhật server/.env. Khởi động lại npm run dev, rồi mở Bàn & phiên → Xem QR tĩnh để lấy QR mới."
