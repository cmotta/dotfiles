#!/bin/sh
# Claude Code status line
# Line 1: dir | branch +added -removed  [agent]
# Line 2: context | cost | duration | transcript

input=$(cat)

# --- Extract all fields in a single jq invocation ---
eval "$(echo "$input" | jq -r '
  @sh "model=\(.model.display_name // "")",
  @sh "cwd=\(.workspace.current_dir // .cwd)",
  @sh "ctx_size=\(.context_window.context_window_size // 200000)",
  @sh "ctx_pct=\(.context_window.used_percentage // 0)",
  @sh "agent_name=\(.agent.name // "")",
  @sh "cost_usd=\(.cost.total_cost_usd // 0)",
  @sh "duration_ms=\(.cost.total_duration_ms // 0)",
  @sh "lines_added=\(.cost.total_lines_added // 0)",
  @sh "lines_removed=\(.cost.total_lines_removed // 0)",
  @sh "transcript=\(.transcript_path // "")"
')"

dir=$(basename "$cwd")

# Git branch
git_branch=""
if git_branch_out=$(git -C "$cwd" -c gc.auto=0 symbolic-ref --short HEAD 2>/dev/null); then
  git_branch="$git_branch_out"
fi

# --- Derived display values ---
ctx_pct_int=$(printf '%.0f' "$ctx_pct")

# Progress bar: color by usage level
if [ "$ctx_pct_int" -ge 90 ]; then BAR_COLOR='\033[31m'    # red
elif [ "$ctx_pct_int" -ge 70 ]; then BAR_COLOR='\033[33m'  # yellow
else BAR_COLOR='\033[32m'; fi                               # green

filled=$((ctx_pct_int / 10)); empty=$((10 - filled))
bar=$(printf "%${filled}s" | tr ' ' '█')$(printf "%${empty}s" | tr ' ' '░')

cost_fmt=$(printf '$%.2f' "$cost_usd")

dur_min=$((duration_ms / 60000))
dur_sec=$(((duration_ms % 60000) / 1000))

transcript_name=""
if [ -n "$transcript" ]; then
  transcript_name=$(basename "$transcript")
fi

# --- Colors ---
C='\033[36m'     # cyan
G='\033[32m'     # green
Y='\033[33m'     # yellow
R='\033[31m'     # red
D='\033[2m'      # dim
Z='\033[0m'      # reset

# --- Line 1: model + workspace + git + lines changed ---
line1="${C}[${model}]${Z} 📁 ${dir}"
if [ -n "$git_branch" ]; then
  line1="${line1} ${D}|${Z} 🌿 ${git_branch}"
  [ "$lines_added" -gt 0 ] && line1="${line1} ${G}+${lines_added}${Z}"
  [ "$lines_removed" -gt 0 ] && line1="${line1} ${R}-${lines_removed}${Z}"
fi
[ -n "$agent_name" ] && line1="${line1}  🤖 ${agent_name}"
printf '%b\n' "$line1"

# --- Line 2: progress bar | cost | duration | transcript ---
line2="${BAR_COLOR}${bar}${Z} ${ctx_pct_int}% ${D}|${Z} ${Y}${cost_fmt}${Z} ${D}|${Z} ⏱️ ${dur_min}m ${dur_sec}s"
if [ -n "$transcript" ]; then
  line2="${line2} ${D}|${Z} $(printf '\033]8;;file://%s\a%s\033]8;;\a' "$transcript" "$transcript_name")"
fi
printf '%b\n' "$line2"
