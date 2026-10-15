# Implementation Decisions

Decisions that refine the brief in [AGENTS.md](AGENTS.md). Where this file and the brief disagree, this file wins.

## Configuration

### Shared vs. local config

The template is meant to be forked by a team. Values the whole team shares are committed. Values that are per-person or secret stay local.

| `meta-repo.yaml` (committed, shared) | `meta-repo.local.yaml` (gitignored, per person) |
|---|---|
| `metarepo_id` | `root` (a host path) |
| `folders` (paths relative to `root`) and `separate_mounts` | `env` values |
| `persistent_volumes` | `proxy` settings |
| `env` keys (the variables the container expects) | extra personal `folders` (optional) |

- **Merge rules:** scalars and maps in the local file override the shared file. `folders` are combined by matching on `path`.
- **Template:** `meta-repo.yaml.template` is renamed to `meta-repo.local.yaml.template`, because the local file is the one each person creates. Whoever forks the template edits `meta-repo.yaml` directly.

### apply.sh

- **Dependency:** requires `yq` on the host. If it's missing, fail with a clear message.
- **Validation:**
  - Every folder must exist under `root`.
  - There must be no duplicate folder names.
  - `root` must be set.
  - Every declared `env` key must have a value.
- **`metarepo_id`:** used as the Compose project name and as a prefix on all volume names, so separate meta-repos never share volumes.
- **`$VARS` in `env`:** passed through unexpanded and resolved by Compose when the container starts. Secrets are never written to `compose.local.yaml`.

## Container layout

- **Workspace root:** `/workspace`.
- **`.workspace/`:** bind-mounted read-only (`:ro`). It contains `Dockerfile`, `devcontainer.json` and `compose.yaml`. It does **not** contain `compose.local.yaml`, because that file leaks host information.
- **`.agents/` and `.root/AGENTS.md`:** always bind-mounted read-write, so host edits show up live and agents can edit their own skills.
- **`--admin` mode:** this repo is mounted at `/workspace/<this repo's directory name>`. The name is not fixed as `this-repo`.

## Volumes

- **`separate_mounts`:** each one becomes a named volume per folder. Named volumes are created owned by root, so `docker-entrypoint.sh` fixes their ownership to the `vscode` user. This also covers volumes created before Linux UID remapping.
- **Persisted agent state:** only the specific paths are persisted, never the whole `.vscode-server` directory, because extension version conflicts can break things.
  - **Copilot / VS Code:**
    - `~/.copilot`
    - `~/.vscode-server/data/agentSessionData`
    - `~/.vscode-server/data/User/globalStorage`
  - **Claude Code:**
    - `~/.claude`
    - `~/.claude.json`, which is a single file, so it is symlinked into a persisted directory.

## Dockerfile

- **Base image:** the Microsoft dev containers Ubuntu image, pinned to an Ubuntu release (e.g. `ubuntu-24.04`).
- **Docker-in-Docker:** use the official `docker-in-docker` dev container feature in `devcontainer.json`, not a hand-rolled install.
- **Proxy:** values come explicitly from the meta-repo yaml, never picked up automatically from the host environment. They are passed as build args and also set as container env vars, because tools at runtime (`npm`, `gh`, `claude`) need them too. *(Assumed; not explicitly confirmed.)*
- **Versions:**
  - **Node:** `nvm install --lts` at build time. Repos with an `.nvmrc` use their own version via `nvm use`.
  - **bun, Claude CLI:** latest at build time. The Claude CLI updates itself.
  - **Pinned:** the nvm installer version and the base image's Ubuntu release.
- **Certs:** the commented-out blocks for trusting CA certs from `.devcontainer/certs/` are kept, as in the brief.

## Host platform support

- **macOS:** supported. Docker Desktop translates file ownership on bind mounts.
- **Linux:** supported. Dev Containers' `updateRemoteUserUID` remaps the container user to the host UID, and the entrypoint fixes volume ownership.
- **Windows:** documented as "WSL2 only, untested". Repos must live inside the WSL2 filesystem.
