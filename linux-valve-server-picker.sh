#!/usr/bin/env bash
# This is a Valve SDR relay blocker for CS2 / Deadlock / Marathon / THE FINALS
#
# Fixes the bug in other server picker's Linux build (that use "iptables -A INPUT -s",
# which blocks the relay's REPLIES to you but not your OUTGOING connection
# attempt, so matchmaking doesn't actually skip the server). This script uses
# "-A OUTPUT -d" instead.
# The data source I used was: Valve's public Steam Web API (no key required), the exact same

set -euo pipefail

STATE_DIR="$HOME/.config/cs-server-picker"
STATE_FILE="$STATE_DIR/blocked.tsv"
mkdir -p "$STATE_DIR"
touch "$STATE_FILE"

declare -A APPIDS=(
  [cs2]=730
  [deadlock]=1422450
  [marathon]=3065800
  [finals]=2073850
)

usage() {
  cat <<EOF
Usage:
  $0 list <game>                  List available POPs (regions) and their relay IPs
  $0 block <game> <pop> [pop...]  Block the given POP(s) — use POP codes from 'list'
  $0 unblock <game> <pop> [...]   Unblock the given POP(s)
  $0 status                       Show everything currently blocked by this script
  $0 reset                        Remove ALL rules this script added (safe — leaves
                                   the rest of your firewall untouched)

Games: cs2, deadlock, marathon, finals

Example:
  $0 list cs2
  $0 block cs2 jnb dxb            # block Johannesburg + Dubai relays
  $0 status
  $0 unblock cs2 jnb
  $0 reset
EOF
  exit 1
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "This script needs 'jq'. Install it with: sudo apt install jq" >&2
    exit 1
  fi
}

fetch_pops() {
  local game="$1"
  local appid="${APPIDS[$game]:?Unknown game '$game'. Valid: ${!APPIDS[*]}}"
  curl -fsSL "https://api.steampowered.com/ISteamApps/GetSDRConfig/v1/?appid=${appid}" \
    | jq -r '.pops | to_entries[] | select(.value.relays != null) |
        "\(.key)\t\(.value.desc)\t\([.value.relays[].ipv4] | join(","))"'
}

cmd_list() {
  local game="${1:?Specify a game (cs2, deadlock, marathon, finals)}"
  printf "%-8s %-28s %s\n" "POP" "REGION" "RELAY IPs"
  fetch_pops "$game" | while IFS=$'\t' read -r pop desc ips; do
    printf "%-8s %-28s %s\n" "$pop" "$desc" "$ips"
  done
}

cmd_block() {
  local game="${1:?Specify a game}"; shift
  [ "$#" -gt 0 ] || usage
  local pops_data
  pops_data="$(fetch_pops "$game")"
  for pop in "$@"; do
    local line desc ips
    line="$(printf '%s\n' "$pops_data" | awk -F'\t' -v p="$pop" '$1==p')"
    if [ -z "$line" ]; then
      echo "WARNING: POP '$pop' not found for $game (check '$0 list $game'), skipping" >&2
      continue
    fi
    desc="$(printf '%s' "$line" | cut -f2)"
    ips="$(printf '%s' "$line" | cut -f3)"
    IFS=',' read -ra ip_array <<< "$ips"
    for ip in "${ip_array[@]}"; do
      local tag="csp_${game}_${pop}"
      if ! sudo iptables -C OUTPUT -d "$ip" -j DROP -m comment --comment "$tag" 2>/dev/null; then
        sudo iptables -A OUTPUT -d "$ip" -j DROP -m comment --comment "$tag"
        printf '%s\t%s\t%s\t%s\n' "$game" "$pop" "$desc" "$ip" >> "$STATE_FILE"
      fi
    done
    echo "Blocked $game POP '$pop' ($desc) — ${#ip_array[@]} relay IP(s)"
  done
}

cmd_unblock() {
  local game="${1:?Specify a game}"; shift
  [ "$#" -gt 0 ] || usage
  for pop in "$@"; do
    while IFS=$'\t' read -r g p _desc ip; do
      [ "$g" = "$game" ] && [ "$p" = "$pop" ] || continue
      sudo iptables -D OUTPUT -d "$ip" -j DROP -m comment --comment "csp_${g}_${p}" 2>/dev/null || true
    done < "$STATE_FILE"
    grep -v -P "^${game}\t${pop}\t" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
    echo "Unblocked $game POP '$pop'"
  done
}

cmd_status() {
  if [ ! -s "$STATE_FILE" ]; then
    echo "Nothing currently blocked."
    return
  fi
  printf "%-10s %-8s %-28s %s\n" "GAME" "POP" "REGION" "IP"
  while IFS=$'\t' read -r g p desc ip; do
    printf "%-10s %-8s %-28s %s\n" "$g" "$p" "$desc" "$ip"
  done < "$STATE_FILE"
}

cmd_reset() {
  if [ ! -s "$STATE_FILE" ]; then
    echo "Nothing to reset."
    return
  fi
  while IFS=$'\t' read -r g p _desc ip; do
    sudo iptables -D OUTPUT -d "$ip" -j DROP -m comment --comment "csp_${g}_${p}" 2>/dev/null || true
  done < "$STATE_FILE"
  : > "$STATE_FILE"
  echo "All server-picker rules removed. Rest of your firewall is untouched."
}

require_jq

case "${1:-}" in
  list)    shift; cmd_list "$@" ;;
  block)   shift; cmd_block "$@" ;;
  unblock) shift; cmd_unblock "$@" ;;
  status)  shift; cmd_status "$@" ;;
  reset)   shift; cmd_reset "$@" ;;
  *) usage ;;
esac
