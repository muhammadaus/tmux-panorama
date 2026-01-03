#!/bin/bash
# Run this script to capture the crash

cd "$(dirname "$0")"

echo "=== CRASH CAPTURE SCRIPT ==="
echo ""

# Kill any existing
pkill -f tmux 2>/dev/null
sleep 1

# Make sure we have latest build
echo "Building..."
make -j4 2>&1 | tail -3

echo ""
echo "Starting tmux with debug logging..."
echo "Log will be saved to: /tmp/tmux-crash.log"
echo ""

# Run in foreground with verbose logging
./tmux -vvvv new-session -x80 -y40 2>/tmp/tmux-crash.log \; split-window -W

echo ""
echo "=== TMUX EXITED ==="
echo ""
echo "Last 100 lines of debug log:"
echo "=============================="
tail -100 /tmp/tmux-crash.log
echo ""
echo "=============================="
echo "Full log saved to: /tmp/tmux-crash.log"
