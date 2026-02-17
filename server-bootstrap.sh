#!/usr/bin/env bash
set -euo pipefail

# ─── Server Bootstrap ────────────────────────────────────────
# Sets up a fresh Ubuntu Server as a headless dev environment.
# Installs system packages, dev toolchains, Tailscale, dotfiles.
# Idempotent — safe to re-run.

DOTFILES_REPO="https://github.com/cmotta/dotfiles.git"
DOTFILES_DIR="$HOME/Code/dotfiles"

# ─── Helpers ──────────────────────────────────────────────────

info()  { echo "==> $*"; }
skip()  { echo "  already installed — skipped"; }

has() { command -v "$1" &>/dev/null; }

# ─── 1. System packages ──────────────────────────────────────

info "Updating system packages..."
sudo apt update && sudo apt upgrade -y

PACKAGES=(
  zsh git curl wget unzip
  build-essential cmake pkg-config
  neovim tmux ripgrep fd-find bat jq
  python3 python3-venv python3-pip
  htop tree
)

info "Installing system packages..."
sudo apt install -y "${PACKAGES[@]}"

# Ubuntu uses different binary names for fd and bat
if has fdfind && ! has fd; then
  sudo ln -sf "$(which fdfind)" /usr/local/bin/fd
  echo "  symlinked fdfind → fd"
fi

if has batcat && ! has bat; then
  sudo ln -sf "$(which batcat)" /usr/local/bin/bat
  echo "  symlinked batcat → bat"
fi

# ─── 2. Install GitHub CLI ───────────────────────────────────

if ! has gh; then
  info "Installing GitHub CLI..."
  (type -p wget >/dev/null || sudo apt install -y wget) \
    && sudo mkdir -p -m 755 /etc/apt/keyrings \
    && out=$(mktemp) && wget -qO "$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    && cat "$out" | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null \
    && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null \
    && sudo apt update && sudo apt install -y gh
else
  info "GitHub CLI"
  skip
fi

# ─── 3. Install AWS CLI v2 ───────────────────────────────────

if ! has aws; then
  info "Installing AWS CLI v2..."
  tmpdir=$(mktemp -d)
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$tmpdir/awscliv2.zip"
  unzip -q "$tmpdir/awscliv2.zip" -d "$tmpdir"
  sudo "$tmpdir/aws/install"
  rm -rf "$tmpdir"
else
  info "AWS CLI"
  skip
fi

# ─── 4. Set zsh as default shell ─────────────────────────────

if [ "$SHELL" != "$(which zsh)" ]; then
  info "Setting zsh as default shell..."
  chsh -s "$(which zsh)"
  echo "  zsh will be active on next login"
else
  info "Default shell"
  skip
fi

# ─── 5. Install Tailscale ────────────────────────────────────

if ! has tailscale; then
  info "Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
else
  info "Tailscale"
  skip
fi

if ! tailscale status &>/dev/null; then
  info "Starting Tailscale — authenticate via the URL below..."
  sudo tailscale up
else
  info "Tailscale auth"
  skip
fi

# ─── 6. GitHub auth (fine-grained PAT) ───────────────────────
# Uses a fine-grained personal access token for HTTPS cloning.
# Create one at: github.com/settings/personal-access-tokens/new
# Required permissions: Contents (read & write), Metadata (read)

if ! gh auth status &>/dev/null; then
  info "Authenticating GitHub..."
  echo "  Enter a fine-grained PAT with Contents (read/write) access."
  echo "  Create one at: https://github.com/settings/personal-access-tokens/new"
  printf "  GitHub PAT: "
  read -rs GITHUB_TOKEN
  echo ""

  # Store credential for git
  git config --global credential.helper store
  printf "https://x-access-token:%s@github.com\n" "$GITHUB_TOKEN" \
    > "$HOME/.git-credentials"
  chmod 600 "$HOME/.git-credentials"

  # Authenticate gh CLI with the same token
  echo "$GITHUB_TOKEN" | gh auth login --with-token
  echo "  GitHub authenticated"
fi

# ─── 7. Clone dotfiles and run install.sh ─────────────────────

