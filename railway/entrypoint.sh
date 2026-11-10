#!/bin/bash
# Start script for Evolution API on Railway.
#
# The upstream entrypoint migrates once and exits if Postgres isn't up yet, and runs the API
# under npm. This one:
#   1. refuses to start with an empty API key or the public default baked into the image;
#   2. waits for Postgres (by retrying the migration) and for Redis, which holds WhatsApp's
#      encryption keys: starting without it makes paired numbers lose their sessions;
#   3. caps Node's heap on small plans so the API collects garbage before the container is killed;
#   4. runs `node dist/main` directly and restarts it if it dies, so one crash doesn't use up
#      Railway's restart limit and leave the API down.
set -u
cd /evolution
log() { echo "[railway] $*"; }

UPSTREAM_DEFAULT_KEY=429683C4C977415CAAFCCE10F7D57E11
if [ -z "${AUTHENTICATION_API_KEY:-}" ] || [ "$AUTHENTICATION_API_KEY" = "$UPSTREAM_DEFAULT_KEY" ]; then
  log "AUTHENTICATION_API_KEY is empty or is the public default from the upstream image."
  log "Anyone could control your WhatsApp numbers with it. Set a private value and redeploy."
  exit 1
fi
if [ -z "${DATABASE_CONNECTION_URI:-}" ]; then
  log "DATABASE_CONNECTION_URI is not set. Point it at the Postgres service and redeploy."
  exit 1
fi

# Listen where Railway routes traffic.
export SERVER_PORT="${SERVER_PORT:-${PORT:-8080}}"

# Small plans: cap the heap at 60% of the container limit (Free is 0.5 GB, Trial 1 GB).
limit=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo max)
if [ -z "${NODE_OPTIONS:-}" ] && [ "$limit" != "max" ]; then
  limit_mb=$((limit / 1048576))
  if [ "$limit_mb" -le 2048 ]; then
    export NODE_OPTIONS="--max-old-space-size=$((limit_mb * 60 / 100))"
    log "memory limit ${limit_mb} MB: Node heap capped at $((limit_mb * 60 / 100)) MB"
  fi
fi

# Postgres: retry the migration until the database answers. A fresh Postgres needs a few
# seconds to initialise, and private DNS isn't always ready at the first try.
deadline=$(( $(date +%s) + ${DB_WAIT_SECONDS:-300} ))
attempt=0
while :; do
  attempt=$((attempt + 1))
  if npm run --silent db:deploy >/tmp/migrate.log 2>&1; then
    log "database migrations applied (attempt $attempt)"
    break
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    log "migrations still failing after ${DB_WAIT_SECONDS:-300}s. Last output:"
    tail -n 25 /tmp/migrate.log
    exit 1
  fi
  if grep -qE "P1001|P1002|Can't reach database server|ECONNREFUSED|ENOTFOUND|EAI_AGAIN" /tmp/migrate.log; then
    log "Postgres isn't reachable yet (attempt $attempt), retrying in 5s"
  else
    log "migration failed (attempt $attempt), retrying in 5s:"
    tail -n 8 /tmp/migrate.log
  fi
  sleep 5
done
# The image ships a Prisma client generated for Postgres; other providers need their own.
if [ "${DATABASE_PROVIDER:-postgresql}" != "postgresql" ]; then
  npm run --silent db:generate || { log "prisma generate failed"; exit 1; }
fi

# Redis: don't start until it answers.
if [ "${CACHE_REDIS_ENABLED:-true}" = "true" ]; then
  node railway/wait-redis.js || exit 1
fi

# Optional: delete saved messages older than MESSAGE_RETENTION_DAYS, every 6 hours.
pruner=0
if [[ "${MESSAGE_RETENTION_DAYS:-}" =~ ^[1-9][0-9]*$ ]]; then
  log "message retention on: messages older than ${MESSAGE_RETENTION_DAYS} days are deleted every 6 hours"
  ( sleep 600; while :; do NODE_OPTIONS=--max-old-space-size=96 node railway/prune-messages.js; sleep 21600; done ) &
  pruner=$!
elif [ -n "${MESSAGE_RETENTION_DAYS:-}" ]; then
  log "MESSAGE_RETENTION_DAYS='${MESSAGE_RETENTION_DAYS}' is not a whole number of days: retention is off"
fi

child=0
stop() {
  log "stopping"
  [ "$pruner" -ne 0 ] && kill "$pruner" 2>/dev/null
  if [ "$child" -ne 0 ]; then kill -TERM "$child" 2>/dev/null; wait "$child" 2>/dev/null; fi
  exit 0
}
trap stop TERM INT

# Keep the API running. Five exits within a minute of starting means it can't start at all:
# give up then, so the deployment shows as crashed instead of looping quietly.
fast=0
delay=2
while :; do
  started=$(date +%s)
  node dist/main &
  child=$!
  wait "$child"
  code=$?
  ran=$(( $(date +%s) - started ))
  if [ "$ran" -lt 60 ]; then fast=$((fast + 1)); else fast=0; delay=2; fi
  if [ "$fast" -ge 5 ]; then
    log "Evolution API exited 5 times within a minute of starting (last exit code $code). Giving up."
    exit 1
  fi
  log "Evolution API exited with code $code after ${ran}s, restarting in ${delay}s"
  sleep "$delay"
  delay=$((delay * 2)); [ "$delay" -gt 30 ] && delay=30
done
