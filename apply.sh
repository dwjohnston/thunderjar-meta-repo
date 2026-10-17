#!/usr/bin/env bash
# Generate .devcontainer/compose.local.yaml from meta-repo.yaml and
# meta-repo.local.yaml.
#
# Usage: ./apply.sh [--admin]
#
#   --admin   Also mount this repo into the container at /workspace/<repo dir>,
#             so the meta-repo itself can be edited from inside the container.
#
# Requires mikefarah/yq v4 on the host. Compatible with macOS's bash 3.2.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_NAME=$(basename "$SCRIPT_DIR")
SHARED="$SCRIPT_DIR/meta-repo.yaml"
LOCAL="$SCRIPT_DIR/meta-repo.local.yaml"
STATIC_COMPOSE="$SCRIPT_DIR/.devcontainer/compose.yaml"
OUT="$SCRIPT_DIR/.devcontainer/compose.local.yaml"
ROOT_FILES_DIR="$SCRIPT_DIR/.root"

ADMIN=false

usage() {
    sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
    case "$arg" in
        --admin) ADMIN=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "apply.sh: unknown argument: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

die() { echo "apply.sh: error: $*" >&2; exit 1; }
ERRORS=0
err() { echo "  ✗ $*" >&2; ERRORS=$((ERRORS + 1)); }
warn() { echo "  ! $*" >&2; }

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
if ! command -v yq >/dev/null 2>&1; then
    die "yq is required but was not found.
  Install mikefarah/yq v4: https://github.com/mikefarah/yq#install
  (macOS: brew install yq)"
fi
if ! yq --version 2>&1 | grep -q 'mikefarah'; then
    die "found '$(command -v yq)', but it is not mikefarah/yq v4 (the Python yq wrapper is not supported).
  Install mikefarah/yq: https://github.com/mikefarah/yq#install"
fi

[[ -f "$SHARED" ]] || die "missing $SHARED"
[[ -f "$LOCAL" ]] || die "missing meta-repo.local.yaml. Create it from the template:
  cp meta-repo.local.yaml.template meta-repo.local.yaml"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
MERGED="$TMP_DIR/merged.yaml"
GEN="$TMP_DIR/compose.local.yaml"

# ---------------------------------------------------------------------------
# Merge shared + local config
#   - scalars and maps: local overrides shared (deep merge)
#   - folders: concatenated, then entries with the same `path` are merged
#     (separate_mounts and ignore are combined)
# ---------------------------------------------------------------------------
yq eval-all '. as $d ireduce ({}; . * (($d // {}) | del(.folders)))' "$SHARED" "$LOCAL" > "$TMP_DIR/base.yaml" \
    || die "could not parse meta-repo.yaml / meta-repo.local.yaml"
yq eval-all -o=json -I0 '. as $d ireduce ([]; . + (($d // {}).folders // []))' "$SHARED" "$LOCAL" > "$TMP_DIR/folders.json" \
    || die "could not read 'folders'"
