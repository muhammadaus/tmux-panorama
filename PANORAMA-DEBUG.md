# Tmux Panorama Mode - Debug Guide

## What is Panorama Mode?

Two panes side-by-side sharing ONE shell. The shell thinks it has 20 rows, but each pane shows 10:

```
┌─────────── LEFT (rows 0-9) ───────────┬─────────── RIGHT (rows 10-19) ─────────┐
│ SLAVE: Shows older output             │ MASTER: Shows cursor/prompt            │
└───────────────────────────────────────┴────────────────────────────────────────┘
```

**IMPORTANT**: At STARTUP, cursor is at row 0-9 (LEFT). Run `seq 1 25` to push cursor to RIGHT.

---

## Quick Test

```bash
pkill -f tmux           # Kill cached server
make -j4                # Rebuild
./tmux -S /tmp/test new-session -x40 -y10 \; split-window -W
seq 1 25                # Generate output to move cursor to RIGHT
```

---

## Actual C Code References

### 1. Creating Panorama Split: `cmd-split-window.c`

**Line 121-122** - Put slave on LEFT side:
```c
if (args_has(args, 'W'))
    flags |= SPAWN_BEFORE;
```

**Line 145** - Create the slave pane:
```c
new_wp = window_pane_create_panorama_slave(w, wp, new_sx, new_sy);
```

**Line 152** - Insert slave BEFORE master (left side):
```c
TAILQ_INSERT_BEFORE(wp, new_wp, entry);
```

**Line 164-173** - Resize PTY to combined height:
```c
u_int combined_sy = panorama_original_sy * 2;  // 10 * 2 = 20 rows
ws.ws_row = combined_sy;
ioctl(wp->fd, TIOCSWINSZ, &ws);      // Tell shell: "you have 20 rows"
screen_resize(&wp->base, wp->sx, combined_sy, 0);  // Resize buffer
```

---

### 2. Visual Rendering: `screen-redraw.c`

**Line 907-910** - Slave (LEFT) renders rows 0-9:
```c
if (wp->panorama_role == PANORAMA_SLAVE && wp->panorama_sibling != NULL) {
    s = &wp->panorama_sibling->base;  // Use MASTER's screen buffer
    panorama_row_offset = 0;          // Start from row 0
}
```

**Line 911-918** - Master (RIGHT) renders rows 10-19:
```c
else if (wp->panorama_role == PANORAMA_MASTER && wp->panorama_sibling != NULL) {
    s = &wp->base;                    // Use own screen buffer
    panorama_row_offset = wp->panorama_sibling->sy;  // Start from row 10
    // Bounds check - abort if offset exceeds screen
    if (panorama_row_offset + wp->sy > screen_size_y(s)) {
        log_debug("%s: panorama master bounds exceeded", __func__);
        return;
    }
}
```

**Line 967** - Apply offset when drawing each line:
```c
tty_draw_line(tty, s, i, j + panorama_row_offset, width, x, y, &defaults, palette);
//                        ^^^^^^^^^^^^^^^^^^^^^^^
//                        This shifts which row we read from the screen buffer
```

---

### 3. Cursor Position: `server-client.c`

**Line 2968-2976** - Adjust cursor Y for panorama master:
```c
cursor_cy = s->cy;  // Raw cursor position (0-19 in combined screen)

if (wp->panorama_role == PANORAMA_MASTER && wp->panorama_sibling != NULL) {
    pano_off = wp->panorama_sibling->sy;  // = 10 (slave height)

    // Is cursor in master's visible range (rows 10-19)?
    if (s->cy >= pano_off && s->cy < pano_off + wp->sy)
        cursor_cy = s->cy - pano_off;     // Adjust: row 15 becomes row 5
    else
        cursor_cy = wp->sy;               // Out of range - hide cursor
}
```

