# load custom executable functions (skip when directory is empty)
if [ -d "$HOME/.zsh/functions" ]; then
  for function in "$HOME"/.zsh/functions/*(N-.); do
    source "$function"
  done
fi

# extra files in ~/.zsh/configs/pre , ~/.zsh/configs , and ~/.zsh/configs/post
# these are loaded first, second, and third, respectively.
_load_settings() {
  _dir="$1"
  if [ -d "$_dir" ]; then
    if [ -d "$_dir/pre" ]; then
      for config in "$_dir"/pre/**/*(N-.); do
        . "$config"
      done
    fi

    for config in "$_dir"/**/*(N-.); do
      case "$config" in
        "$_dir"/(pre|post)/*|*.zwc)
          :
          ;;
        *)
          . "$config"
          ;;
      esac
    done

    if [ -d "$_dir/post" ]; then
      for config in "$_dir"/post/**/*(N-.); do
        . "$config"
      done
    fi
  fi
}
_load_settings "$HOME/.zsh/configs"

# Local config
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
typeset -U path PATH

path=(/usr/local/bin $path)

# aliases
[[ -f ~/.aliases ]] && source ~/.aliases

# Bun
export BUN_INSTALL="$HOME/.bun"
if [ -d "$BUN_INSTALL/bin" ]; then
  path=($BUN_INSTALL/bin $path)
fi
# bun completions
[ -s "$BUN_INSTALL/_bun" ] && source "$BUN_INSTALL/_bun"

# pnpm
if [ "$(uname -s)" = "Darwin" ]; then
  export PNPM_HOME="$HOME/Library/pnpm"
else
  export PNPM_HOME="$HOME/.local/share/pnpm"
fi
if [ -d "$PNPM_HOME" ]; then
  path=($PNPM_HOME $path)
fi
# pnpm end
