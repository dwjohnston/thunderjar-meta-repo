# Workspace

You are running inside a dev container that combines several repositories into
one workspace (a "meta-repo"). This file is at `/workspace/AGENTS.md`.

## Layout

```
/workspace/
    AGENTS.md          # this file
    .agents/skills/    # shared skills (also at /workspace/.claude/skills)
    .workspace/        # READ-ONLY: how this environment is built
        Dockerfile
        devcontainer.json
        compose.yaml
    <repo>/            # one directory per repository
```

- Each directory under `/workspace` (other than the dot-directories) is a
  **separate git repository**, bind-mounted from the host. Run git commands
  from inside the repo you are changing, and commit to each repo separately.
  Read each repo's own `AGENTS.md` / `CLAUDE.md` / `README` before changing it.
- `/workspace` itself is **not** a git repository.
- `/workspace/.workspace/` is read-only. Read it to understand the environment.
  You cannot change the environment from here (see below).
- Some directories, typically `node_modules`, are Docker volumes rather than
  host bind mounts, so dependencies built here don't clash with the host's.
  Reinstall dependencies inside the container rather than expecting the host's.

## Tools

- **Node** via `nvm`: the latest LTS is the default. In a repo with an
  `.nvmrc`, run `nvm install && nvm use` first.
- **bun**, **gh** (GitHub CLI), **claude** (Claude Code CLI), **git**.
- **Docker** and **Docker Compose** (Docker-in-Docker). Containers you start
  run inside this dev container. Their published ports are reachable at
  `localhost` here, not on the host, unless VS Code forwards them.
- If a proxy is configured, `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY` are set.

## Persistence

Survives a container rebuild:

- Everything inside the repositories (they live on the host).
- Agent state: `~/.claude`, `~/.claude.json`, `~/.copilot`, and VS Code's chat
  session and global storage.
- Any `persistent_volumes` and `separate_mounts` (see `compose.yaml` and the
  volume mounts).

Lost on a rebuild: everything else outside `/workspace`, e.g. packages
installed with `apt` or `npm -g`. If a tool is needed permanently, it belongs
in the Dockerfile. Suggest that change to the user rather than relying on it.

## Changing the environment

The environment is defined by the meta-repo on the host. To add a repo, a
tool or an environment variable, tell the user what to change. If the meta-repo
itself is mounted (admin mode), it is a directory under `/workspace` that
contains `apply.sh` and `meta-repo.yaml`: see the `meta-repo-admin` skill.
