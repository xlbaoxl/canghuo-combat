#!/usr/bin/env bash
set -euo pipefail
engine="${1:?Pass the Godot 4.7.2 executable}"
platform="${2:-Linux}"
case "$platform" in Linux|Windows) ;; *) echo "Platform must be Linux or Windows" >&2; exit 2;; esac
module="$(cd "$(dirname "$0")/.." && pwd)"
out="${3:-$module/builds}"
mkdir -p "$out"; out="$(cd "$out" && pwd)"
export UPGRADE_VERIFY_DIR="$out/verification"
"$engine" --headless --path "$module/project" --editor --import --quit
for test in test_upgrade test_presentation_upgrade threaded_upgrade; do
  "$engine" --headless --path "$module/project" --script "res://tests/$test.gd"
done
name=CanghuoTraining.x86_64
[[ "$platform" == Windows ]] && name=CanghuoTraining.exe
"$engine" --headless --path "$module/project" --export-release "Training $platform" "$out/$name"
sha256sum "$out/$name"
