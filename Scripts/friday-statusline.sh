#!/usr/bin/env bash
# Copyright (c) 2026 Dhruv Chawla · SPDX-License-Identifier: MIT
#
# Claude Code status line command that shares your plan limits with Friday.
#
# Claude Code pipes a JSON description of the session to this script after
# each reply. For Pro/Max subscribers it includes `rate_limits` (5-hour and
# weekly used percentage and reset time). This script saves ONLY those
# numbers, plus the time, to ~/.claude/friday/rate-limits.json, which Friday
# reads. It makes no network calls and saves nothing else (no prompts, paths
# or session IDs). It then prints a short status line, e.g. "5h 23% · 7d 41%".
#
# Setup (once): add this to ~/.claude/settings.json
#   "statusLine": { "type": "command", "command": "/path/to/Friday/Scripts/friday-statusline.sh" }
# To keep a status line you already have, set FRIDAY_STATUSLINE_NEXT to its
# command; this script then passes the same input to it and prints its output.
set -uo pipefail

input=$(cat)
out_dir="$HOME/.claude/friday"
out_file="$out_dir/rate-limits.json"

if command -v jq >/dev/null 2>&1; then
  limits=$(printf '%s' "$input" | jq -c --argjson now "$(date +%s)" '
    if (.rate_limits.five_hour // .rate_limits.seven_day) == null then empty else
      { captured_at: $now,
        rate_limits: (.rate_limits | {five_hour, seven_day} | with_entries(select(.value != null))
          | map_values({used_percentage, resets_at})) }
    end' 2>/dev/null)
  if [ -n "$limits" ]; then
    mkdir -p "$out_dir"
    tmp=$(mktemp "$out_dir/.rate-limits.XXXXXX") && printf '%s\n' "$limits" >"$tmp" && mv -f "$tmp" "$out_file"
  fi
fi

if [ -n "${FRIDAY_STATUSLINE_NEXT:-}" ]; then
  printf '%s' "$input" | bash -c "$FRIDAY_STATUSLINE_NEXT"
elif command -v jq >/dev/null 2>&1; then
  printf '%s' "$input" | jq -r '. as $in |
    [ (.rate_limits.five_hour.used_percentage // empty | "5h \(floor)%"),
      (.rate_limits.seven_day.used_percentage // empty | "7d \(floor)%") ]
    | if length == 0 then ($in.model.display_name // "Claude") else join(" · ") end' 2>/dev/null
fi
exit 0
