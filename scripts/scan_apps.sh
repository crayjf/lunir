#!/bin/bash
ri() {
  local n="$1"
  [ -z "$n" ] && return
  [ "${n:0:1}" = "/" ] && [ -f "$n" ] && echo "$n" && return
  for size in 256 128 64 48 32; do
    local p="/usr/share/icons/hicolor/${size}x${size}/apps/${n}.png"
    [ -f "$p" ] && echo "$p" && return
  done
  local sv="/usr/share/icons/hicolor/scalable/apps/${n}.svg"
  [ -f "$sv" ] && echo "$sv" && return
  for dir in /usr/share/pixmaps "$HOME/.local/share/icons/hicolor/48x48/apps"; do
    [ -f "$dir/${n}.png" ] && echo "$dir/${n}.png" && return
    [ -f "$dir/${n}.svg" ] && echo "$dir/${n}.svg" && return
  done
}

find /usr/share/applications "$HOME/.local/share/applications" \
  -maxdepth 1 -name '*.desktop' 2>/dev/null | while read -r f; do
  nd=$(grep -m1 '^NoDisplay=' "$f" | cut -d= -f2- | tr A-Z a-z)
  [ "$nd" = "true" ] && continue
  nm=$(grep -m1 '^Name=' "$f" | cut -d= -f2-)
  [ -z "$nm" ] && continue
  er=$(grep -m1 '^Exec=' "$f" | cut -d= -f2-)
  ec=$(echo "$er" | sed 's/ %[A-Za-z]//g')
  ic=$(grep -m1 '^Icon=' "$f" | cut -d= -f2-)
  ip=$(ri "$ic")
  printf '%s|%s|%s\n' "$nm" "$ec" "$ip"
done | sort -u