if [ ! -d "$DOTFILES_DIR" ]; then
  info "Cloning dotfiles..."
  mkdir -p "$HOME/Code"
  git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
else
  info "Dotfiles repo"
  skip
fi

info "Running dotfiles installer..."
cd "$DOTFILES_DIR" && ./install.sh

# ─── 8. Install uv (Python toolchain) ────────────────────────

if ! has uv; then
  info "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
else
  info "uv"
  skip
fi

if ! has ruff; then
  info "Installing ruff via uv..."
  uv tool install ruff
else
  info "ruff"
  skip
fi

# ─── 9. Install fnm + Node.js + pnpm ─────────────────────────

if ! has fnm; then
  info "Installing fnm..."
  curl -fsSL https://fnm.vercel.app/install | bash
  export PATH="$HOME/.local/share/fnm:$PATH"
  eval "$(fnm env)"
else
  info "fnm"
  skip
fi

if ! has node; then
  info "Installing Node.js LTS via fnm..."
  eval "$(fnm env)"
  fnm install --lts
else
  info "Node.js"
  skip
fi

if ! has pnpm; then
  info "Enabling pnpm via corepack..."
  eval "$(fnm env)"
  corepack enable
  corepack prepare pnpm@latest --activate
else
  info "pnpm"
  skip
fi

# ─── 10. Install Claude Code CLI ─────────────────────────────

if ! has claude; then
  info "Installing Claude Code CLI..."
  eval "$(fnm env)"
  npm install -g @anthropic-ai/claude-code
else
  info "Claude Code CLI"
  skip
fi

# ─── 11. Create ~/.zshrc.local stub ──────────────────────────

if [ ! -f "$HOME/.zshrc.local" ]; then
  info "Creating ~/.zshrc.local..."
  cat > "$HOME/.zshrc.local" << 'EOF'
# Machine-local zsh configuration (server)

# fnm (Node version manager)
if [ -d "$HOME/.local/share/fnm" ]; then
  export PATH="$HOME/.local/share/fnm:$PATH"
  eval "$(fnm env --use-on-cd --shell zsh)"
fi

# uv (Python toolchain)
if [ -d "$HOME/.local/bin" ]; then
  export PATH="$HOME/.local/bin:$PATH"
  eval "$(uv generate-shell-completion zsh)"
fi

# Claude Code
# export ANTHROPIC_API_KEY="sk-ant-..."
EOF
  echo "  wrote ~/.zshrc.local"
else
  info "~/.zshrc.local"
  skip
fi

# ─── 12. Install tmux plugins headlessly ─────────────────────

if [ -x "$HOME/.tmux/plugins/tpm/bin/install_plugins" ]; then
  info "Installing tmux plugins..."
  "$HOME/.tmux/plugins/tpm/bin/install_plugins"
else
  info "TPM not found — skipping tmux plugin install"
fi

# ─── 13. Verification checklist ──────────────────────────────

echo ""
echo "════════════════════════════════════════════════════"
echo "  Bootstrap complete! Verification:"
echo "════════════════════════════════════════════════════"

# Reload PATH for version checks
export PATH="$HOME/.local/bin:$HOME/.local/share/fnm:$PATH"
has fnm && eval "$(fnm env)"

check() {
  local name="$1" cmd="$2"
  if has "$cmd"; then
    printf "  %-12s %s\n" "$name" "$($cmd --version 2>&1 | head -1)"
  else
    printf "  %-12s %s\n" "$name" "NOT FOUND"
  fi
}

check "zsh"       zsh
check "neovim"    nvim
check "tmux"      tmux
check "gh"        gh
check "aws"       aws
check "uv"        uv
check "node"      node
check "pnpm"      pnpm
check "claude"    claude
check "tailscale" tailscale

echo ""
echo "Next steps:"
echo "  1. Log out and back in (or run: exec zsh)"
echo "  2. Set ANTHROPIC_API_KEY in ~/.zshrc.local"
echo "  3. Configure notifications: ~/.claude/hooks/.env"
echo "  4. Set up AWS credentials if using SNS/SES: aws configure"
echo "  5. Test: claude-headless \"echo hello\""
echo ""
