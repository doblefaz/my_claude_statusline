#!/usr/bin/env bash
# Claude Code status line: working dirs with git branch + model/context/rate limits.
# Reads the statusline JSON from stdin.

input=$(cat)

# Avoid printf errors with locales that use a decimal comma
export LC_NUMERIC=C

R=$'\033[0m'
GRAY=$'\033[38;5;250m'
DIM=$'\033[2;37m'
CYAN=$'\033[36m'
ORANGE=$'\033[38;5;208m'
YELLOW=$'\033[38;5;226m'
LBLUE=$'\033[38;5;117m'
BLUE=$'\033[34m'

# Compact token formatter: 45200 -> 45.2k, 200000 -> 200k, 1000000 -> 1M
fmt_tokens() {
  awk -v n="$1" 'BEGIN {
    if (n !~ /^[0-9.]+$/) { print "--"; exit }
    if (n >= 1000000)      { v = n / 1000000; s = "M" }
    else if (n >= 1000)    { v = n / 1000;    s = "k" }
    else                   { printf "%d", n; exit }
    t = sprintf("%.1f", v); sub(/\.0$/, "", t); print t s
  }'
}

# Epoch seconds or ISO 8601 string -> formatted local time (arg2 = date format)
fmt_time() {
  local ts="$1" fmt="$2"
  [ -z "$ts" ] && return
  if [[ "$ts" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    ts=${ts%.*}
    # Tolerate milliseconds
    [ "${#ts}" -ge 13 ] && ts=$((ts / 1000))
    date -d "@$ts" +"$fmt" 2>/dev/null
  else
    date -d "$ts" +"$fmt" 2>/dev/null
  fi
}

# --- Section 1: main dir (workspace.current_dir, fallback cwd) first, then added dirs ---
while IFS= read -r dir; do
  [ -z "$dir" ] && continue
  branch=""
  if git -C "$dir" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git -C "$dir" --no-optional-locks branch --show-current 2>/dev/null)
    [ -z "$branch" ] && branch=$(git -C "$dir" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  fi
  # Show $HOME as ~ (only for the home itself or a subdirectory, not /home/jmino2)
  shown="$dir"
  case "$dir" in "$HOME"|"$HOME"/*) shown="~${dir#"$HOME"}" ;; esac
  if [ -n "$branch" ]; then
    printf ' • %s%s%s %s(%s)%s\n' "$GRAY" "$shown" "$R" "$CYAN" "$branch" "$R"
  else
    printf ' • %s%s%s %s(no git)%s\n' "$GRAY" "$shown" "$R" "$DIM" "$R"
  fi
done < <(printf '%s' "$input" | jq -r '[(.workspace.current_dir // .cwd), (.workspace.added_dirs // [])[]?] | .[] | strings' 2>/dev/null)

# --- Section 2: summary line ---
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty' 2>/dev/null)
size=$(printf '%s' "$input" | jq -r '.context_window.context_window_size // empty' 2>/dev/null)
# Tokens in current context: sum of current_usage; otherwise estimated from used_percentage
used=$(printf '%s' "$input" | jq -r '
  (.context_window.current_usage // null) as $u
  | if $u != null then (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0))
    elif (.context_window.used_percentage != null and .context_window.context_window_size != null)
      then (.context_window.used_percentage * .context_window.context_window_size / 100 | floor)
    else empty end' 2>/dev/null)
h5=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
h5r=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)
wk=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
wkr=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.resets_at // empty' 2>/dev/null)

segs=()

# Effort: absent if the model does not support it
effort=$(printf '%s' "$input" | jq -r '.effort.level // empty' 2>/dev/null)
[ -n "$model" ] && [ -n "$effort" ] && model="$model ($effort)"
[ -n "$model" ] && segs+=("$(printf '%s%s%s' "$ORANGE" "$model" "$R")")

if [ -n "$used" ] || [ -n "$size" ]; then
  u="--"; s="--"
  [ -n "$used" ] && u=$(fmt_tokens "$used")
  [ -n "$size" ] && s=$(fmt_tokens "$size")
  # Percentage: use used_percentage if present, otherwise compute it
  pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
  if [ -z "$pct" ] && [ -n "$used" ] && [ -n "$size" ] && [ "$size" != 0 ]; then
    pct=$(awk -v u="$used" -v s="$size" 'BEGIN { print u * 100 / s }')
  fi
  txt="$u/$s"
  [ -n "$pct" ] && txt="$(printf '%.0f%%' "$pct") ($txt)"
  segs+=("$(printf '%s%s%s' "$YELLOW" "$txt" "$R")")
fi

if [ -n "$h5" ]; then
  t=$(fmt_time "$h5r" '%H:%M')
  txt=$(printf '%.0f%%' "$h5")
  [ -n "$t" ] && txt="$txt ($t)"
  segs+=("$(printf '%s%s%s' "$LBLUE" "$txt" "$R")")
fi

if [ -n "$wk" ]; then
  t=$(fmt_time "$wkr" '%d/%m %H:%M')
  txt=$(printf '%.0f%%' "$wk")
  [ -n "$t" ] && txt="$txt ($t)"
  segs+=("$(printf '%s%s%s' "$BLUE" "$txt" "$R")")
fi

out=""
for seg in "${segs[@]}"; do
  [ -z "$out" ] && out="$seg" || out="$out | $seg"
done

# --- System info: RAM and CPU temperature ---
GREEN=$'\033[32m'
RED=$'\033[31m'
sys=()

# Used RAM = total - available (reclaimable cache counts as free)
ram=$(awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2}
  END { if (t > 0) { u = t - a; printf "%.0f%% (%.1fG/%.1fG)", u * 100 / t, u / 1048576, t / 1048576 } }' /proc/meminfo 2>/dev/null)
[ -n "$ram" ] && sys+=("$(printf '%s%s%s' "$GREEN" "$ram" "$R")")

# CPU package temperature (x86_pkg_temp); if missing, the first available zone
temp=""
for z in /sys/class/thermal/thermal_zone*; do
  [ "$(cat "$z/type" 2>/dev/null)" = "x86_pkg_temp" ] && { temp=$(cat "$z/temp" 2>/dev/null); break; }
done
[ -z "$temp" ] && temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
if [[ "$temp" =~ ^[0-9]+$ ]]; then
  temp=$((temp / 1000))
  # Thresholds: <70 green, 70-84 yellow, >=85 red
  if   [ "$temp" -ge 85 ]; then tc="$RED"
  elif [ "$temp" -ge 70 ]; then tc="$YELLOW"
  else tc="$GREEN"; fi
  sys+=("$(printf '%s%s° C%s' "$tc" "$temp" "$R")")
fi

right=""
for seg in "${sys[@]}"; do
  [ -z "$right" ] && right="$seg" || right="$right | $seg"
done

if [ -n "$right" ]; then
  [ -n "$out" ] && out="$out | $right" || out="$right"
fi
printf '%s\n' "$out"
