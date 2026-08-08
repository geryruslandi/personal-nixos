#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

sudo nixos-rebuild switch --flake . --impure --accept-flake-config
