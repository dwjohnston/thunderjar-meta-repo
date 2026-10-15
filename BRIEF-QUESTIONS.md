The brief is clear enough to start. These are the questions whose answers would change what I build. Where I have a default, I've given it in brackets.

apply.sh and config

1. How do the two config files combine? Does meta-repo.local.yaml deep-merge over meta-repo.yaml, or replace it? And what is meta-repo.yaml.template for, if meta-repo.yaml is committed? [Deep-merge. The template is the starting point people copy.]
- 🙋‍♂️Let's talk about this. Intention is that someone can fork this template, there are some parts of the yaml that need/want to be persisted between users, but other parts that defintiely want to be kept secret. Like env values or folder locations. 

2. What can apply.sh depend on? Parsing YAML in bash needs yq or Python. Is requiring yq on the host acceptable? [Use yq, and fail with a clear message if it's missing.]
- 🙋‍♂️ require yq
3. When do $VARS in env: get resolved? Should apply.sh expand them when it runs, which writes secrets into compose.local.yaml? Or should it pass them through for Compose to resolve when the container starts? [Pass them through, so no secrets end up on disk.]

4. What is metarepo_id used for? I'd use it for the Compose project name and as a prefix on volume names, so two meta-repos don't share volumes. Is that the intent?
- 🙋‍♂️ That's correct 

**Container layout**

5. Where is the workspace? Is it /workspace, or the default /workspaces/<name>? [/workspace]
- 🙋‍♂️ yes. 
6. How should .workspace/ be read-only? Mounting it read-only (:ro) would be the default. And should it hold the generated compose.local.yaml as well?
- 🙋‍♂️ Mount read only. Do not include the generated compose.local that leaks information about the host. 
7. Should .agents/ and .root/AGENTS.md be bind-mounted or copied into the image? Bind-mounting means edits on the host show up live. [Bind-mount, read-only unless in --admin mode.]
- 🙋‍♂️ Always bind mount
8. Is this-repo/ a fixed name? Should it be the repo's directory name instead?
- 🙋‍♂️ It's the directory name
Volumes
9. separate_mounts: each one becomes a named volume per folder. Those volumes are owned by root when first created, so I'd fix the ownership in docker-entrypoint.sh. OK?
- 🙋‍♂️ Yes
10. Persisting conversations: for Claude Code that means ~/.claude and ~/.claude.json. Since .claude.json is a single file, I'd symlink it into a persisted directory. For Copilot, should I persist the whole .vscode-server folder, or only the three paths listed? Persisting the whole folder also keeps extensions, but that can cause conflicts when versions change. [Only the listed paths.]
- 🙋‍♂️ Only listed paths

Dockerfile
11. Docker-in-Docker: should this use the official dev container feature (docker-in-docker) in devcontainer.json, or be installed in the Dockerfile? Or would you rather mount the host's Docker socket ("docker-outside-of-docker"), which is lighter but means bind-mount paths are host paths? [The DinD feature.]
 - 🙋‍♂️ I didn't realise there was one. use the official one. 
12. Should the proxy settings be build args, runtime env vars, or both? And should apply.sh pick up the host's HTTP(S)_PROXY/NO_PROXY automatically? [Both, picked up automatically.]
 - 🙋‍♂️ Build time args - they should be source explicilty from the meta-repo. yaml 
13. Which Node version should nvm install as the default? Should bun and the Claude CLI be pinned or latest? [Node LTS, latest for the rest.]
- 🙋‍♂️ Your advice. 

Scope
14. Should apply.sh also check things? For example, that each folder exists under root, or that there are no duplicate names. [Yes, with basic checks.]
 - 🙋‍♂️ Sure 
15. Is Linux or Windows as a host in scope, or is it macOS only? This affects things like UID mapping.
 - 🙋‍♂️ Explain 

If you're happy with the defaults, I'll start and note any assumptions as I go.