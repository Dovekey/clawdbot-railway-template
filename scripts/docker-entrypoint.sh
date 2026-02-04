#!/bin/sh
# Docker entrypoint script for OpenClaw
# Handles data directory permissions gracefully for Railway volume mounts

set -e

echo "[entrypoint] Starting OpenClaw data directory setup..."
echo "[entrypoint] Current user: $(whoami) (uid=$(id -u), gid=$(id -g))"

# Default data directory (may be overridden by environment)
DATA_BASE="${DATA_DIR:-/data}"
DESIRED_STATE_DIR="${OPENCLAW_STATE_DIR:-$DATA_BASE/.openclaw}"
DESIRED_WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-$DESIRED_STATE_DIR/workspace}"

# Fallback locations if primary isn't writable
# Home directory should now exist (created in Dockerfile)
FALLBACK_STATE_DIR="${HOME:-/home/openclaw}/.openclaw"
FALLBACK_WORKSPACE_DIR="$FALLBACK_STATE_DIR/workspace"

echo "[entrypoint] Desired state dir: $DESIRED_STATE_DIR"
echo "[entrypoint] Desired workspace dir: $DESIRED_WORKSPACE_DIR"
echo "[entrypoint] Fallback state dir: $FALLBACK_STATE_DIR"

# Debug: Show what exists at /data
if [ -d "$DATA_BASE" ]; then
    echo "[entrypoint] $DATA_BASE exists with permissions:"
    ls -la "$DATA_BASE" 2>/dev/null || echo "[entrypoint] Cannot list $DATA_BASE"
    echo "[entrypoint] $DATA_BASE mount info:"
    df -h "$DATA_BASE" 2>/dev/null || echo "[entrypoint] Cannot get df for $DATA_BASE"
else
    echo "[entrypoint] WARNING: $DATA_BASE does not exist!"
    echo "[entrypoint] This usually means no Railway volume is mounted."
    echo "[entrypoint] Data will NOT persist across container restarts!"
fi

# Function to setup directories (tests file writes AND subdirectory creation)
setup_directories() {
    state_dir="$1"
    workspace_dir="$2"

    echo "[entrypoint] Testing directory: $state_dir"

    # Try to create directories
    if ! mkdir -p "$state_dir" 2>/dev/null; then
        echo "[entrypoint] FAILED: Cannot create $state_dir"
        return 1
    fi

    if ! mkdir -p "$workspace_dir" 2>/dev/null; then
        echo "[entrypoint] FAILED: Cannot create $workspace_dir"
        return 1
    fi

    # Verify we can write files to state dir
    if ! (touch "$state_dir/.write-test" 2>/dev/null && rm -f "$state_dir/.write-test"); then
        echo "[entrypoint] FAILED: Cannot write files to $state_dir"
        return 1
    fi

    # Verify we can write files to workspace dir
    if ! (touch "$workspace_dir/.write-test" 2>/dev/null && rm -f "$workspace_dir/.write-test"); then
        echo "[entrypoint] FAILED: Cannot write files to $workspace_dir"
        return 1
    fi

    # Verify we can create subdirectories (critical for workspace operations)
    if ! (mkdir -p "$state_dir/.subdir-test" 2>/dev/null && rmdir "$state_dir/.subdir-test"); then
        echo "[entrypoint] FAILED: Cannot create subdirectories in $state_dir"
        return 1
    fi

    echo "[entrypoint] SUCCESS: $state_dir is writable"
    return 0
}

# Try primary location first (/data)
if setup_directories "$DESIRED_STATE_DIR" "$DESIRED_WORKSPACE_DIR"; then
    echo "[entrypoint] ✓ Using persistent data directory: $DESIRED_STATE_DIR"
    export OPENCLAW_STATE_DIR="$DESIRED_STATE_DIR"
    export OPENCLAW_WORKSPACE_DIR="$DESIRED_WORKSPACE_DIR"
    export OPENCLAW_DATA_PERSISTENT="true"
else
    echo "[entrypoint] ========================================"
    echo "[entrypoint] WARNING: Cannot write to $DESIRED_STATE_DIR"
    echo "[entrypoint] ========================================"
    echo "[entrypoint] Possible causes:"
    echo "[entrypoint]   1. No Railway volume mounted at /data"
    echo "[entrypoint]   2. Volume has incorrect permissions"
    echo "[entrypoint]   3. Volume is read-only"
    echo "[entrypoint] Trying fallback: $FALLBACK_STATE_DIR"
    echo "[entrypoint] ========================================"

    if setup_directories "$FALLBACK_STATE_DIR" "$FALLBACK_WORKSPACE_DIR"; then
        export OPENCLAW_STATE_DIR="$FALLBACK_STATE_DIR"
        export OPENCLAW_WORKSPACE_DIR="$FALLBACK_WORKSPACE_DIR"
        export OPENCLAW_DATA_PERSISTENT="false"
        echo "[entrypoint] ⚠ Using HOME fallback: $FALLBACK_STATE_DIR"
        echo "[entrypoint] ⚠ WARNING: Data will NOT persist across container restarts!"
        echo "[entrypoint] ⚠ To fix: Add a Railway volume mounted at /data"
    else
        echo "[entrypoint] ========================================"
        echo "[entrypoint] CRITICAL ERROR: Cannot create data directory"
        echo "[entrypoint] ========================================"
        echo "[entrypoint] Both primary and fallback locations failed."
        echo "[entrypoint] Please ensure the container has write permissions to either:"
        echo "[entrypoint]   - $DATA_BASE (Railway volume - recommended)"
        echo "[entrypoint]   - $HOME (container home directory)"
        echo "[entrypoint] ========================================"

        # Last resort: use /tmp but LOUDLY warn about it
        TMP_STATE_DIR="/tmp/.openclaw-$$"
        TMP_WORKSPACE_DIR="$TMP_STATE_DIR/workspace"

        if setup_directories "$TMP_STATE_DIR" "$TMP_WORKSPACE_DIR"; then
            export OPENCLAW_STATE_DIR="$TMP_STATE_DIR"
            export OPENCLAW_WORKSPACE_DIR="$TMP_WORKSPACE_DIR"
            export OPENCLAW_DATA_PERSISTENT="false"
            echo "[entrypoint] ⚠⚠⚠ USING /tmp AS LAST RESORT ⚠⚠⚠"
            echo "[entrypoint] ⚠⚠⚠ ALL DATA WILL BE LOST ON RESTART! ⚠⚠⚠"
        else
            echo "[entrypoint] FATAL: Cannot create any data directory"
            exit 1
        fi
    fi
fi

# Final status
echo "[entrypoint] ========================================"
echo "[entrypoint] Data directory configuration:"
echo "[entrypoint]   STATE_DIR: $OPENCLAW_STATE_DIR"
echo "[entrypoint]   WORKSPACE_DIR: $OPENCLAW_WORKSPACE_DIR"
echo "[entrypoint]   PERSISTENT: ${OPENCLAW_DATA_PERSISTENT:-unknown}"
echo "[entrypoint] ========================================"

# Execute the main command
exec "$@"
