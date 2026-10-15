# The Brief

You are building a 'meta-repo' tool. This contains a .devcontainer configuration the users can use to open several repos inside a docker container.

The structure of this repo:

```
.agents/ # Meta repo comes with some shared skills
.devcontainer/
    certs/ # if needed CA certs to bake into the docker image live here
    .dockerignore
    compose.local.yaml* (git ignored)
    compose.yaml
    devcontainer.json
    docker-entrypoint.sh
    Dockerfile
AGENTS.md # This file
.root/ # The files that live here will live in the root dir of the container
    AGENTS.md # AGENTS.md file specifically for the container root
meta-repo.yaml.template
meta-repo.yaml
meta-repo.local.yaml* (gitignored)
apply.sh
```

An example `meta-repo.yaml` looks like:

```yaml
metarepo_id: "some id"

# We give a single folder that the developers code typically exists
root: "/Users/myname/git-workspace"

# In that root folder we specify individual folders that will become a part of the meta repo
# We also specify 'separate_mounts'; these are things like node_modules, where you don't want these to bind back to the host file system,
# because you often get conflicts between macOS and Linux versions of dependencies.
folders:
  - path: "foo"
    separate_mounts:
      - node_modules

  - path: "bar"
    separate_mounts:
      - node_modules

# Here we allow specifying folders that will exist on the container that we don't want to have to reinstall each time the container rebuilds
persistent_volumes:
  tool-cache: /home/vscode/.cache

env:
  SOME_API_KEY: $I_CAN_REFERENCE_ENV_VARS
```

When we run `./apply.sh` this will generate the `compose.local.yaml`.

When the dev container is then opened, the container file system will look like:

```
workspace/
    .agents/
    AGENTS.md # the container specific AGENTS.md
    .workspace/ # !important - these files are read only. The intention is to give the agent some information about the environment they are working in.
        Dockerfile
        devcontainer.json
        compose.yaml

    foo/
    bar/

```

If `./apply.sh --admin` is run they will see:

```
workspace/
    .agents/
    AGENTS.md # the container specific AGENTS.md
    .workspace/ # !important - these files are read only. The intention is to give the agent some information about the environment they are working in.
        Dockerfile
        devcontainer.json
        compose.yaml

    foo/
    bar/
    this-repo/ # 👈

```

That is, in `--admin` mode they can modify the files from this repo itself, in the container.

## The Dockerfile

The Dockerfile needs to contain:

- Root image: the Microsoft dev containers Ubuntu image.
- Commented-out blocks showing how to trust root certs from the certs folder.
- Env block setting up HTTP proxy etc.
- Needs to support Docker in Docker with Docker Compose.
- Add the following dependencies:
  - bun
  - nvm
  - gh
  - claude cli

### Persisted volumes for agent conversations

An important part is that folders like:

- `vscode/.copilot`
- `vscode/.vscode-server/data/agentSessionData`
- `vscode/.vscode-server/data/User/globalStorage`

Need to be persisted. This is so that when you rebuild the container, you don't lose the conversations.

For the first pass, set this up for Copilot and Claude Code.
