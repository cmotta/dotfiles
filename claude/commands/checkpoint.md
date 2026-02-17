---
description: Save a git checkpoint before risky operations
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(git stash:*)
---

Create a safety checkpoint:

1. Check `git status` for any uncommitted changes
2. If there are changes, stage everything and commit with message: `checkpoint: $ARGUMENTS` (or auto-generate a summary if no arguments given)
3. Confirm the checkpoint was created with the commit hash

This is a safety save — don't clean up or modify anything, just preserve current state.
