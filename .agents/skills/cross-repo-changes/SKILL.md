---
name: cross-repo-changes
description: How to plan, make, and ship a change that spans more than one repository in this meta-repo workspace. Use when a task touches code in two or more directories under /workspace, e.g. an API change plus its client, or a shared library plus its consumers.
---

# Cross-repo changes

Each directory under `/workspace` is its own git repository. A change that
spans several repos is several changes, one per repo, that have to land in a
workable order.

## 1. Map the change

Before editing, write down:

- Which repos are touched and what changes in each.
- The dependency direction: who consumes whom (package dependency, HTTP API,
  shared schema, etc.).
- The order to release in. Producers usually ship first, with the change
  backwards compatible, then consumers, then the old path is removed.

If the change can't be made backwards compatible, say so to the user and agree
on a plan before continuing.

## 2. Check each repo's state

For each repo:

```bash
cd /workspace/<repo>
git status --short
git branch --show-current
```

Don't build on top of someone's uncommitted work without asking. Read the
repo's own `AGENTS.md` / `CLAUDE.md` / `README` for its conventions (test
commands, Node version via `.nvmrc`, branch naming).

## 3. Make the change

- Use the **same branch name** in every repo touched, so the related changes
  are easy to find.
- To test a consumer against an unpublished producer, prefer the ecosystem's
  local linking (`npm link`, `bun link`, a `file:` dependency, a workspace
  override). Revert linking before committing.
- Run each repo's own tests and checks from inside that repo.

## 4. Commit and open PRs

- Commit in each repo separately, with messages that make sense on their own.
- When opening PRs with `gh`, cross-link them: each PR description lists the
  related PRs in the other repos and the required merge order.

## 5. Report

Finish with a short table: repo, branch, what changed, PR link (if any), and
the merge order.
