#!/bin/bash
# Debug the SERVER process (where crash happens)

cd "$(dirname "$0")"

pkill -f tmux 2>/dev/null
sleep 1

echo "=== DEBUGGING TMUX SERVER ==="
echo ""
echo "Step 1: Starting tmux server under lldb..."
echo ""

# Start server in background under lldb, write pid
lldb -o "process launch --stop-at-entry" -o "continue" -- ./tmux -S /tmp/debug-socket start-server &
LLDB_PID=$!
sleep 2

echo "Step 2: Creating panorama session..."
./tmux -S /tmp/debug-socket new-session -d -x178 -y40
./tmux -S /tmp/debug-socket split-window -W
sleep 1

echo "Step 3: Attaching to session..."
echo "Press Ctrl-C repeatedly until crash. Then check lldb window."
echo ""

./tmux -S /tmp/debug-socket attach

echo ""
echo "Session ended. Check lldb output above for backtrace."
echo ""

# Kill lldb
kill $LLDB_PID 2>/dev/null
