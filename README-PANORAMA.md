# tmux Panorama Mode

Panorama mode is an experimental feature that splits a single shell (one PTY) across two side-by-side panes, effectively doubling your visible terminal history.

## How It Works

```
+------------------+------------------+
|   LEFT (SLAVE)   |  RIGHT (MASTER)  |
|                  |                  |
| Shows rows 0-N   | Shows rows N-2N  |
| (overflow/history)|  (active cursor) |
|                  |                  |
| Display only     | Has the PTY      |
+------------------+------------------+
```

- **One PTY, Two Panes**: The shell sees a terminal with 2x the height (combined height of both panes)
- **LEFT pane (slave)**: Shows the top half of the combined screen (overflow/history)
- **RIGHT pane (master)**: Shows the bottom half where the cursor and active input are

## Usage

```bash
# Create a panorama split
./tmux new-session \; split-window -W

# Or from within tmux
# Press prefix, then: split-window -W
```

## Known Issues

### Issue 1: Cursor Jumps to Left Pane (Shell)

During normal shell use, the cursor (green block) unexpectedly appears on the left (slave) pane instead of staying on the right (master) pane.

**Expected**: Cursor should always be on the RIGHT pane for shell use since the prompt is at the bottom of the combined screen.

**Actual**: Cursor sometimes appears on the LEFT pane.

### Issue 2: Resize Line Artifacts

After resizing the terminal window or dragging the pane border, green vertical line artifacts appear on the screen and don't clear properly.

**Expected**: Clean redraw after resize with no visual artifacts.

**Actual**: Green vertical lines remain visible, especially on the left side of the left pane.

### Issue 3: Neovim Cursor Invisible on Left Pane

When using full-screen applications like neovim, and the cursor moves to the top half of the screen (which should display on the left pane), the cursor becomes invisible.

**Expected**: When neovim's cursor is in the top half of the combined screen, it should be visible on the LEFT pane.

**Actual**: Cursor is invisible/not rendered on the left pane.

### Issue 4: Resize Text Reflow

After resizing, text doesn't wrap/reflow correctly to fit the new pane dimensions. This is often combined with the line artifacts from Issue 2.

**Expected**: Text should reflow properly to the new width after resize.

**Actual**: Text doesn't wrap to new dimensions correctly, leaving display corruption.

## Key Source Files

| File | Purpose |
|------|---------|
| `window.c` | Pane resize, panorama sibling links, `window_pane_create_panorama_slave()` |
| `screen-redraw.c` | Draws pane content with panorama row offset |
| `server-client.c` | Cursor positioning logic |
| `tty.c` | Terminal output, line drawing |
| `cmd-split-window.c` | The `-W` flag implementation |

## Architecture Notes

- Master pane has `panorama_role = PANORAMA_MASTER` and owns the PTY
- Slave pane has `panorama_role = PANORAMA_SLAVE` and `fd = -1` (no PTY)
- Both panes point to each other via `panorama_sibling`
- Slave uses master's screen buffer for rendering with `panorama_row_offset = 0`
- Master uses its own screen buffer starting at `panorama_row_offset = slave_height`
