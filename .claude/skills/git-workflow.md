---
name: git-workflow
description: Git workflow rules for this repo — all changes via feature branch + PR, never direct push to main
---

# Git Workflow

**Rule: never push directly to main.**

All changes must go through a feature branch and PR.

## Flow

```
git checkout -b <type>/<name>   # create branch
# ... make commits ...
git push -u origin <type>/<name>
gh pr create --base main
```

## Branch naming

| Prefix | Use |
|--------|-----|
| `feat/` | new feature |
| `fix/`  | bug fix |
| `chore/` | maintenance, deps, docs |

## When to apply

Any time you are about to run `git push origin main` — stop, create a branch instead.

Before committing: verify current branch is NOT `main`:
```bash
git branch --show-current   # must not be "main"
```

If already on `main` with unpushed commits:
```bash
git checkout -b fix/<name>
git push -u origin fix/<name>
gh pr create --base main
```

## Pre-push hook

A pre-push hook at `.git/hooks/pre-push` enforces this automatically and will block direct pushes to main.
