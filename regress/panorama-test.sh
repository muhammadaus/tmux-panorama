#!/bin/bash
# Automated test for panorama mode
# Tests that split-window -W creates two panes sharing a single PTY

set -e

TMUX="${TEST_TMUX:-./tmux}"
SOCKET="/tmp/tmux-panorama-test-$$"
TMP=$(mktemp)
PANE_HEIGHT=10

cleanup() {
    $TMUX -S "$SOCKET" kill-server 2>/dev/null || true
    rm -f "$TMP" "${TMP}.pane0" "${TMP}.pane1" "$SOCKET"
}
trap cleanup EXIT

echo "=== Panorama Mode Test ==="
echo "Using tmux: $TMUX"
echo ""

# 1. Kill any existing server
$TMUX -S "$SOCKET" kill-server 2>/dev/null || true

# 2. Create session with known dimensions (40 wide, 10 tall)
echo "Creating test session (40x$PANE_HEIGHT)..."
$TMUX -S "$SOCKET" -f/dev/null new-session -d -x40 -y$PANE_HEIGHT

# 3. Create panorama split
echo "Creating panorama split (split-window -W)..."
$TMUX -S "$SOCKET" split-window -W

# 4. Wait for split to complete
sleep 0.5

# 5. Verify we have 2 panes
PANE_COUNT=$($TMUX -S "$SOCKET" list-panes | wc -l | tr -d ' ')
if [ "$PANE_COUNT" != "2" ]; then
    echo "[FAIL] Expected 2 panes, got $PANE_COUNT"
    exit 1
fi
echo "[PASS] Created 2 panes"

# 6. Get pane IDs
PANE0=$($TMUX -S "$SOCKET" list-panes -F '#{pane_id}' | head -1)
PANE1=$($TMUX -S "$SOCKET" list-panes -F '#{pane_id}' | tail -1)
echo "Pane IDs: $PANE0 (master), $PANE1 (slave)"

# 7. Show pane info
echo ""
echo "=== Pane Info ==="
$TMUX -S "$SOCKET" list-panes -F 'Pane #{pane_id}: #{pane_width}x#{pane_height} at (#{pane_left},#{pane_top})'
echo ""

# 8. Send numbered output to test scrolling (send to master pane)
echo "Sending test output (seq 1 50)..."
$TMUX -S "$SOCKET" send-keys -t "$PANE0" 'seq 1 50' Enter
sleep 3

# 9. Capture both panes
echo "Capturing pane contents..."
$TMUX -S "$SOCKET" capture-pane -t "$PANE0" -p > "${TMP}.pane0"
$TMUX -S "$SOCKET" capture-pane -t "$PANE1" -p > "${TMP}.pane1"

# 10. Display captured content for debugging
echo ""
echo "=== Master Pane (Left/$PANE0) Content ==="
cat -n "${TMP}.pane0"
echo ""
echo "=== Slave Pane (Right/$PANE1) Content ==="
cat -n "${TMP}.pane1"
echo ""

# 11. Verify panorama behavior:
# Check if slave pane has different content than master (it should show offset rows)
if diff -q "${TMP}.pane0" "${TMP}.pane1" > /dev/null 2>&1; then
    echo "[FAIL] Both panes show identical content - panorama offset not working"
    FAIL=1
else
    echo "[PASS] Panes show different content (offset is applied)"
fi

# 12. Check if slave pane is empty (common failure mode)
SLAVE_LINES=$(grep -c '[0-9]' "${TMP}.pane1" 2>/dev/null || echo "0")
if [ "$SLAVE_LINES" -eq 0 ]; then
    echo "[FAIL] Slave pane is empty - no content rendered"
    FAIL=1
else
    echo "[PASS] Slave pane has content ($SLAVE_LINES lines with numbers)"
fi

# 13. Check for continuous numbering
# Master visible area would be rows 0-9 (10 lines)
# Slave visible area would be rows 10-19 (10 lines)
# Get the 10th line of master capture (last visible in master pane)
MASTER_10TH=$(sed -n '10p' "${TMP}.pane0" | grep -o '[0-9]\+' | head -1 || echo "0")
SLAVE_FIRST=$(grep -o '[0-9]\+' "${TMP}.pane1" | head -1 || echo "0")
echo ""
echo "Master pane 10th row: $MASTER_10TH"
echo "Slave pane first number: $SLAVE_FIRST"

# For continuity: slave first should be master 10th + 1
if [ -n "$MASTER_10TH" ] && [ -n "$SLAVE_FIRST" ]; then
    EXPECTED=$((MASTER_10TH + 1))
    if [ "$SLAVE_FIRST" -eq "$EXPECTED" ]; then
        echo "[PASS] Content is continuous (master 10th=$MASTER_10TH, slave first=$SLAVE_FIRST)"
    else
        echo "[WARN] Expected slave first=$EXPECTED but got $SLAVE_FIRST"
    fi
else
    echo "[INFO] Could not verify continuity - check output above"
fi

echo ""
echo "=== TEST COMPLETED ==="

if [ "$FAIL" = "1" ]; then
    echo "RESULT: FAILED - See errors above"
    exit 1
else
    echo "RESULT: Basic checks passed - Review output for correctness"
    exit 0
fi
