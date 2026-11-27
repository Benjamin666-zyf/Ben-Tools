#!/bin/bash
set -euo pipefail

desktop_dir="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$desktop_dir/.." && pwd)"
output="${1:-$repo/ben-pake/output}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
stage="$(mktemp -d "${TMPDIR:-/tmp}/ben-pake-package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT

cd "$repo"
pnpm install --frozen-lockfile
pnpm run cli:build
pnpm pack --pack-destination "$stage"

app="$stage/Ben-Pake.app"
engine="$app/Contents/Resources/pake"
mkdir -p "$app/Contents/MacOS" "$engine"
tar -xzf "$stage/"pake-cli-*.tgz --strip-components=1 -C "$engine"
cp "$repo/package.json" "$repo/pnpm-lock.yaml" "$repo/.npmrc" "$repo/rust-toolchain.toml" "$engine/"
(cd "$engine" && pnpm install --prod --frozen-lockfile)
cp "$desktop_dir/Info.plist" "$app/Contents/"
swiftc -target arm64-apple-macos14.0 -swift-version 6 -parse-as-library -O \
  "$desktop_dir/BenPake.swift" "$desktop_dir/Builder.swift" -o "$app/Contents/MacOS/Ben-Pake"
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
/usr/bin/env node "$engine/dist/cli.js" --version

hdiutil create -volname Ben-Pake -srcfolder "$app" -format UDZO "$stage/Ben-Pake.dmg"
mv -f "$stage/Ben-Pake.dmg" "$output/Ben-Pake.dmg"
if [[ -d "$output/Ben-Pake.app" ]]; then
  mv "$output/Ben-Pake.app" "$stage/previous.app"
fi
mv "$app" "$output/Ben-Pake.app"