NOT_LISTS=$(yq -r '.[] | . as $f | (["separate_mounts", "ignore"][] | select(($f[.] // []) | tag != "!!seq") | "folder '\''" + ($f.path // "?") + "'\'': '\''" + . + "'\'' must be a list (each entry starts with \"- \")")' "$TMP_DIR/folders.json") \
    || die "could not read 'folders'"
[[ -z "$NOT_LISTS" ]] || die "$NOT_LISTS"
yq -o=json -I0 '
    . as $all
    | [.[].path] | unique
    | map(
        . as $p
        | $all | map(select(.path == $p))
        | .[] as $f ireduce ({}; . *+ $f)
        | .separate_mounts |= ((. // []) | unique)
        | .ignore |= ((. // []) | unique)
    )' "$TMP_DIR/folders.json" > "$TMP_DIR/folders.merged.json" \
    || die "could not merge 'folders'"
FOLDERS_JSON=$(cat "$TMP_DIR/folders.merged.json") \
    yq '.folders = (strenv(FOLDERS_JSON) | from_yaml)' "$TMP_DIR/base.yaml" > "$MERGED"

q() { yq "$@" "$MERGED"; }

# Escape `$` for Compose interpolation (host paths must be taken literally).
compose_literal() { printf '%s' "${1//\$/\$\$}"; }

# Turn an arbitrary string into a Docker volume name fragment.
volume_slug() { printf '%s' "$1" | sed -e 's#[^A-Za-z0-9_.-]#-#g' -e 's#^[-.]*##'; }

# Membership test for newline-separated lists (bash 3.2 has no assoc arrays).
in_list() { case $'\n'"$2"$'\n' in *$'\n'"$1"$'\n'*) return 0 ;; esac; return 1; }

# Escape glob characters so `find -path` matches a path literally.
glob_literal() { printf '%s' "$1" | sed 's/[][*?\\]/\\&/g'; }

# Relative path that stays inside its parent: not absolute, no `..`, not empty.
is_safe_relative() {
    [[ -n "$1" && "$1" != /* && "/$1/" != */../* && "$1" != "." ]]
}

echo "Validating config..."

# ---------------------------------------------------------------------------
# metarepo_id
# ---------------------------------------------------------------------------
METAREPO_ID=$(q '.metarepo_id // ""')
if [[ -z "$METAREPO_ID" ]]; then
    err "metarepo_id must be set (in meta-repo.yaml)"
elif ! [[ "$METAREPO_ID" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    err "metarepo_id '$METAREPO_ID' must start with a lowercase letter or digit and contain only lowercase letters, digits, '-' and '_' (it is used as the Compose project name)"
fi

# ---------------------------------------------------------------------------
# root
# ---------------------------------------------------------------------------
ROOT=$(q '.root // ""')
case "$ROOT" in
    "~") ROOT=$HOME ;;
    "~/"*) ROOT="$HOME/${ROOT#\~/}" ;;
esac
ROOT=${ROOT%/}
if [[ -z "$ROOT" ]]; then
    err "root must be set (in meta-repo.local.yaml)"
elif [[ "$ROOT" != /* ]]; then
    err "root '$ROOT' must be an absolute path"
elif [[ ! -d "$ROOT" ]]; then
    err "root '$ROOT' does not exist or is not a directory"
fi

# ---------------------------------------------------------------------------
# Names that are taken at /workspace/<name>
# ---------------------------------------------------------------------------
RESERVED=$(printf '%s\n' .agents .workspace .claude)
ROOT_ENTRIES=""
if [[ -d "$ROOT_FILES_DIR" ]]; then
    for entry in "$ROOT_FILES_DIR"/* "$ROOT_FILES_DIR"/.[!.]*; do
        [[ -e "$entry" ]] || continue
        name=$(basename "$entry")
        case "$name" in .DS_Store|.gitkeep) continue ;; esac
        ROOT_ENTRIES="$ROOT_ENTRIES$name"$'\n'
    done
fi
RESERVED="$RESERVED"$'\n'"$ROOT_ENTRIES"
if $ADMIN; then
    RESERVED="$RESERVED"$'\n'"$REPO_NAME"
fi

# ---------------------------------------------------------------------------
# folders
# ---------------------------------------------------------------------------
FOLDER_COUNT=$(q '.folders | length')
FOLDER_NAMES=""
VOLUME_KEYS=""
[[ "$FOLDER_COUNT" -gt 0 ]] || warn "no folders configured; the container will only contain the meta-repo files"

i=0
while [[ $i -lt $FOLDER_COUNT ]]; do
    path=$(q ".folders[$i].path // \"\"")
    path=${path%/}
    if [[ -z "$path" ]]; then
        err "folders[$i] has no 'path'"
    elif ! is_safe_relative "$path"; then
        err "folder '$path' must be a path relative to root, without '..'"
    else
        name=$(basename "$path")
        if in_list "$name" "$FOLDER_NAMES"; then
            err "duplicate folder name '$name' (from '$path'): each folder is mounted at /workspace/<folder name>, so names must be unique"
        elif in_list "$name" "$RESERVED"; then
            err "folder name '$name' (from '$path') clashes with /workspace/$name, which the meta-repo already uses"
        fi
        FOLDER_NAMES="$FOLDER_NAMES$name"$'\n'
        if [[ -n "$ROOT" && ! -d "$ROOT/$path" ]]; then
            err "folder '$path' does not exist under root ($ROOT/$path)"
        fi

        # Never search inside .git or the separate_mounts (they aren't host files).
        prune=(-name .git)
        mount_count=$(q ".folders[$i].separate_mounts | length")
        j=0
        while [[ $j -lt $mount_count ]]; do
            mount=$(q ".folders[$i].separate_mounts[$j]")
            mount=${mount%/}
            if ! is_safe_relative "$mount"; then
                err "separate_mount '$mount' in folder '$path' must be a path relative to the folder, without '..'"
            else
                key="folder-$(volume_slug "$name")-$(volume_slug "$mount")"
                if in_list "$key" "$VOLUME_KEYS"; then
                    err "separate_mount '$mount' in folder '$path' maps to the same volume name as another mount ($key)"
                fi
                VOLUME_KEYS="$VOLUME_KEYS$key"$'\n'
                prune+=(-o -path "./$(glob_literal "$mount")")
            fi
            j=$((j + 1))
        done

        # ignore: glob patterns, expanded now against the host files. A pattern
        # without a `/` matches a name at any depth; one with a `/` matches the
        # path from the folder root (`*` may cross directories). A trailing `/`
        # matches directories only.
        match=()
        ignore_count=$(q ".folders[$i].ignore | length")
        j=0
        while [[ $j -lt $ignore_count ]]; do
            pattern=$(q ".folders[$i].ignore[$j]")
            dir_only=false
            [[ "$pattern" == */ ]] && dir_only=true
            pattern=${pattern%/}
            if ! is_safe_relative "$pattern"; then
                err "ignore pattern '$pattern' in folder '$path' must be relative to the folder, without '..'"
            else
                [[ ${#match[@]} -gt 0 ]] && match+=(-o)
                if [[ "$pattern" == */* ]]; then
                    cond=(-path "./$pattern")
                else
                    cond=(-name "$pattern")
                fi
                $dir_only && cond+=(-type d)
                match+=(\( "${cond[@]}" \))
            fi
            j=$((j + 1))
        done
        if [[ ${#match[@]} -gt 0 && -n "$ROOT" && -d "$ROOT/$path" ]]; then
            (cd "$ROOT/$path" && find . -mindepth 1 \( "${prune[@]}" \) -prune -o \( "${match[@]}" \) -print -prune) \
                > "$TMP_DIR/ignored-$i" \
                || warn "could not search all of folder '$path' for ignored files; some may not be hidden"
        fi
    fi
    i=$((i + 1))
done

# ---------------------------------------------------------------------------
# persistent_volumes
# ---------------------------------------------------------------------------
PV_NAMES=$(q '.persistent_volumes // {} | keys | .[]')
while IFS= read -r pv; do
    [[ -n "$pv" ]] || continue
    target=$(PV="$pv" q '.persistent_volumes[strenv(PV)] // ""')
    if ! [[ "$pv" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
        err "persistent_volumes name '$pv' may only contain letters, digits, '_', '.' and '-'"
    fi
    if [[ "$target" != /* ]]; then
        err "persistent_volumes '$pv' must map to an absolute container path (got '$target')"
    fi
done <<< "$PV_NAMES"

# ---------------------------------------------------------------------------
# env
# ---------------------------------------------------------------------------
ENV_KEYS=$(q '.env // {} | keys | .[]')
while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    value=$(K="$key" q '.env[strenv(K)] // ""')
    if ! [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        err "env key '$key' is not a valid environment variable name"
    fi
    if [[ -z "$value" ]]; then
        err "env '$key' is declared but has no value (set it in meta-repo.local.yaml)"
        continue
    fi
    # Compose resolves $VAR references at container start; warn if they're
    # unset in this shell, since they probably will be then too.
    refs=$(printf '%s' "${value//\$\$/}" | grep -oE '\$\{?[A-Za-z_][A-Za-z0-9_]*' | sed -e 's/^\$//' -e 's/^{//' || true)
    for ref in $refs; do
        if [[ -z "${!ref+x}" ]]; then
            warn "env '$key' references \$$ref, which is not set in this shell. It must be set in the environment that launches the container (e.g. VS Code)."
        fi
    done
done <<< "$ENV_KEYS"

# ---------------------------------------------------------------------------
# dotfiles (personal, from meta-repo.local.yaml)
# Each entry is a file or directory under your host home directory. It is
# mounted read-only at the same path under the container user's home.
# ---------------------------------------------------------------------------
CONTAINER_HOME=/home/vscode
DOTFILES_REL=""
DOTFILE_COUNT=$(q '.dotfiles // [] | length')
if [[ "$(q '.dotfiles // [] | tag')" != "!!seq" ]]; then
    err "dotfiles must be a list (each entry starts with \"- \")"
    DOTFILE_COUNT=0
fi
i=0
while [[ $i -lt $DOTFILE_COUNT ]]; do
    entry=$(q ".dotfiles[$i]")
    entry=${entry%/}
    case "$entry" in
        "~/"*) rel=${entry#\~/} ;;
        "$HOME/"*) rel=${entry#"$HOME"/} ;;
        *) rel=$entry ;;
    esac
    if ! is_safe_relative "$rel"; then
        err "dotfile '$entry' must be under your home directory (~/...), without '..'"
    elif [[ ! -e "$HOME/$rel" ]]; then
        warn "dotfile '$entry' does not exist ($HOME/$rel); skipped"
    elif in_list "$rel" "$DOTFILES_REL"; then
        warn "dotfile '$entry' is listed twice; ignoring the duplicate"
    else
        DOTFILES_REL="$DOTFILES_REL$rel"$'\n'
    fi
    i=$((i + 1))
done

if [[ $ERRORS -gt 0 ]]; then
    die "$ERRORS problem(s) found; compose.local.yaml was not written"
fi

# ---------------------------------------------------------------------------
# Generate compose.local.yaml
# ---------------------------------------------------------------------------
echo "{}" > "$GEN"
gen() { yq -i "$1" "$GEN"; }

ID="$METAREPO_ID" gen '.name = strenv(ID)'

# Names for the volumes declared in compose.yaml (agent state).
for key in $(yq '.volumes // {} | keys | .[]' "$STATIC_COMPOSE"); do
    K="$key" N="$METAREPO_ID-$key" gen '.volumes[strenv(K)] = {"name": strenv(N)}'
done

# Build-time proxy -> build args
for var in http_proxy https_proxy no_proxy; do
    value=$(V="$var" q '.proxy.buildtime[strenv(V)] // ""')
    if [[ -n "$value" ]]; then
        upper=$(printf '%s' "$var" | tr '[:lower:]' '[:upper:]')
        K="BUILDTIME_$upper" V="$value" gen '.services.dev.build.args[strenv(K)] = strenv(V)'
    fi
done

# Environment
ID="$METAREPO_ID" gen '.services.dev.environment.META_REPO_ID = strenv(ID)'
for var in http_proxy https_proxy no_proxy; do
    value=$(V="$var" q '.proxy.runtime[strenv(V)] // ""')
    if [[ -n "$value" ]]; then
        upper=$(printf '%s' "$var" | tr '[:lower:]' '[:upper:]')
        V="$(compose_literal "$value")"
        K="$upper" V="$V" gen '.services.dev.environment[strenv(K)] = strenv(V)'
        K="$var" V="$V" gen '.services.dev.environment[strenv(K)] = strenv(V)'
    fi
done
while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    # Passed through unexpanded: Compose resolves $VAR references at start-up.
    value=$(K="$key" q '.env[strenv(K)]')
    K="$key" V="$value" gen '.services.dev.environment[strenv(K)] = strenv(V)'
done <<< "$ENV_KEYS"

add_bind() {
    S="$(compose_literal "$1")" T="$2" gen '.services.dev.volumes += [{"type": "bind", "source": strenv(S), "target": strenv(T)}]'
    if [[ "${3:-}" == ro ]]; then
        gen '.services.dev.volumes[-1].read_only = true'
    fi
}
VOLUME_PATHS=""
add_volume() {
    local key=$1 target=$2
    K="$key" T="$target" gen '.services.dev.volumes += [{"type": "volume", "source": strenv(K), "target": strenv(T)}]'
    K="$key" N="$METAREPO_ID-$key" gen '.volumes[strenv(K)] = {"name": strenv(N)}'
    VOLUME_PATHS="${VOLUME_PATHS:+$VOLUME_PATHS:}$target"
}

# Files from .root/ live in /workspace/
printf '%s' "$ROOT_ENTRIES" | while IFS= read -r name; do
    [[ -n "$name" ]] && add_bind "../.root/$name" "/workspace/$name"
done

# Personal dotfiles (aliases etc.), read-only, in the container user's home
printf '%s' "$DOTFILES_REL" | while IFS= read -r rel; do
    [[ -n "$rel" ]] && add_bind "$HOME/$rel" "$CONTAINER_HOME/$rel" ro
done

# The repos, and their separate_mounts
i=0
while [[ $i -lt $FOLDER_COUNT ]]; do
    path=$(q ".folders[$i].path")
    path=${path%/}
    name=$(basename "$path")
    add_bind "$ROOT/$path" "/workspace/$name"
    mount_count=$(q ".folders[$i].separate_mounts | length")
    j=0
    while [[ $j -lt $mount_count ]]; do
        mount=$(q ".folders[$i].separate_mounts[$j]")
        mount=${mount%/}
        add_volume "folder-$(volume_slug "$name")-$(volume_slug "$mount")" "/workspace/$name/$mount"
        j=$((j + 1))
    done
    # Hide ignored paths: files become an empty read-only file, directories an
    # empty tmpfs. The host files are untouched.
    if [[ -f "$TMP_DIR/ignored-$i" ]]; then
        while IFS= read -r rel; do
            rel=${rel#./}
            T="$(compose_literal "/workspace/$name/$rel")"
            if [[ -d "$ROOT/$path/$rel" ]]; then
                T="$T" gen '.services.dev.volumes += [{"type": "tmpfs", "target": strenv(T)}]'
            else
                T="$T" gen '.services.dev.volumes += [{"type": "bind", "source": "/dev/null", "target": strenv(T), "read_only": true}]'
            fi
            echo "/workspace/$name/$rel" >> "$TMP_DIR/hidden"
        done < "$TMP_DIR/ignored-$i"
    fi
    i=$((i + 1))
done

# persistent_volumes
while IFS= read -r pv; do
    [[ -n "$pv" ]] || continue
    target=$(PV="$pv" q '.persistent_volumes[strenv(PV)]')
    add_volume "persist-$pv" "$target"
done <<< "$PV_NAMES"

# Tell the entrypoint which volume roots need their ownership fixed.
P="$VOLUME_PATHS" gen '.services.dev.environment.META_REPO_VOLUME_PATHS = strenv(P)'

# --admin: this repo itself
if $ADMIN; then
    add_bind ".." "/workspace/$REPO_NAME"
fi

# Key order: name, services, volumes
gen '{"name": .name, "services": .services, "volumes": .volumes}'
gen '. head_comment = "GENERATED by apply.sh from meta-repo.yaml + meta-repo.local.yaml. Do not edit:\nchanges will be overwritten. Contains host paths, so it is gitignored and\nnot exposed in /workspace/.workspace.\nMode: '"$( $ADMIN && echo admin || echo standard )"'"'

mv "$GEN" "$OUT"

# Ask Compose to validate the merged result, if it's available.
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    if ! compose_err=$(cd "$SCRIPT_DIR/.devcontainer" && docker compose -f compose.yaml -f compose.local.yaml config --quiet 2>&1); then
        warn "docker compose could not validate the generated config:"
        printf '%s\n' "$compose_err" | sed 's/^/      /' >&2
    fi
fi

echo
echo "Wrote .devcontainer/compose.local.yaml ($( $ADMIN && echo 'admin mode' || echo 'standard mode' ))"
echo "  project:  $METAREPO_ID"
printf '%s' "$FOLDER_NAMES" | while IFS= read -r name; do
    [[ -n "$name" ]] && echo "  /workspace/$name"
done
if $ADMIN; then
    echo "  /workspace/$REPO_NAME  (this repo)"
fi
if [[ -n "$DOTFILES_REL" ]]; then
    echo "  dotfiles (read-only, in $CONTAINER_HOME):"
    printf '%s' "$DOTFILES_REL" | sed 's/^/    /'
fi
if [[ -f "$TMP_DIR/hidden" ]]; then
    echo
    echo "Hidden by ignore (re-run ./apply.sh to pick up newly created files):"
    sed 's/^/  /' "$TMP_DIR/hidden"
fi
echo
echo "Next: in VS Code run 'Dev Containers: Rebuild and Reopen in Container'."
