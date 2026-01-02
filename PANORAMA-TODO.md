# Panorama Mode - Future Improvements

## Overview
Panorama mode splits one shell (one PTY) across two side-by-side panes:
- LEFT (SLAVE): Shows rows 0 to N-1 (overflow/history)
- RIGHT (MASTER): Shows rows N to 2N-1 (active cursor area)

## Issues to Fix

### 1. Copy Mode (prefix [) - NOT WORKING
**Problem**: Copy mode clones the wrong screen for panorama panes.

**Root Cause** (window-copy.c:438):
- `window_copy_init()` clones `&wp->base` (the pane's own screen)
- For SLAVE pane: `wp->base` is empty/wrong - all content is in MASTER's screen
- Result: Entering copy mode shows blank or wrong content

**Fix Required**:
```c
// In window_copy_init(), detect panorama and use correct screen:
if (wp->panorama_role == PANORAMA_SLAVE && wp->panorama_sibling != NULL) {
    base = &wp->panorama_sibling->base;  // Use MASTER's screen
    // Set scroll offset to show rows 0 to slave_sy
}
else if (wp->panorama_role == PANORAMA_MASTER && wp->panorama_sibling != NULL) {
    base = &wp->base;  // Own screen
    // Set scroll offset to show rows slave_sy to combined_sy
}
```

**Files to modify**:
- window-copy.c: `window_copy_init()`, `window_copy_resize()`, scroll functions

---

### 2. Cursor Jumping to Left + Prints Left Behind
**Problem**: Cursor sometimes appears on left pane with old content artifacts.

**Root Cause**:
- Race condition: `panorama_row_offset` updated AFTER screen resize
- Old content not cleared when screen buffer expands
- Rows beyond old size contain uninitialized data

**Fix Required** (window.c:1152-1166):
```c
if (wp->panorama_role == PANORAMA_MASTER && wp->panorama_sibling != NULL) {
    u_int combined_sy = sy + wp->panorama_sibling->sy;

    /* ATOMIC: Update offset BEFORE resize to prevent race */
    wp->panorama_sibling->panorama_row_offset = sy;

    /* Resize screen */
    screen_resize(&wp->base, sx, combined_sy, ...);

    /* Force FULL redraw of BOTH panes */
    wp->flags |= PANE_REDRAW;
    wp->panorama_sibling->flags |= PANE_REDRAW;
}
```

**Files to modify**:
- window.c: `window_pane_resize()`
- screen-redraw.c: Add TTY sync barrier during panorama resize

---

### 3. Artifacts When Resizing Right Pane
**Problem**: Resizing master pane leaves visual artifacts.

**Root Cause**:
- Screen buffer grows but new rows aren't cleared
- TTY not properly flushed between resize and redraw
- No synchronization between pane resize and screen buffer resize

**Fix Required**:
1. Clear new rows when screen buffer expands
2. Add `tty_sync_start()`/`tty_sync_end()` around panorama resize
3. Force full redraw after any panorama resize

**Files to modify**:
- screen.c: `screen_resize()` - clear new rows for panorama
- window.c: `window_pane_resize()` - add TTY sync
- screen-redraw.c: Ensure atomic redraw for panorama pairs

---

## Implementation Order

### Phase 1: Fix Resize Artifacts (Easiest)
1. Update `window_pane_resize()` to set offset BEFORE resize
2. Add `PANE_REDRAW` flag to both panes after any panorama resize
3. Clear new rows in screen buffer when expanding

### Phase 2: Fix Copy Mode (Medium)
1. Detect panorama in `window_copy_init()`
2. Clone from MASTER's screen for both panes
3. Set appropriate scroll offset based on which pane entered copy mode
4. Add boundary checks to prevent scrolling past pane's visible region

### Phase 3: Scroll Synchronization (Advanced)
1. When scrolling in copy mode, optionally sync both panes
2. Allow seamless scroll from slave through to master region
3. Consider unified copy mode view across both panes

---

## Key Files

| File | Purpose |
|------|---------|
| window-copy.c | Copy mode implementation |
| window.c | Pane resize, panorama sibling links |
| screen-redraw.c | Draws pane content with panorama offset |
| screen.c | Screen buffer management |
| tty.c | Terminal output, sync barriers |

---

## Testing Commands
```bash
# Basic panorama
./tmux new-session \; split-window -W

# Test copy mode
# Press prefix [ in either pane

# Test resize
# Drag pane border or use resize-pane command

# Test rapid output
seq 1 1000
```
