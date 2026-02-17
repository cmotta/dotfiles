---
description: Review code for bugs, security issues, and improvements
allowed-tools: Read, Glob, Grep, Bash(git diff:*), Bash(git log:*)
---

Review the following for $ARGUMENTS:

1. **Bugs**: Logic errors, edge cases, null/undefined handling
2. **Security**: Injection risks, exposed secrets, unsafe operations
3. **Performance**: N+1 queries, unnecessary re-renders, missing indexes
4. **Readability**: Naming, complexity, missing types

Be direct. Skip obvious stuff. Focus on what could actually break.
