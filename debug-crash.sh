#!/bin/bash
# Debug crash with lldb

cd "$(dirname "$0")"

pkill -f tmux 2>/dev/null
sleep 1

echo "=== RUNNING TMUX UNDER LLDB ==="
echo "When tmux starts, press Ctrl-C repeatedly until it crashes."
echo "LLDB will catch the crash and show the backtrace."
echo ""
echo "Press Enter to start..."
read

# Run under lldb
lldb -o "run -vvvv new-session -x178 -y40 \; split-window -W" -o "bt" -- ./tmux
