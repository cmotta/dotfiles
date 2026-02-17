#!/usr/bin/env bash
set -euo pipefail

# ─── Dotfiles installer ────────────────────────────────────────
# Symlinks dotfiles, sets up git identity, vim-plug, TPM, and SSH.
# Safe to run multiple times — existing correct links are skipped,
# conflicting files are backed up.

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── OS detection ──────────────────────────────────────────────
case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux)  OS=linux ;;
  *)      OS=unknown ;;
esac

# ─── Counters ──────────────────────────────────────────────────
linked=0
skipped=0
backed_up=0
BACKUP_DIR=""

backup() {
  if [ -z "$BACKUP_DIR" ]; then
    BACKUP_DIR="$HOME/.dotfiles_backup/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
  fi
  local dest="$1"
  local rel
  rel="${dest#$HOME/}"
  mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
  mv "$dest" "$BACKUP_DIR/$rel"
  backed_up=$((backed_up + 1))
  echo "  backed up  $dest → $BACKUP_DIR/$rel"
}

link_file() {
  local src="$1" dest="$2"

  # Already correctly linked — skip (normalize double slashes from RCM)
  local current
  current="$(readlink "$dest" 2>/dev/null | sed 's|//|/|g')"
  if [ -L "$dest" ] && [ "$current" = "$src" ]; then
    skipped=$((skipped + 1))
    return
  fi

  # Something exists at target — back it up
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    backup "$dest"
  fi

  # Create parent directories if needed
  mkdir -p "$(dirname "$dest")"
  ln -sf "$src" "$dest"
  linked=$((linked + 1))
  echo "  linked     $dest → $src"
}

# ─── Symlink map ───────────────────────────────────────────────
echo "Linking dotfiles..."

# Simple dotfiles: source name → ~/.name
dotfiles=(
  aliases
  gitconfig
  gitignore
  gitmessage
  git_template
  zshrc
  zshenv
  vimrc
  vimrc.bundles
  gvimrc
  tmux.conf
  psqlrc
  gemrc
  agignore
  hushlogin
  ctags.d
  zsh
  bin
)

for name in "${dotfiles[@]}"; do
  link_file "$DOTFILES_DIR/$name" "$HOME/.$name"
done

# config/nvim → ~/.config/nvim
link_file "$DOTFILES_DIR/config/nvim" "$HOME/.config/nvim"

# ─── Git identity ──────────────────────────────────────────────
if [ ! -f "$HOME/.gitconfig.local" ]; then
  echo ""
  echo "Setting up git identity..."
  printf "  Name: "
  read -r git_name
  printf "  Email: "
  read -r git_email

  {
    echo "[user]"
    echo "  name = $git_name"
    echo "  email = $git_email"
  } > "$HOME/.gitconfig.local"

  if [ "$OS" = "macos" ]; then
    {
      echo "[credential]"
      echo "  helper = osxkeychain"
    } >> "$HOME/.gitconfig.local"
  fi

  echo "  wrote ~/.gitconfig.local"
fi

# ─── vim-plug ──────────────────────────────────────────────────
if [ ! -f "$HOME/.vim/autoload/plug.vim" ]; then
  echo ""
  echo "Installing vim-plug..."
  curl -fLo "$HOME/.vim/autoload/plug.vim" --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  echo "  running PlugInstall..."
  vim -u "$HOME/.vimrc.bundles" +PlugInstall +PlugClean! +qa
  echo "  vim-plug installed"
else
  echo "  vim-plug already installed — skipped"
fi

# ─── TPM (tmux plugin manager) ────────────────────────────────
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  echo ""
  echo "Installing TPM..."
  git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  echo "  TPM installed (press prefix + I inside tmux to install plugins)"
else
  echo "  TPM already installed — skipped"
fi

# ─── SSH config ────────────────────────────────────────────────
if [ ! -f "$HOME/.ssh/config" ]; then
  echo ""
  echo "Setting up SSH config..."
  mkdir -p "$HOME/.ssh/sockets"
  chmod 700 "$HOME/.ssh"
  if [ -f "$DOTFILES_DIR/ssh_config.example" ]; then
    cp "$DOTFILES_DIR/ssh_config.example" "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"
    echo "  copied ssh_config.example → ~/.ssh/config"
  fi
fi

# ─── Legacy cleanup ───────────────────────────────────────────
if [ -f "$HOME/.git_template/HEAD" ] && \
   [ "$(cat "$HOME/.git_template/HEAD")" = "ref: refs/heads/main" ]; then
  echo "  removing stale ~/.git_template/HEAD (defaultBranch is in gitconfig)"
  rm -f "$HOME/.git_template/HEAD"
fi

# ─── Touch .local stubs ───────────────────────────────────────
# psqlrc sources .psqlrc.local — create it if missing to avoid errors
if [ ! -f "$HOME/.psqlrc.local" ]; then
  touch "$HOME/.psqlrc.local"
fi

# ─── Claude Code ──────────────────────────────────────────────
if command -v claude &>/dev/null || [ -d "$HOME/.claude" ]; then
  echo ""
  echo "Setting up Claude Code..."
  mkdir -p "$HOME/.claude/commands" "$HOME/.claude/hooks"

  # Global instructions
  link_file "$DOTFILES_DIR/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"

  # Slash commands
  for f in "$DOTFILES_DIR/claude/commands/"*.md; do
    [ -f "$f" ] || continue
    link_file "$f" "$HOME/.claude/commands/$(basename "$f")"
  done

  # Notification hook
  link_file "$DOTFILES_DIR/claude/hooks/notify-if-detached.sh" \
    "$HOME/.claude/hooks/notify-if-detached.sh"

  # Secrets template (copy, not symlink — user edits this)
  if [ ! -f "$HOME/.claude/hooks/.env" ]; then
    cp "$DOTFILES_DIR/claude/hooks/.env.example" "$HOME/.claude/hooks/.env"
    echo "  copied  hooks/.env.example → ~/.claude/hooks/.env"
  fi

  # Merge permissions + hooks into settings.json (preserves existing keys)
  if command -v python3 &>/dev/null; then
    python3 - "$HOME/.claude/settings.json" \
              "$DOTFILES_DIR/claude/settings-defaults.json" << 'PYEOF'
import json, sys, os

settings_path = sys.argv[1]
defaults_path = sys.argv[2]

try:
    with open(settings_path) as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

with open(defaults_path) as f:
    defaults = json.load(f)

changed = False
for key in defaults:
    if key not in settings:
        settings[key] = defaults[key]
        changed = True

if changed:
    with open(settings_path, 'w') as f:
        json.dump(settings, f, indent=2)
        f.write('\n')
    print('  updated  ~/.claude/settings.json')
else:
    print('  ~/.claude/settings.json already configured — skipped')
PYEOF
  fi
fi

# ─── Summary ──────────────────────────────────────────────────
echo ""
echo "Done! $linked linked, $skipped skipped, $backed_up backed up."
