#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if tmux has-session -t nixos 2>/dev/null; then
    tmux attach-session -t nixos
    exit 0
fi

tmux new-session -d -s nixos -c "$(pwd)" -n ide
tmux send-keys -t nixos:ide "nvim" Enter

tmux new-window -t nixos -c "$(pwd)" -n opencode
tmux send-keys -t nixos:opencode "opencode" Enter

tmux select-window -t nixos:ide
tmux attach-session -t nixos
