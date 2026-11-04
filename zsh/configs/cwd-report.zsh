# Report the working directory to the terminal (OSC 7) on every cd, so a
# new split or tab can start in the same directory. Rex, iTerm2, Ghostty
# and others understand it; a terminal that does not just ignores it.

_cwd_report() {
  [[ -t 1 ]] || return
  local path="$PWD" encoded="" c
  for c in ${(s::)path}; do
    case "$c" in
      [A-Za-z0-9/._~-]) encoded+="$c" ;;
      *) encoded+="$(printf '%%%02X' "'$c")" ;;
    esac
  done
  printf '\e]7;file://%s%s\e\\' "$HOST" "$encoded"
}

autoload -Uz add-zsh-hook
add-zsh-hook chpwd _cwd_report
_cwd_report
