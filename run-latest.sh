#!/bin/sh
set -eu

repository="uta-a/discord-erlpack-mobile-patcher"
user_agent="fake-mobile-status-installer"
script_name="patcher.sh"
checksum_name="$script_name.sha256"
release_base_url="https://github.com/$repository/releases/latest/download"

case "$(uname -s)" in
  Darwin) ;;
  *) echo "Only macOS is supported by this script." >&2; exit 1 ;;
esac

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/fake-mobile-status.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

script_path="$temporary_directory/$script_name"
checksum_path="$temporary_directory/$checksum_name"

echo "Checking the latest shell patcher release..."
curl --fail --location --silent --show-error --user-agent "$user_agent" \
  "$release_base_url/$script_name" --output "$script_path"
curl --fail --location --silent --show-error --user-agent "$user_agent" \
  "$release_base_url/$checksum_name" --output "$checksum_path"

expected_hash="$(awk 'NR == 1 { print tolower($1) }' "$checksum_path")"
case "$expected_hash" in
  *[!0-9a-f]*|"") echo "Invalid SHA-256 file." >&2; exit 1 ;;
esac
if [ "${#expected_hash}" -ne 64 ]; then
  echo "Invalid SHA-256 length." >&2
  exit 1
fi

actual_hash="$(shasum -a 256 "$script_path" | awk '{ print tolower($1) }')"
if [ "$actual_hash" != "$expected_hash" ]; then
  echo "SHA-256 verification failed. The downloaded script will not be executed." >&2
  exit 1
fi

echo "Verified latest release. Starting shell patcher..."
sh "$script_path" "$@"
