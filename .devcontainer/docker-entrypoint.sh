#!/usr/bin/env bash
# Container entrypoint. Runs as root on every container start, then hands off
# to the container command (`sleep infinity` by default).
#
# 1. Named volumes are created owned by root, and volumes created before Dev
#    Containers remapped the vscode UID to the host UID are owned by the old
#    UID. Fix both so the vscode user can write to them.
# 2. Keep ~/.claude.json (a single file) persisted by symlinking it into the
#    persisted ~/.claude volume.
set -euo pipefail

USER_NAME=vscode
USER_HOME=/home/${USER_NAME}
USER_UID=$(id -u "$USER_NAME")
USER_GID=$(id -g "$USER_NAME")

# Persisted agent-state paths (named volumes declared in compose.yaml).
AGENT_STATE_PATHS=(
    "$USER_HOME/.copilot"
    "$USER_HOME/.vscode-server/data/agentSessionData"
    "$USER_HOME/.vscode-server/data/User/globalStorage"
    "$USER_HOME/.claude"
)

# Extra volume paths (separate_mounts, persistent_volumes) come from
# compose.local.yaml as a colon-separated list.
IFS=':' read -r -a EXTRA_PATHS <<< "${META_REPO_VOLUME_PATHS:-}"

# chown the parent directories of a mount point (non-recursively) up to, but
# not including, $USER_HOME or /workspace. Docker creates missing parents as root.
fix_parents() {
    local dir
    dir=$(dirname "$1")
    while [[ "$dir" == "$USER_HOME"/* || "$dir" == /workspace/* ]]; do
        if [[ -d "$dir" && "$(stat -c %u "$dir")" != "$USER_UID" ]]; then
            chown "$USER_UID:$USER_GID" "$dir"
        fi
        dir=$(dirname "$dir")
    done
}

# Recursively chown a volume only when its root isn't owned by vscode, so
# large caches aren't re-walked on every start.
fix_volume() {
    local path=$1
    [[ -n "$path" ]] || return 0
    mkdir -p "$path"
    fix_parents "$path"
    if [[ "$(stat -c %u "$path")" != "$USER_UID" || "$(stat -c %g "$path")" != "$USER_GID" ]]; then
        echo "[meta-repo] fixing ownership of $path"
        chown -R "$USER_UID:$USER_GID" "$path"
    fi
}

for p in "${AGENT_STATE_PATHS[@]}" "${EXTRA_PATHS[@]}"; do
    fix_volume "$p"
done

# /workspace itself is not a mount, but may be left with a stale UID after
# Dev Containers remaps the vscode UID. /workspace/.claude is created by Docker
# as root, as the parent of the .claude/skills mount.
chown "$USER_UID:$USER_GID" /workspace
[[ -d /workspace/.claude ]] && chown "$USER_UID:$USER_GID" /workspace/.claude

# ~/.claude.json -> ~/.claude/.claude.json
claude_json="$USER_HOME/.claude.json"
claude_json_persisted="$USER_HOME/.claude/.claude.json"
if [[ -f "$claude_json" && ! -L "$claude_json" ]]; then
    # A regular file: either baked into the image at build time, or the symlink
    # was replaced by an atomic write during a previous run of this container.
    # Keep whichever copy is newer.
    if [[ ! -e "$claude_json_persisted" || "$claude_json" -nt "$claude_json_persisted" ]]; then
        mv "$claude_json" "$claude_json_persisted"
    else
        rm -f "$claude_json"
    fi
fi
ln -sfn "$claude_json_persisted" "$claude_json"
chown -h "$USER_UID:$USER_GID" "$claude_json"
[[ -e "$claude_json_persisted" ]] && chown "$USER_UID:$USER_GID" "$claude_json_persisted"

exec "$@"
