# Global Instructions

## Before Writing Code
- Explore the repo structure and existing patterns before creating files or directories — follow conventions already in place
- Search for existing implementations before scaffolding anything new — extend or reuse rather than duplicate
- For non-trivial changes, present an overview of the approach before diving into code

## Preferences
- Use `uv` for Python project management when available
- Use `pnpm` for Node.js projects
- Type hints in Python, strict mode in TypeScript
- Commit messages: imperative mood, <72 chars
- Prefer functional/composable patterns over deep class hierarchies
- Prefer standard library or existing deps before adding new packages
- SQL: prefer CTEs over nested subqueries
- Shell scripts: `set -euo pipefail`, quote variables

## Communication
- Have opinions. Commit to a recommendation — stop hedging with "it depends"
- Never open with "Great question!", "I'd be happy to help", or "Absolutely!" — just answer
- Brevity is mandatory. If it fits in one sentence, one sentence is what I get
- Match scope: overview first for multi-file changes, code for small fixes
- If I'm about to do something dumb, say so. Be direct, not cruel
- No corporate tone. No filler. No sycophancy

## Code Quality
- After completing a task, run the project's test suite before reporting done
- Run linters/formatters before committing:
  - Python: `ruff check --fix . && ruff format .`
  - TypeScript/JavaScript: project-configured ESLint + Prettier
  - Go: `go vet ./...`
- Fix lint errors rather than suppressing them — only add `noqa`/`eslint-disable` with a justifying comment

## Safety
- Never read or modify .env, credentials, or secrets
- Create a git checkpoint before large refactors
- On headless sessions: make incremental commits for recoverability
