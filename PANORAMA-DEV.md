# Panorama Mode - Development Documentation

## Overview

Panorama mode splits a single shell (one PTY) across two side-by-side panes, effectively doubling your visible terminal height.

```
+------------------+------------------+
|   LEFT (SLAVE)   |  RIGHT (MASTER)  |
|                  |                  |
| Shows rows 0-N   | Shows rows N-2N  |
| (top half)       | (bottom half)    |
|                  |                  |
| Display only     | Has the PTY      |
+------------------+------------------+
```

## Current Status

### Working
- Basic panorama split (`split-window -W`)
- Shell output displays across both panes
- Neovim cursor visible on left pane (alternate screen mode)
- Copy mode works in fullscreen

### Known Issues
- Issue 1: Cursor sometimes jumps to left pane during shell use
- Issue 2: Green line artifacts after resize
- Issue 4: Text reflow broken on resize

## Debug Logging

Run with verbose logging to diagnose issues:

```bash
# Start with debug output (logs go to tmux-server-*.log)
./tmux -vvvv new-session \; split-window -W

# View logs in another terminal
tail -f tmux-server-*.log | grep PANORAMA
```

### Log Messages

| Prefix | Location | Description |
|--------|----------|-------------|
| `PANORAMA: created split` | cmd-split-window.c | When panorama panes are created |
| `PANORAMA: master pane` | cmd-split-window.c | Master pane and screen dimensions |
| `PANORAMA: slave pane` | cmd-split-window.c | Slave pane dimensions and offset |
| `PANORAMA copy-mode:` | window-copy.c | Copy mode screen/backing dimensions |

## Architecture

### Pane Roles
- **PANORAMA_MASTER**: Right pane, owns the PTY (`fd != -1`), screen has combined height
- **PANORAMA_SLAVE**: Left pane, display-only (`fd = -1`), renders from master's screen
- **PANORAMA_NONE**: Normal pane (not in panorama mode)

### Key Fields (struct window_pane)
```c
int panorama_role;           // PANORAMA_NONE, PANORAMA_MASTER, or PANORAMA_SLAVE
struct window_pane *panorama_sibling;  // Pointer to sibling pane
u_int panorama_row_offset;   // Row offset for rendering (slave's visible height)
```

### Screen Dimensions
- Master's `wp->base`: Combined height (2 * pane_height)
- Slave's `wp->base`: Pane height (just for initialization, not used for content)
- PTY size: `ws_row = combined_height`, `ws_col = pane_width`

## Key Files

| File | Functions |
|------|-----------|
| `cmd-split-window.c` | `-W` flag, panorama creation |
| `window.c` | `window_pane_create_panorama_slave()`, resize handling |
| `window-copy.c` | Copy mode with panorama support |
| `screen-redraw.c` | Renders slave from master's screen |
| `server-client.c` | Cursor positioning logic |
| `input-keys.c` | Routes slave input to master |

## Testing

```bash
# Basic panorama
./tmux new-session \; split-window -W

# Generate output
seq 1 100

# Test copy mode
# Press prefix [

# Test neovim
nvim
```

## Branches

- `master`: Upstream tmux
- `panorama-mode`: Main panorama implementation
- `panorama-dev`: Development/experimental changes
