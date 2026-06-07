#!/bin/sh
set -eu

patch_marker="fake-mobile-status:erlpack-patcher:v1"
action="menu"
channel="auto"
discord_path=""
no_run=0

usage() {
  cat <<'EOF'
Usage:
  patcher.sh [status|install|uninstall] [--channel stable|canary|auto] [--discord-path PATH]
  patcher.sh --action status --channel stable
EOF
}

fail() {
  echo "Failed: $*" >&2
  exit 1
}

is_number() {
  case "$1" in
    ''|*[!0-9.]*) return 1 ;;
    *) return 0 ;;
  esac
}

version_key() {
  name="$1"
  value=${name#app-}
  is_number "$value" || return 1
  awk -v version="$value" 'BEGIN {
    n = split(version, parts, ".")
    for (i = 1; i <= 4; i++) {
      printf "%06d", (i <= n ? parts[i] : 0)
    }
  }'
}

normalize_content() {
  sed 's/\r$//' "$1"
}

patched_wrapper() {
  cat <<'EOF'
"use strict";
// fake-mobile-status:erlpack-patcher:v1
const erlpack = require("./discord_erlpack.node");
const originalPack = erlpack.pack;

erlpack.pack = function (payload, ...rest) {
  let nextPayload = payload;
  try {
    if (payload?.op === 2 && payload?.d?.properties) {
      nextPayload = {
        ...payload,
        d: {
          ...payload.d,
          properties: {
            ...payload.d.properties,
            os: "Android",
            browser: "Discord Android",
            device: "Discord Android"
          }
        }
      };
    }
  } catch {
    nextPayload = payload;
  }
  return originalPack.call(this, nextPayload, ...rest);
};

module.exports = erlpack;
EOF
}

wrapper_status() {
  file="$1"
  content=$(normalize_content "$file")
  patched=$(patched_wrapper)
  official_single=$(printf '"use strict";\nmodule.exports = require('\''./discord_erlpack.node'\'');')
  official_double=$(printf '"use strict";\nmodule.exports = require("./discord_erlpack.node");')

  if [ "$content" = "$official_single" ] || [ "$content" = "$official_double" ]; then
    echo "official"
    return
  fi
  if [ "$content" = "$patched" ]; then
    echo "patched"
    return
  fi
  if printf '%s\n' "$content" | grep -F "$patch_marker" >/dev/null 2>&1; then
    echo "stale-patch"
    return
  fi
  echo "unknown/third-party"
}

default_channel_directory() {
  case "$1" in
    stable) printf '%s\n' "$HOME/Library/Application Support/discord" ;;
    canary) printf '%s\n' "$HOME/Library/Application Support/discordcanary" ;;
    *) fail "unsupported channel: $1" ;;
  esac
}

resolve_path() {
  path="$1"
  if [ -d "$path" ]; then
    (cd -P "$path" && pwd)
  else
    directory=$(dirname "$path")
    name=$(basename "$path")
    printf '%s/%s\n' "$(cd -P "$directory" && pwd)" "$name"
  fi
}

