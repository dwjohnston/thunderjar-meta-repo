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

## ThunderJar

```
thunderjar/           # the thunderjar implementation
thunderjar2/          # Just the spec 
```