**Line 2978-2986** - Only show cursor if in visible area:
```c
if (wp->xoff + s->cx >= ox && wp->xoff + s->cx <= ox + sx &&
    wp->yoff + cursor_cy >= oy && wp->yoff + cursor_cy < oy + sy) {
    cursor = 1;
    cx = wp->xoff + s->cx - ox;
    cy = wp->yoff + cursor_cy - oy;
}
// If cursor = 0, MODE_CURSOR is disabled (cursor hidden)
```

---

### 4. Capture Pane: `cmd-capture-pane.c`

**Line 219-224** - Slave captures rows 0-9:
```c
if (wp->panorama_role == PANORAMA_SLAVE && wp->panorama_sibling != NULL) {
    top = gd->hsize;                  // Start at history + 0
    bottom = top + wp->sy - 1;        // End at history + 9
}
```

**Line 225-232** - Master captures rows 10-19:
```c
else if (wp->panorama_role == PANORAMA_MASTER && wp->panorama_sibling != NULL) {
    u_int offset = wp->panorama_sibling->sy;  // = 10
    top = gd->hsize + offset;         // Start at history + 10
    bottom = top + wp->sy - 1;        // End at history + 19
}
```

---

### 5. PTY Resize: `window.c`

**Line 1133-1147** - Master pane resize:
```c
if (wp->panorama_role == PANORAMA_MASTER && wp->panorama_sibling != NULL) {
    u_int combined_sy = sy + wp->panorama_sibling->sy;  // 10 + 10 = 20
    screen_resize(&wp->base, sx, combined_sy, ...);     // Buffer = 20 rows
    wp->panorama_sibling->panorama_row_offset = sy;     // Slave offset = 10

    // Set PTY size
    struct winsize ws;
    ws.ws_row = combined_sy;          // Shell sees 20 rows
    ioctl(wp->fd, TIOCSWINSZ, &ws);
}
```

---

### 6. Slave Not Dead: `window.c`

**Line 1335-1341** - Don't mark slave as dead just because fd == -1:
```c
int window_pane_exited(struct window_pane *wp)
{
    // Slave intentionally has fd == -1, but is NOT dead
    if (wp->panorama_role == PANORAMA_SLAVE)
        return ((wp->flags & PANE_EXITED) != 0);
    return (wp->fd == -1 || (wp->flags & PANE_EXITED));
}
```

---

### 7. Cleanup Sibling: `window.c`

**Line 989-1002** - When master dies, kill slave too:
```c
if (wp->panorama_role == PANORAMA_MASTER && wp->panorama_sibling != NULL) {
    struct window_pane *slave = wp->panorama_sibling;
    slave->panorama_sibling = NULL;
    slave->panorama_role = PANORAMA_NONE;
    wp->panorama_sibling = NULL;
    slave->flags |= PANE_EXITED;
    server_destroy_pane(slave, 1);
}
```

---

## Debugging

```bash
# Check pane roles
./tmux list-panes -F '#{pane_id}: role=#{pane_panorama_role} x=#{pane_left}'

# Check PTY size (should be 20 for 10+10)
./tmux send-keys 'stty size' Enter

# Check cursor row in 20-row screen
./tmux display -p 'cursor_y=#{cursor_y}'

# Capture each pane
./tmux capture-pane -t %0 -p  # Master (RIGHT)
./tmux capture-pane -t %1 -p  # Slave (LEFT)
```

---

## Expected Behavior

| State | cursor_y | Prompt Location |
|-------|----------|-----------------|
| Startup | 0-3 | LEFT (this is normal!) |
| After `seq 1 25` | 19 | RIGHT |
| After Ctrl-C x30 | ~19 | RIGHT |

---

## Troubleshooting

**"Prompt on LEFT"**
- At startup this is EXPECTED. Cursor starts at row 0.
- Run `seq 1 25` to push cursor past row 10 to the RIGHT pane.

**"Cursor on RIGHT with weird offset"**
- Check `server-client.c:2968-2976` - cursor adjustment code.

**"Server crash"**
- Check null pointer: `wp->panorama_sibling` may be NULL.
- Check bounds in `screen-redraw.c:915-918`.

**"split-window: unknown flag -W"**
- Run `pkill -f tmux` first to kill cached server.
