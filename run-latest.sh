#!/bin/sh
set -eu

repository="uta-a/discord-erlpack-mobile-patcher"
releases_api="https://api.github.com/repos/$repository/releases?per_page=30"
user_agent="fake-mobile-status-installer"

case "$(uname -s)" in
  Darwin) ;;
  *) echo "Only macOS is supported by this script." >&2; exit 1 ;;
esac

case "$(uname -m)" in
  arm64) binary_name="erlpack-patcher-macos-arm64" ;;
  x86_64) binary_name="erlpack-patcher-macos-x64" ;;
  *) echo "Unsupported macOS architecture: $(uname -m)" >&2; exit 1 ;;
esac

checksum_name="$binary_name.sha256"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/fake-mobile-status.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

release_json="$temporary_directory/release.json"
binary_path="$temporary_directory/$binary_name"
checksum_path="$temporary_directory/$checksum_name"

echo "Checking the latest Fake Mobile Status release..."
curl --fail --location --silent --show-error \
  --header "Accept: application/vnd.github+json" \
  --header "X-GitHub-Api-Version: 2022-11-28" \
  --user-agent "$user_agent" \
  "$releases_api" > "$release_json"

asset_url() {
  asset_name="$1"
  sed -n 's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/p' "$release_json" |
    grep "/$asset_name$" |
    head -n 1
}

binary_url="$(asset_url "$binary_name")"
checksum_url="$(asset_url "$checksum_name")"
if [ -z "$binary_url" ] || [ -z "$checksum_url" ]; then
  echo "Required release assets were not found." >&2
  exit 1
fi

curl --fail --location --silent --show-error --user-agent "$user_agent" \
  "$binary_url" --output "$binary_path"
curl --fail --location --silent --show-error --user-agent "$user_agent" \
  "$checksum_url" --output "$checksum_path"

expected_hash="$(awk 'NR == 1 { print tolower($1) }' "$checksum_path")"
case "$expected_hash" in
  *[!0-9a-f]*|"") echo "Invalid SHA-256 file." >&2; exit 1 ;;
esac
if [ "${#expected_hash}" -ne 64 ]; then
  echo "Invalid SHA-256 length." >&2
  exit 1
fi

actual_hash="$(shasum -a 256 "$binary_path" | awk '{ print tolower($1) }')"
if [ "$actual_hash" != "$expected_hash" ]; then
  echo "SHA-256 verification failed. The downloaded file will not be executed." >&2
  exit 1
fi

chmod +x "$binary_path"
echo "Verified latest release. Starting installer..."
"$binary_path" "$@"
