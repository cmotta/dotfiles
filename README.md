# Dotfiles

Personal dotfiles for zsh, vim/neovim, tmux, and git. Works on macOS and Linux.

## Quick Start

```sh
git clone https://github.com/YOUR_USER/dotfiles.git ~/Code/dotfiles
cd ~/Code/dotfiles
./install.sh
```

`install.sh` is safe to run multiple times — it skips existing links and backs up conflicts to `~/.dotfiles_backup/`.

## Server Setup

`server-bootstrap.sh` provisions a fresh Ubuntu server as a headless dev environment. It installs system packages, dev toolchains (Node via fnm, Python via uv), Tailscale, GitHub CLI, AWS CLI, Claude Code, and then clones this repo and runs `install.sh`.

```sh
curl -fsSL https://raw.githubusercontent.com/cmotta/dotfiles/master/server-bootstrap.sh | bash
```

Or from a local copy:

```sh
./server-bootstrap.sh
```

Idempotent — safe to re-run. See the script header for details.

## What `install.sh` Does

1. **Symlinks** all dotfiles into `$HOME` (e.g. `gitconfig` → `~/.gitconfig`)
2. **Prompts for git identity** (name + email) on first run → writes `~/.gitconfig.local`
3. **Installs vim-plug** and runs `:PlugInstall` if missing
4. **Installs TPM** (tmux plugin manager) if missing
5. **Copies SSH config** from `ssh_config.example` → `~/.ssh/config` if missing
6. **Sets up Claude Code** — symlinks global instructions, slash commands, and notification hooks into `~/.claude/`

## Prerequisites

- **zsh** (set as login shell: `chsh -s $(which zsh)`)
- **git**
- **curl**

Recommended:

- **neovim** — config symlinked to `~/.config/nvim`
- **tmux** — prefix is `Ctrl+A`
- **ripgrep** (`rg`) — used by vim and scripts
- **fd** — fast file finder

### macOS

```sh
brew install zsh git curl neovim tmux ripgrep fd
```

### Ubuntu/Debian

```sh
sudo apt install zsh git curl neovim tmux ripgrep fd-find
```

## What's Included

| Component | Files | Notes |
|-----------|-------|-------|
| zsh | `zshrc`, `zshenv`, `zsh/` | Functions, keybindings, completions |
| vim/neovim | `vimrc`, `vimrc.bundles`, `gvimrc`, `config/nvim` | vim-plug managed plugins |
| tmux | `tmux.conf` | TPM plugins, vi copy mode |
| git | `gitconfig`, `gitignore`, `gitmessage`, `git_template` | Aliases, hooks, ctags |
| shell | `aliases`, `bin/` | Utility scripts on `$PATH` |
| Claude Code | `claude/`, `bin/dev-workspace` | Global instructions, slash commands, hooks |
| other | `psqlrc`, `gemrc`, `agignore`, `ctags.d`, `hushlogin` | Tool configs |

## Customization with `.local` Files

Every config sources a `.local` counterpart that is **never committed**. Use these for machine-specific settings:

| File | Purpose |
|------|---------|
| `~/.gitconfig.local` | Git name, email, credential helper |
| `~/.zshrc.local` | Homebrew, Go, pyenv, cloud SDKs |
| `~/.tmux.conf.local` | Status bar overrides |
| `~/.vimrc.bundles.local` | Extra vim plugins |
| `~/.aliases.local` | Extra aliases |

See the `*.local.example` files in this repo for commented templates. `ssh_config.example` is copied to `~/.ssh/config` on first install.

## Key Bindings

### tmux (prefix: `Ctrl+A`)

| Binding | Action |
|---------|--------|
| `h/j/k/l` | Navigate panes |
| `H/J/K/L` | Resize panes (repeatable) |
| `\|` | Split horizontal |
| `-` | Split vertical |
| `<` / `>` | Reorder windows |
| `v` (copy mode) | Begin selection |
| `y` (copy mode) | Copy to system clipboard |
| `r` | Reload config |
| `prefix + I` | Install TPM plugins |

### vim

| Binding | Action |
|---------|--------|
| `<leader>` | Space |
| `<leader><leader>` | Switch between last two files |

## Shell Aliases & Scripts

| Command | Description |
|---------|-------------|
| `v` | Open `$VISUAL` |
| `e` | Open `$EDITOR` |
| `ll` | `ls -al` |
| `path` | Pretty-print `$PATH` |
| `git-churn` | Show file churn on current branch |
| `replace foo bar **/*.rb` | Find and replace across files |
| `dev-workspace [name]` | Start tmux dev workspace (Claude + 3 terminal panes) |
| `tat` | Attach to tmux session named after current directory |

## License

Based on [thoughtbot/dotfiles](https://github.com/thoughtbot/dotfiles). See [LICENSE](LICENSE).
