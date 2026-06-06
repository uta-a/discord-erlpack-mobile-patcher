#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
patcher="$script_dir/patcher.sh"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/discord-erlpack-patcher-test.XXXXXX")
old_home=${HOME:-}
passed=0

cleanup() {
  HOME=$old_home
  export HOME
  rm -rf "$test_root"
}
trap cleanup EXIT HUP INT TERM

export HOME="$test_root/home"
export FAKE_MOBILE_STATUS_SKIP_PROCESS_CHECK=1
mkdir -p "$HOME"

official='"use strict";
module.exports = require('\''./discord_erlpack.node'\'');'

assert_equal() {
  actual="$1"
  expected="$2"
  message="$3"
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: $message. Expected '$expected', got '$actual'." >&2
    exit 1
  fi
}

assert_contains() {
  haystack="$1"
  needle="$2"
  message="$3"
  case "$haystack" in
    *"$needle"*) ;;
    *) echo "FAIL: $message. Missing '$needle'." >&2; exit 1 ;;
  esac
}

assert_throws() {
  if "$@" >/tmp/discord-erlpack-patcher-test.out 2>&1; then
    echo "FAIL: expected command to fail: $*" >&2
    exit 1
  fi
}

new_test_discord() {
  discord_root="$1"
  discord_version="${2:-app-1.0.100}"
  wrapper_content="${3:-$official}"
  wrapper_dir="$discord_root/$discord_version/modules/discord_erlpack-1/discord_erlpack"
  mkdir -p "$wrapper_dir"
  printf '%s\n' "$wrapper_content" > "$wrapper_dir/index.js"
}

invoke_test() {
  name="$1"
  shift
  "$@"
  passed=$((passed + 1))
  echo "PASS: $name"
}

test_selects_newest_complete_version() {
  root="$test_root/newest"
  new_test_discord "$root" "app-1.0.99"
  new_test_discord "$root" "app-1.0.100"
  mkdir -p "$root/app-1.0.101/modules"
  output=$(sh "$patcher" status --channel stable --discord-path "$root")
  assert_contains "$output" "Version: app-1.0.100" "wrong app version"
}

test_installs_and_uninstalls() {
  root="$test_root/roundtrip"
  new_test_discord "$root"
  output=$(sh "$patcher" install --channel stable --discord-path "$root")
  assert_contains "$output" "Success: patch applied" "install result"
  output=$(sh "$patcher" status --channel stable --discord-path "$root")
  assert_contains "$output" "Status:  patched" "installed status"
  output=$(sh "$patcher" uninstall --channel stable --discord-path "$root")
  assert_contains "$output" "Success: official wrapper restored" "uninstall result"
  output=$(sh "$patcher" status --channel stable --discord-path "$root")
  assert_contains "$output" "Status:  official" "restored status"
}

test_refuses_unknown_wrapper() {
  root="$test_root/unknown"
  new_test_discord "$root" "app-1.0.100" "module.exports = thirdParty;"
  assert_throws sh "$patcher" install --channel stable --discord-path "$root"
  content=$(cat "$root/app-1.0.100/modules/discord_erlpack-1/discord_erlpack/index.js")
  assert_equal "$content" "module.exports = thirdParty;" "unknown wrapper changed"
}

test_detects_stable_and_canary() {
  support="$HOME/Library/Application Support"
  new_test_discord "$support/discord"
  new_test_discord "$support/discordcanary" "app-1.0.200"
  output=$(sh "$patcher" status)
  assert_contains "$output" "Discord Stable" "stable not detected"
  assert_contains "$output" "Discord Canary" "canary not detected"
}

test_fails_with_no_detected_discord() {
  empty_home="$test_root/empty-home"
  mkdir -p "$empty_home"
  HOME="$empty_home" assert_throws sh "$patcher" status
}

test_refuses_wrapper_outside_root() {
  root="$test_root/escape-root"
  outside="$test_root/outside"
  new_test_discord "$outside"
  mkdir -p "$root/app-1.0.100/modules"
  link_path="$root/app-1.0.100/modules/discord_erlpack-1"
  if ! ln -s "$outside/app-1.0.100/modules/discord_erlpack-1" "$link_path" 2>/dev/null || [ ! -L "$link_path" ]; then
    echo "SKIP: refuses wrapper outside root (symlink unavailable)"
    return
  fi
  assert_throws sh "$patcher" status --channel stable --discord-path "$root"
}

invoke_test "selects newest complete Discord version" test_selects_newest_complete_version
invoke_test "installs and uninstalls" test_installs_and_uninstalls
invoke_test "refuses unknown wrapper" test_refuses_unknown_wrapper
invoke_test "detects Stable and Canary" test_detects_stable_and_canary
invoke_test "fails with no detected Discord" test_fails_with_no_detected_discord
invoke_test "refuses wrapper outside root" test_refuses_wrapper_outside_root

echo "shell tests passed: $passed"
