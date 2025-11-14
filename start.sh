#!/usr/bin/env bash
set -euo pipefail

# ---------------------------
# Config (env first, then .env)
# ---------------------------

# Default ports
: "${PORT:=8787}"              # backend port
: "${FRONTEND_PORT:=5500}"     # static server port
: "${ECOSYSTEM_FILE:=ecosystem.config.js}"

# Load .env if present (does NOT override already-set env)
if [ -f ".env" ]; then
  # shellcheck disable=SC1091
  set -a
  # only export lines like KEY=VAL (ignore comments/blank)
  while IFS='=' read -r k v; do
    [[ "$k" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    [[ -z "${!k:-}" ]] && export "$k"="$v"
  done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' .env | sed 's/\r$//')
  set +a
fi

# -------------
# Init
# -------------
cd "$(dirname "$0")"  # ensure we run in App directory
mkdir -p logs

say() { printf '%b\n' "$*"; }
hr() { printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' -; }

# -------------
# Helpers
# -------------
wait_for_http() {
  # wait_for_http <url> <timeout_sec>
  local url="$1" timeout="${2:-15}" i=0
  while (( i < timeout )); do
    if command -v curl >/dev/null 2>&1; then
      if curl -sk --max-time 2 "$url" >/dev/null; then
        return 0
      fi
    else
      # if curl is missing, just sleep a bit and assume ok later
      sleep 1
      ((i++))
      continue
    fi
    sleep 1; ((i++))
  done
  return 1
}

clean_port() {
  # clean_port <port>
  local p="$1"
  if command -v lsof >/dev/null 2>&1; then
    local pids
    pids="$(lsof -ti tcp:"$p" 2>/dev/null || true)"
    if [ -n "$pids" ]; then
      say "  -> Killing PIDs on :$p -> $pids"
      # try graceful
      kill $pids 2>/dev/null || true
      sleep 0.5
      # still alive?
      if lsof -ti tcp:"$p" >/dev/null 2>&1; then
        kill -9 $pids 2>/dev/null || true
      fi
    else
      say "  -> No process on :$p"
    fi
  else
    say "  lsof not found; skip port cleanup for :$p"
  fi
}

# -------------
# Step 1: cleanup residual processes on ports
# -------------
say "[1/5] Cleaning residual processes on ports :$PORT and :$FRONTEND_PORT (if any)..."
clean_port "$PORT"
clean_port "$FRONTEND_PORT"

# -------------
# Step 2: start/reload pm2 apps
# -------------
say "[2/5] Starting / reloading PM2 apps..."
if ! command -v pm2 >/dev/null 2>&1; then
  say "ERROR: pm2 not found. Install with: npm i -g pm2"
  exit 1
fi

if [ ! -f "$ECOSYSTEM_FILE" ]; then
  say "ERROR: $ECOSYSTEM_FILE not found in $(pwd)"
  exit 1
fi

if pm2 --help 2>/dev/null | grep -q "startOrReload"; then
  pm2 startOrReload "$ECOSYSTEM_FILE"
else
  # fallback: try start; if failure, try reload
  pm2 start "$ECOSYSTEM_FILE" || pm2 reload "$ECOSYSTEM_FILE"
fi

# -------------
# Step 3: save pm2 process list
# -------------
say "[3/5] Saving PM2 process list for startup on boot..."
pm2 save

# -------------
# Step 4: health checks (backend + frontend)
# -------------
BACKEND_URL="http://localhost:${PORT}/api/health"
FRONTEND_URL="http://localhost:${FRONTEND_PORT}/index.html"

say "[4/5] Waiting for backend health: ${BACKEND_URL}"
if wait_for_http "$BACKEND_URL" 20; then
  if command -v curl >/dev/null 2>&1; then
    say "  -> Backend says: $(curl -s "$BACKEND_URL")"
  else
    say "  -> Backend reachable."
  fi
else
  say "WARN: Backend health endpoint not reachable (timeout)."
fi

say "    Waiting for frontend page:  ${FRONTEND_URL}"
if wait_for_http "$FRONTEND_URL" 20; then
  if command -v curl >/dev/null 2>&1; then
    title="$(curl -s "$FRONTEND_URL" | sed -n 's:.*<title>\(.*\)</title>.*:\1:p' | head -n1)"
    [ -n "$title" ] && say "  -> Frontend <title>: $title" || say "  -> Frontend reachable."
  else
    say "  -> Frontend reachable."
  fi
else
  say "WARN: Frontend not reachable (timeout)."
fi

# -------------
# Step 5: show pm2 status + helpful URLs
# -------------
say "[5/5] PM2 status:"
pm2 status || true
hr
say "Frontend: ${FRONTEND_URL}"
say "Health:   ${BACKEND_URL}"
hr
say "Tips:"
say "  • If using VS Code Remote-SSH, forward ports ${FRONTEND_PORT} and ${PORT} to your local machine."
say "  • Then open the URLs above in your local browser."
say "Done."
