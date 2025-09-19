#!/bin/sh
set -eu

ENV_FILE="/app/.env"
PERSIST_ENV_FILE="/data/.env"

# Simple logging helper
log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

if [ -s "$PERSIST_ENV_FILE" ]; then
  log "Using persistent env file: $PERSIST_ENV_FILE"
  rm -f "$ENV_FILE"
  ln -sf "$PERSIST_ENV_FILE" "$ENV_FILE"
elif [ -s "$ENV_FILE" ]; then
  # First run after admin saved in-app .env -> persist it
  log "Found $ENV_FILE, persisting to $PERSIST_ENV_FILE"
  cp "$ENV_FILE" "$PERSIST_ENV_FILE"
  rm -f "$ENV_FILE"
  ln -sf "$PERSIST_ENV_FILE" "$ENV_FILE"
else
  # No env provided -> use .env.example from IAction project as base
  log "No .env found, creating from .env.example at $PERSIST_ENV_FILE"
  if [ -f "/app/.env.example" ]; then
    # Use project's .env.example and adapt for Home Assistant addon
    # Filter and clean: extract only VARIABLE=value, remove inline comments
    grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "/app/.env.example" | \
    sed 's/#.*$//' | \
    sed 's/[[:space:]]*$//' | \
    grep -v '^[[:space:]]*$' > "$PERSIST_ENV_FILE"
    log "Used .env.example as base"
  else
    # Fallback to minimal default if .env.example not found
    {
      echo "AI_API_MODE=lmstudio"
      echo "AI_TIMEOUT=60"
      echo "AI_STRICT_OUTPUT=false"
      echo "LOG_LEVEL=INFO"
      echo "OPENAI_API_KEY="
      echo "OPENAI_MODEL=gpt-4o"
      echo "LMSTUDIO_URL=http://127.0.0.1:11434/v1"
      echo "LMSTUDIO_MODEL="
      echo "OLLAMA_URL=http://127.0.0.1:11434/v1"
      echo "OLLAMA_MODEL="
      echo "MQTT_BROKER=core-mosquitto"
      echo "MQTT_PORT=1883"
      echo "MQTT_USERNAME="
      echo "MQTT_PASSWORD="
      echo "HA_DEVICE_NAME=IAction"
      echo "HA_DEVICE_ID=iaction_camera_ai"
      echo "CAPTURE_MODE=rtsp"
      echo "DEFAULT_RTSP_URL="
      echo "RTSP_USERNAME="
      echo "RTSP_PASSWORD="
      echo "HA_BASE_URL="
      echo "HA_TOKEN="
      echo "HA_ENTITY_ID="
      echo "HA_IMAGE_ATTR=entity_picture"
      echo "HA_POLL_INTERVAL=1.0"
      echo "MIN_ANALYSIS_INTERVAL=0.1"
    } > "$PERSIST_ENV_FILE"
    log "Used fallback defaults"
  fi
  rm -f "$ENV_FILE"
  ln -sf "$PERSIST_ENV_FILE" "$ENV_FILE"
  log ".env generated at ${ENV_FILE} (persisted in ${PERSIST_ENV_FILE})"
fi

# Export variables so the app always sees them
log "Loading environment from $ENV_FILE"
log "Complete .env file content:"
cat -n "$ENV_FILE" | while read line; do log "  $line"; done

set -a
. "$ENV_FILE"
set +a

# Persist detections.json
if [ ! -f "/data/detections.json" ]; then
  echo '{}' > "/data/detections.json"
fi
ln -sf "/data/detections.json" "/app/detections.json"

# Try to update source code to latest on container start (non-fatal)
if command -v git >/dev/null 2>&1 && [ -d "/app/.git" ]; then
  log "Attempting git pull to update IAction..."
  git config --global --add safe.directory /app || true
  if (cd /app && git pull --ff-only); then
    log "Git update complete"
  else
    log "Fast-forward pull failed (force-push or divergence). Attempting hard reset to origin/main..."
    if (cd /app && git fetch --depth 1 origin main && git reset --hard origin/main); then
      log "Hard reset to origin/main complete"
    else
      log "Git update failed or no network; continuing with existing code"
    fi
  fi
else
  log "Skipping git update (git not available or /app is not a git repo)"
fi

log "Starting IAction application..."

# Start the main application
exec python -u app.py