find_discord_target() {
  root="$1"
  [ -d "$root" ] || return 1
  resolved_root=$(resolve_path "$root")
  candidates=""

  for app_dir in "$root"/*; do
    [ -d "$app_dir" ] || continue
    app_name=$(basename "$app_dir")
    key=$(version_key "$app_name" 2>/dev/null || true)
    [ -n "$key" ] || continue
    modules="$app_dir/modules"
    [ -d "$modules" ] || continue

    for erlpack_dir in "$modules"/discord_erlpack-*; do
      [ -d "$erlpack_dir" ] || continue
      erlpack_name=$(basename "$erlpack_dir")
      erlpack_version=${erlpack_name#discord_erlpack-}
      erlpack_key=$(version_key "$erlpack_version" 2>/dev/null || true)
      [ -n "$erlpack_key" ] || continue
      wrapper="$erlpack_dir/discord_erlpack/index.js"
      [ -f "$wrapper" ] || continue
      candidates="${candidates}${key} ${erlpack_key} ${app_name} ${wrapper}
"
    done
  done

  [ -n "$candidates" ] || return 1
  selected=$(printf '%s' "$candidates" | sort -r | head -n 1)
  app_version=$(printf '%s' "$selected" | awk '{ print $3 }')
  wrapper=$(printf '%s' "$selected" | cut -d' ' -f4-)
  resolved_wrapper=$(resolve_path "$wrapper")

  case "$resolved_wrapper" in
    "$resolved_root"/*) ;;
    *) fail "discord_erlpack wrapper resolves outside Discord directory: $resolved_wrapper" ;;
  esac

  printf '%s|%s|%s\n' "$app_version" "$resolved_wrapper" "$resolved_root"
}

installation_status() {
  channel_name="$1"
  root="$2"
  target=$(find_discord_target "$root") || return 1
  app_version=$(printf '%s' "$target" | cut -d'|' -f1)
  wrapper=$(printf '%s' "$target" | cut -d'|' -f2)
  resolved_root=$(printf '%s' "$target" | cut -d'|' -f3)
  status=$(wrapper_status "$wrapper")
  printf '%s|%s|%s|%s\n' "$channel_name" "$app_version" "$status" "$resolved_root|$wrapper"
}

detect_installations() {
  for channel_name in stable canary; do
    root=$(default_channel_directory "$channel_name")
    installation_status "$channel_name" "$root" 2>/dev/null || true
  done
}

backup_path() {
  channel_name="$1"
  app_version="$2"
  printf '%s\n' "$HOME/Library/Application Support/FakeMobileStatus/shell-patcher/backups/$channel_name/$app_version/discord_erlpack-index.js"
}

assert_discord_stopped() {
  channel_name="$1"
  [ "${FAKE_MOBILE_STATUS_SKIP_PROCESS_CHECK:-0}" = "1" ] && return
  case "$channel_name" in
    stable) process_name="Discord" ;;
    canary) process_name="Discord Canary" ;;
    *) fail "unsupported channel: $channel_name" ;;
  esac
  if pgrep -x "$process_name" >/dev/null 2>&1; then
    fail "Discord $channel_name is running; fully exit it before changing the patch"
  fi
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{ print tolower($1) }'
  else
    sha256sum "$1" | awk '{ print tolower($1) }'
  fi
}

write_verified_file() {
  destination="$1"
  source="$2"
  directory=$(dirname "$destination")
  mkdir -p "$directory"
  temporary="$directory/.shell-patcher-$$.tmp"
  cp "$source" "$temporary"
  expected=$(sha256_file "$temporary")
  mv "$temporary" "$destination"
  actual=$(sha256_file "$destination")
  [ "$actual" = "$expected" ] || fail "write verification failed: $destination"
}

write_verified_text() {
  destination="$1"
  directory=$(dirname "$destination")
  mkdir -p "$directory"
  temporary="$directory/.shell-patcher-$$.tmp"
  patched_wrapper > "$temporary"
  expected=$(sha256_file "$temporary")
  mv "$temporary" "$destination"
  actual=$(sha256_file "$destination")
  [ "$actual" = "$expected" ] || fail "write verification failed: $destination"
}

install_patch() {
  record="$1"
  channel_name=$(printf '%s' "$record" | cut -d'|' -f1)
  app_version=$(printf '%s' "$record" | cut -d'|' -f2)
  status=$(printf '%s' "$record" | cut -d'|' -f3)
  wrapper=$(printf '%s' "$record" | cut -d'|' -f5-)

  assert_discord_stopped "$channel_name"
  [ "$status" = "patched" ] && { echo "patch is already applied"; return; }
  if [ "$status" = "stale-patch" ]; then
    write_verified_text "$wrapper"
    echo "patch repaired"
    return
  fi
  [ "$status" = "official" ] || fail "refusing to overwrite unknown discord_erlpack wrapper: $wrapper"

  backup=$(backup_path "$channel_name" "$app_version")
  if [ -f "$backup" ]; then
    [ "$(wrapper_status "$backup")" = "official" ] || fail "existing backup is not official: $backup"
  else
    write_verified_file "$backup" "$wrapper"
  fi
  write_verified_text "$wrapper"
  echo "patch applied"
}

uninstall_patch() {
  record="$1"
  channel_name=$(printf '%s' "$record" | cut -d'|' -f1)
  app_version=$(printf '%s' "$record" | cut -d'|' -f2)
  status=$(printf '%s' "$record" | cut -d'|' -f3)
  wrapper=$(printf '%s' "$record" | cut -d'|' -f5-)

  assert_discord_stopped "$channel_name"
  [ "$status" = "official" ] && { echo "wrapper is already official"; return; }
  [ "$status" = "patched" ] || [ "$status" = "stale-patch" ] || fail "patched wrapper has changed; refusing to overwrite it: $wrapper"

  backup=$(backup_path "$channel_name" "$app_version")
  [ -f "$backup" ] || fail "official backup was not found: $backup"
  [ "$(wrapper_status "$backup")" = "official" ] || fail "backup is not an official discord_erlpack wrapper"
  write_verified_file "$wrapper" "$backup"
  echo "official wrapper restored"
}

show_status() {
  record="$1"
  channel_name=$(printf '%s' "$record" | cut -d'|' -f1)
  app_version=$(printf '%s' "$record" | cut -d'|' -f2)
  status=$(printf '%s' "$record" | cut -d'|' -f3)
  root=$(printf '%s' "$record" | cut -d'|' -f4)
  case "$channel_name" in
    stable) label="Discord Stable" ;;
    canary) label="Discord Canary" ;;
  esac
  printf '\n%s\n  Version: %s\n  Status:  %s\n  Path:    %s\n' "$label" "$app_version" "$status" "$root"
}

record_count() {
  printf '%s\n' "$1" | sed '/^$/d' | wc -l | tr -d ' '
}

record_at() {
  printf '%s\n' "$1" | sed '/^$/d' | sed -n "$2p"
}

select_record() {
  records="$1"
  requested_channel="$2"
  count=$(record_count "$records")
  [ "$count" -gt 0 ] || fail "no supported Discord installation was detected"
  if [ "$requested_channel" = "auto" ]; then
    record_at "$records" 1
    return
  fi
  printf '%s\n' "$records" | awk -F'|' -v channel="$requested_channel" '$1 == channel { print; exit }'
}

read_number_choice() {
  prompt="$1"
  labels="$2"
  count=$(record_count "$labels")
  printf '\n%s\n' "$prompt" >&2
  index=1
  printf '%s\n' "$labels" | sed '/^$/d' | while IFS= read -r label; do
    printf '  %s. %s\n' "$index" "$label" >&2
    index=$((index + 1))
  done
  while :; do
    printf 'Select: ' >&2
    IFS= read -r choice
    case "$choice" in
      *[!0-9]*|'') echo "Enter a number from 1 to $count." >&2 ;;
      *) [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ] && { echo "$choice"; return; }
         echo "Enter a number from 1 to $count." >&2 ;;
    esac
  done
}

read_arrow_choice() {
  prompt="$1"
  labels="$2"
  count=$(record_count "$labels")
  selected=1
  old_stty=$(stty -g)
  trap 'stty "$old_stty"; printf "\033[?25h"' EXIT HUP INT TERM
  stty raw -echo min 0 time 1
  printf '\033[?25l' >&2

  while :; do
    printf '\033[2J\033[H' >&2
    printf '%s\n' "$prompt" >&2
    printf 'Use Up/Down arrows and Enter. Esc cancels.\n' >&2
    index=1
    printf '%s\n' "$labels" | sed '/^$/d' | while IFS= read -r label; do
      if [ "$index" -eq "$selected" ]; then
        printf '  > %s\n' "$label" >&2
      else
        printf '    %s\n' "$label" >&2
      fi
      index=$((index + 1))
    done

    key=$(dd bs=1 count=1 2>/dev/null || true)
    [ -n "$key" ] || continue
    if [ "$key" = "$(printf '\033')" ]; then
      next=$(dd bs=1 count=2 2>/dev/null || true)
      case "$next" in
        '[A') selected=$((selected - 1)); [ "$selected" -lt 1 ] && selected=$count ;;
        '[B') selected=$((selected + 1)); [ "$selected" -gt "$count" ] && selected=1 ;;
        *) stty "$old_stty"; printf '\033[?25h\n' >&2; trap - EXIT HUP INT TERM; fail "cancelled" ;;
      esac
    elif [ "$key" = "$(printf '\015')" ] || [ "$key" = "$(printf '\012')" ]; then
      stty "$old_stty"
      printf '\033[?25h\n' >&2
      trap - EXIT HUP INT TERM
      echo "$selected"
      return
    fi
  done
}

read_menu_choice() {
  prompt="$1"
  labels="$2"
  if [ -t 0 ] && [ -t 1 ]; then
    read_arrow_choice "$prompt" "$labels"
  else
    if [ "$action" = "menu" ] && [ ! -t 0 ]; then
      fail "interactive menu requires a terminal; run the launcher directly or pass status/install/uninstall"
    fi
    read_number_choice "$prompt" "$labels"
  fi
}

run_patcher() {
  echo "Fake Mobile Status shell patcher"
  if [ -n "$discord_path" ]; then
    [ "$channel" != "auto" ] || fail "--discord-path requires --channel stable or --channel canary"
    records=$(installation_status "$channel" "$discord_path") || fail "discord_erlpack wrapper was not found under $discord_path"
  else
    records=$(detect_installations)
  fi
  [ "$(record_count "$records")" -gt 0 ] || fail "no supported Discord installation was detected"

  if [ "$action" = "menu" ]; then
    action_labels=$(printf 'Install\nUninstall\nView status\nQuit\n')
    action_choice=$(read_menu_choice "What would you like to do?" "$action_labels")
    case "$action_choice" in
      1) action="install" ;;
      2) action="uninstall" ;;
      3) action="status" ;;
      4) exit 0 ;;
    esac
    install_labels=$(printf '%s\n' "$records" | awk -F'|' '{ print $1 " - " $2 " [" $3 "]" }')
    install_choice=$(read_menu_choice "Select Discord installation" "$install_labels")
    selected=$(record_at "$records" "$install_choice")
  elif [ "$action" = "status" ] && [ "$channel" = "auto" ] && [ -z "$discord_path" ]; then
    printf '%s\n' "$records" | sed '/^$/d' | while IFS= read -r record; do
      show_status "$record"
    done
    return
  else
    selected=$(select_record "$records" "$channel")
    [ -n "$selected" ] || fail "Discord $channel was not detected"
  fi

  case "$action" in
    status) show_status "$selected" ;;
    install)
      result=$(install_patch "$selected")
      selected_channel=$(printf '%s' "$selected" | cut -d'|' -f1)
      printf '\nSuccess: %s on Discord %s\n' "$result" "$selected_channel"
      ;;
    uninstall)
      result=$(uninstall_patch "$selected")
      selected_channel=$(printf '%s' "$selected" | cut -d'|' -f1)
      printf '\nSuccess: %s on Discord %s\n' "$result" "$selected_channel"
      ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    status|install|uninstall|menu) action="$1"; shift ;;
    --action) action="${2:-}"; shift 2 ;;
    --channel) channel="${2:-}"; shift 2 ;;
    --discord-path) discord_path="${2:-}"; shift 2 ;;
    --no-run) no_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; fail "unknown argument: $1" ;;
  esac
done

case "$action" in menu|status|install|uninstall) ;; *) fail "unsupported action: $action" ;; esac
case "$channel" in auto|stable|canary) ;; *) fail "unsupported channel: $channel" ;; esac

[ "$no_run" -eq 1 ] || run_patcher
