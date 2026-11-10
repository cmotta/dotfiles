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

# ─── 2b. Install GitLab CLI (official .deb from the release) ─

if ! has glab; then
  info "Installing GitLab CLI..."
  glab_tag=$(curl -fsSL "https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases?per_page=1" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["tag_name"])')
  glab_ver="${glab_tag#v}"
  glab_deb="glab_${glab_ver}_linux_$(dpkg --print-architecture).deb"
  tmpdir=$(mktemp -d)
  curl -fsSL -o "$tmpdir/$glab_deb" \
    "https://gitlab.com/gitlab-org/cli/-/releases/${glab_tag}/downloads/${glab_deb}"
  sudo apt install -y "$tmpdir/$glab_deb"
  rm -rf "$tmpdir"
else
  info "GitLab CLI"
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
  curl -fsSL https://tailscale.com/install.sh -o /tmp/tailscale-install.sh
  sh /tmp/tailscale-install.sh
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

# ─── 6. Forge logins (done by you, once) ─────────────────────
# gh and glab store the token and act as git's credential helper for HTTPS
# clones, so no PAT is pasted here. Run the logins after the bootstrap.
# Both write the helper into ~/.gitconfig, which is the dotfiles symlink, so
# move those [credential] lines into ~/.gitconfig.local and `git checkout
# gitconfig` afterwards. On a headless box glab's web login needs its
# callback tunnelled: `ssh -L 7171:127.0.0.1:7171 HOST` from the laptop.

if gh auth status &>/dev/null; then
  info "GitHub auth"; skip
else
  info "GitHub auth: run  gh auth login && gh auth setup-git"
fi
if has glab && glab auth status &>/dev/null; then
  info "GitLab auth"; skip
else
  info "GitLab auth: run  glab auth login   (HTTPS, git credential helper: yes; see §6 for the headless tunnel)"
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
  curl -LsSf https://astral.sh/uv/install.sh -o /tmp/uv-install.sh
  sh /tmp/uv-install.sh --no-modify-path   # ~/.zshrc.local adds ~/.local/bin; keep ~/.zshrc untouched
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
  curl -fsSL https://fnm.vercel.app/install -o /tmp/fnm-install.sh
  bash /tmp/fnm-install.sh --skip-shell   # ~/.zshrc.local sets up fnm; keep ~/.zshrc untouched
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

# Ensure fnm shims (node, npm, etc.) are on PATH for the rest of the script
export PATH="$HOME/.local/share/fnm:$PATH"
has fnm && eval "$(fnm env)"

if ! has pnpm; then
  info "Installing pnpm..."   # via npm: the standalone installer edits ~/.zshrc
  npm install -g pnpm
else
  info "pnpm"
  skip
fi

# ─── 10. Install Claude Code CLI ─────────────────────────────

if ! has claude; then
  info "Installing Claude Code CLI (native installer, into ~/.local/bin)..."
  curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh
  bash /tmp/claude-install.sh
  export PATH="$HOME/.local/bin:$PATH"
else
  info "Claude Code CLI"
  skip
fi

# ─── 10b. Rex server (apt repo, user service, linger) ────────
# Personal Rex server reachable over the tailnet; the unit files come from
# dotfiles (config/rex/systemd, linked by install.sh). Ubuntu ships an
# unrelated Perl package called rex, hence the pin.

if ! [ -f /etc/apt/sources.list.d/rex.sources ]; then
  info "Adding the Rex apt repository..."
  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://pkgs.superlogical.com/rex/keys/rex-archive-keyring.gpg \
    | sudo tee /etc/apt/keyrings/rex-archive-keyring.gpg >/dev/null
  sudo tee /etc/apt/sources.list.d/rex.sources >/dev/null <<SRC
Types: deb
URIs: https://pkgs.superlogical.com/rex/apt
Suites: snapshot
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/rex-archive-keyring.gpg
SRC
  sudo tee /etc/apt/preferences.d/rex >/dev/null <<PIN
Package: rex
Pin: origin pkgs.superlogical.com
Pin-Priority: 1001
PIN
  sudo apt update
fi

# Ubuntu's rex (1.14, Perl) sorts above ours (0.0.<epoch>). The pin makes
# apt prefer ours, but unattended-upgrades ignores pins: when the candidate
# comes from a repo it does not manage it installs the newest version from
# the repos it does, which on 10 Nov 2026 replaced Rex with the Perl tool.
# A hold is the one thing unattended-upgrades respects.
if [[ "$(dpkg-query -W -f '${Version}' rex 2>/dev/null)" != 0.0.* ]]; then
  info "Installing Rex..."
  sudo apt install -y --allow-downgrades rex
else
  info "Rex"
  skip
fi
sudo apt-mark hold rex >/dev/null

if [ -f "$HOME/.config/systemd/user/rex.service" ]; then
  if systemctl --user is-active -q rex; then
    info "Rex server service"; skip
  else
    info "Starting the Rex server service..."
    systemctl --user daemon-reload
    systemctl --user enable -q --now rex rex-save.timer
  fi
  if [ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)" != "yes" ]; then
    info "Keeping user services running after logout (linger)..."
    sudo loginctl enable-linger "$USER"
  fi
fi

# ─── 10c. Clone the repo tree ────────────────────────────────
# ~/.repos.local lists "<dir> <url>" under ~/Code (see repos.local.example).
# Clones need the forge logins above; failures are reported, not fatal.

if [ -f "$HOME/.repos.local" ]; then
  info "Cloning repos from ~/.repos.local..."
  "$DOTFILES_DIR/bin/clone-repos" || true
else
  info "No ~/.repos.local: copy repos.local.example there and run clone-repos"
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

# pnpm
if [ -d "$HOME/.local/share/pnpm" ]; then
  export PNPM_HOME="$HOME/.local/share/pnpm"
  export PATH="$PNPM_HOME:$PATH"
fi

# Claude Code — authenticate with: claude login
# Or set an API key as fallback:
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
check "glab"      glab
check "aws"       aws
check "uv"        uv
check "node"      node
check "pnpm"      pnpm
check "claude"    claude
check "tailscale" tailscale
printf "  %-12s %s\n" "rex" "$(has rex && systemctl --user is-active rex 2>/dev/null || echo NOT FOUND)"

echo ""
echo "Next steps:"
echo "  1. Log out and back in (or run: exec zsh)"
echo "  2. Log in: gh auth login && gh auth setup-git; glab auth login; claude"
echo "  3. Edit ~/.repos.local and run clone-repos"
echo "  4. Configure notifications: ~/.claude/hooks/.env"
echo "  5. Set up AWS credentials if using SNS/SES: aws configure"
echo "  6. Rex: add this host in the Mac app, then rx tab / rx ws from a shell"
echo ""
