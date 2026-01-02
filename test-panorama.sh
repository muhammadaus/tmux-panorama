#!/bin/bash
# Test script for panorama mode
# Run: chmod +x test-panorama.sh && ./test-panorama.sh

TMUX="./tmux"
SOCKET="/tmp/panorama-test-$$"

echo "=== Panorama Test Script ==="
echo "Socket: $SOCKET"
echo ""

# Kill any existing
pkill -f tmux 2>/dev/null
sleep 1

# Start session
echo "1. Starting tmux session..."
$TMUX -S "$SOCKET" -f/dev/null new-session -d -x60 -y12

echo "2. Creating panorama split (-W)..."
$TMUX -S "$SOCKET" split-window -W
sleep 1

echo "3. Pane layout:"
$TMUX -S "$SOCKET" list-panes -F '   #{pane_id}: #{pane_panorama_role} at x=#{pane_left}'
echo ""

echo "4. Generating output (seq 1 100)..."
$TMUX -S "$SOCKET" send-keys 'seq 1 100' Enter
sleep 2

echo "5. Sending 30x Ctrl+C..."
for i in $(seq 1 30); do
    $TMUX -S "$SOCKET" send-keys C-c
    sleep 0.1
done
sleep 1

echo ""
echo "=== CAPTURE ==="
echo "LEFT (slave - should be overflow):"
$TMUX -S "$SOCKET" capture-pane -t %1 -p | tail -12
echo ""
echo "RIGHT (master - should have cursor $):"
$TMUX -S "$SOCKET" capture-pane -t %0 -p | tail -12
echo ""

echo "=== ATTACH TO SEE VISUALLY ==="
echo "Press Enter to attach (Ctrl+B D to detach)..."
read

$TMUX -S "$SOCKET" attach

$TMUX -S "$SOCKET" kill-server 2>/dev/null
echo "Done."
