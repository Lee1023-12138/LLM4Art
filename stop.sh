#!/usr/bin/env bash
set -euo pipefail

# ---------------------------
# Config (env first, then .env)
# ---------------------------

# Default names (must match ecosystem.config.js)
: "${APP_NAMES:=llm4art-server llm4art-static}"

# Default ports
: "${PORT:=8787}"              # backend port
: "${FRONTEND_PORT:=5500}"     # static server port

PURGE_PM2=false
if [[ "${1:-}" == "--purge" ]]; then
  PURGE_PM2=true
fi

# Load .env if present (does NOT override already-set env)
if [ -f ".env" ]; then
  # shellcheck disable=SC1091
  set -a
  while IFS='=' read -r k v; do
    [[ "$k" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    [[ -z "${!k:-}" ]] && export "$k"="$v"
  done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' .env | sed 's/\r$//')
  set +a
fi

cd "$(dirname "$0")"

say() { printf '%b\n' "$*"; }
hr()  { printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' -; }

pm2_exists() {
  local name="$1"
  pm2 describe "$name" >/dev/null 2>&1
}

wait_port_free() {
  # wait_port_free <port> <timeout_sec>
  local p="$1" timeout="${2:-10}" i=0
  if ! command -v lsof >/dev/null 2>&1; then
    # no lsof; best-effort sleep
    sleep 1
    return 0
  fi
  while (( i < timeout )); do
    if ! lsof -ti tcp:"$p" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1; ((i++))
  done
  return 1
}

force_kill_port() {
  local p="$1"
  if command -v lsof >/dev/null 2>&1; then
    local pids
    pids="$(lsof -ti tcp:"$p" 2>/dev/null || true)"
    if [ -n "$pids" ]; then
      say "  -> Force killing PIDs on :$p -> $pids"
      kill -9 $pids 2>/dev/null || true
    fi
  fi
}

# ---------------------------
# 1) Stop & delete PM2 apps
# ---------------------------
if ! command -v pm2 >/dev/null 2>&1; then
  say "WARN: pm2 not found. Skipping PM2 stop/delete."
else
  say "[1/3] Stopping PM2 apps..."
  for name in $APP_NAMES; do
    if pm2_exists "$name"; then
      say "  -> pm2 stop $name"
      pm2 stop "$name" || true
    else
      say "  -> $name not found (skipping stop)"
    fi
  done

  say "Deleting PM2 apps..."
  for name in $APP_NAMES; do
    if pm2_exists "$name"; then
      say "  -> pm2 delete $name"
      pm2 delete "$name" || true
    else
      say "  -> $name not found (skipping delete)"
    fi
  done

  if $PURGE_PM2; then
    say "Purging PM2 daemon: pm2 kill"
    pm2 kill || true
  fi
fi

# ---------------------------
# 2) Ensure ports are free
# ---------------------------
say "[2/3] Ensuring ports are free: :$PORT and :$FRONTEND_PORT"
for P in "$PORT" "$FRONTEND_PORT"; do
  if wait_port_free "$P" 10; then
    say "  -> Port :$P is free."
  else
    say "  -> Port :$P still busy; attempting force kill..."
    force_kill_port "$P"
    if wait_port_free "$P" 5; then
      say "  -> Port :$P cleared."
    else
      say "WARN: Port :$P may still be occupied."
    fi
  fi
done

# ---------------------------
# 3) Show PM2 status (if available)
# ---------------------------
say "[3/3] PM2 status:"
if command -v pm2 >/dev/null 2>&1; then
  pm2 status || true
else
  say "  pm2 not installed; nothing to show."
fi

hr
say "Done. All target processes stopped."
say "Tip: restart with: bash start.sh"
