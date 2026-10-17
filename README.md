# meta-repo template

Open several repositories together in one dev container, with Docker-in-Docker,
Node (nvm), bun, gh and the Claude Code CLI preinstalled. Agent conversations
(Claude Code, Copilot / VS Code chat) survive container rebuilds.

Inside the container:

```
/workspace/
    AGENTS.md / CLAUDE.md   # instructions for agents (from .root/)
    .agents/skills/         # shared skills (also at /workspace/.claude/skills)
    .workspace/             # read-only Dockerfile, devcontainer.json, compose.yaml
    foo/                    # your repos
    bar/
    meta-repo-template/     # this repo, only with ./apply.sh --admin
```

## Setting up for a team (once)

Fork this template, then edit and commit:

- `meta-repo.yaml`: `metarepo_id`, the `folders` (repos) everyone works on,
  `separate_mounts`, `persistent_volumes` and the `env` keys the container needs.
- `.devcontainer/Dockerfile`: extra tools. Uncomment the certs block if you
  need corporate CA certificates (put `.crt` files in `.devcontainer/certs/`).
- `.root/AGENTS.md` and `.agents/skills/`: instructions and skills for agents.

## Using it (each person)

Requirements: Docker, VS Code with the Dev Containers extension, and
[mikefarah/yq](https://github.com/mikefarah/yq#install) v4 (`brew install yq`).

1. Clone your repos into one folder, e.g. `~/git-workspace/foo`, `~/git-workspace/bar`.
2. Create your local config:

   ```bash
   cp meta-repo.local.yaml.template meta-repo.local.yaml
   ```

   Set `root`, values for each `env` key, and any proxies.
3. Generate the Compose config:

   ```bash
   ./apply.sh           # or ./apply.sh --admin to also mount this repo
   ```

4. Open this folder in VS Code and run **Dev Containers: Reopen in Container**.

After changing `meta-repo.yaml`, `meta-repo.local.yaml` or the Dockerfile,
re-run `./apply.sh` and **Dev Containers: Rebuild Container**. Changes to
`.agents/` and `.root/` files show up live.

## Configuration

| `meta-repo.yaml` (committed) | `meta-repo.local.yaml` (gitignored) |
|---|---|
| `metarepo_id` | `root` (host path) |
| `folders`, `separate_mounts`, `ignore` | `env` values |
| `persistent_volumes` | `proxy` |
| `env` keys | `dotfiles` |
| | extra personal `folders` |

The local file overrides the shared one. `folders` are combined, matched on
`path`. Each folder is mounted at `/workspace/<folder name>`, so folder names
must be unique.

### Hiding files (`ignore`)

List glob patterns under a folder's `ignore` to keep files such as secrets out
of the container:

```yaml
folders:
  - path: "foo"
    ignore:
      - .env*            # no `/`: matches the name at any depth
      - config/**/*.pem  # with `/`: matched from the folder root
      - secrets/         # trailing `/`: directories only
```

In the container a matched file appears empty and read-only, and a matched
directory appears empty. The host files are untouched. `.git` and
`separate_mounts` are never searched.

Patterns are expanded when `./apply.sh` runs, so a file created later is
**not** hidden until you re-run `./apply.sh` and rebuild. `apply.sh` lists
everything it hid.

### Environment variables and secrets

`env` values may reference host environment variables (`$VAR` / `${VAR}`).
`apply.sh` writes them unexpanded and Compose resolves them when the container
starts, so secrets aren't written to disk. They are read from the environment
of the process that starts the container. On macOS, VS Code launched from the
Dock may not see variables exported in your shell profile: launch it with
`code .` from a terminal. Use `$$` for a literal `$`.

### Dotfiles

List files or directories under your host home in `meta-repo.local.yaml` to
bring your aliases and shell setup into the container:

```yaml
dotfiles:
  - ~/.aliases
```

Each is bind-mounted **read-only** at the same path under `/home/vscode`.
Missing entries are skipped with a warning. Edits on the host show up live.

The image's `~/.bashrc` and `~/.zshrc` source `~/.aliases` if it exists, so put
your portable aliases and functions there and `source` it from your host
`.zshrc`. Don't mount a whole `.zshrc`/`.bashrc`: it would replace the image's
own (which sets up nvm) and usually contains macOS paths and secrets. VS Code
already copies your host `.gitconfig` into the container. Don't list files
containing secrets: everything mounted is readable in the container.

### Proxies

`proxy.buildtime` is used only while building the image (it is not kept in the
image). `proxy.runtime` becomes `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY` (and
lowercase) in the container. Either can be left empty. Neither is picked up
automatically from your host.

### Volumes

All volumes are named `<metarepo_id>-…`, so different meta-repos don't share
them:

- `separate_mounts`: `<id>-folder-<folder>-<mount>`, e.g. `node_modules` kept
  off the host.
- `persistent_volumes`: `<id>-persist-<name>`.
- Agent state: `<id>-claude` (`~/.claude`, including `.claude.json`),
  `<id>-copilot` (`~/.copilot`), `<id>-vscode-agent-sessions` and
  `<id>-vscode-global-storage` (under `~/.vscode-server/data`).

To start completely fresh, remove the container and then the volumes:
`docker volume ls --filter name=<metarepo_id>-`.

## Host platforms

- **macOS**: supported.
- **Linux**: supported. The container user is remapped to your UID, and the
  entrypoint fixes volume ownership.
- **Windows**: WSL2 only, untested. Keep the repos and this repo inside the WSL2
  filesystem and run `./apply.sh` from WSL.

See [DECISIONS.md](DECISIONS.md) for the reasoning behind the design.




## Short comings 


- Ignore globs will be lost. 