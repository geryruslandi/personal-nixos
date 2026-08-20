#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Make the flake see the gitignored secrets.nix during evaluation.
git add --intent-to-add secrets.nix -f
# Unstage it afterward (success or failure) so `git status` stays clean.
cleanup() { git reset -- secrets.nix >/dev/null 2>&1 || true; }
trap cleanup EXIT

sudo nixos-rebuild switch --flake . --impure --accept-flake-config
