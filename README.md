# PCTris — Tetris for Sharp PC-1403

A Tetris implementation in SC61860 assembly for the Sharp PC-1403 pocket computer,
assembled with **pasm v1.1**.

---

## Hardware Target

| Parameter | Value |
|-----------|-------|
| CPU | Sharp SC-61860 @ ~750 KHz |
| LCD | 24 characters × 1 line, 7×5 pixel font → **144 × 7 pixels** |
| RAM (user) | `0xE000`–`0xFFFF` (approx.) |
| Entry point | `0xE030` (called from BASIC: `CALL &E030`) |

The display is used **horizontally**: pieces enter from the **left** and stack on the **right**.
Only characters 3–15 are used (pixel columns 15–79, 65 columns × 7 rows).

---

## Repository Structure

```
pctris/
├── asm/
│   ├── pctris.asm              ← main source (entry point + game logic)
│   ├── pctris.bin              ← assembled binary (load at 0xE030)
│   ├── _lcd_pc1403_cls.lib     ← LCD clear / LCD on-off
│   ├── _lcd_pc1403_pset.lib    ← LCD pixel set/clear (LCD_LIB_PSET)
│   ├── _key_pc1403.lib         ← keyboard scan (blocking + non-blocking)
│   ├── _rnd_pc1403.lib         ← free-running RNG counter (2 ms timer)
│   └── _div_mod_8.lib          ← integer divide / modulo (8-bit)
├── lib/                        ← original library sources (backup)
├── docs/
│   ├── pasm reference.txt      ← pasm assembler documentation
│   ├── pasm_commands_table.md  ← SC61860 opcode quick reference
│   ├── assembler commands.rtf  ← full instruction set reference
│   └── Sharp PC 140X Highlights.docx
├── pasm.exe                    ← assembler binary
├── mame_mcp_readme.md          ← MAME MCP debug server documentation
└── README.md                   ← this file
```

---

## Build

```powershell
cd C:\Users\<user>\git\pctris
.\pasm.exe asm\pctris.asm asm\pctris.bin
```

Output: `asm/pctris.bin` — raw binary, start address `0xE030`.

To run on the PC-1403 (or MAME emulator):
```
CALL &E030
```
Press **DEF** to exit back to BASIC (BRK triggers a hardware interrupt and crashes).

---

## Architecture

### Entry / Exit convention
The BASIC `CALL` instruction saves only the return address. The entry stub at `0xE030`
saves all SC61860 registers I–N (12 bytes) into `SREG` via `EXWD`/`MVWD`, then calls
`main`. On BRK keypress `main` returns and the stub restores the registers before `RTN`.

### Libraries (`.include`)
All four libraries are included inline via `.include` and assembled into the same binary.
They are placed **after** the entry stub and SREG area so that `0xE030` always contains
the entry code callable from BASIC.

| Library | Entry point | Effect |
|---------|-------------|--------|
| `_lcd_pc1403_cls.lib` | `LCD_LIB_CLS` | Fill/clear all LCD pixels; `K=1`=fill, `K=0`=clear |
| `_lcd_pc1403_pset.lib` | `LCD_LIB_PSET` | Set or clear pixel at (XL, YL); `K=1`=set, `K=0`=clear |
| `_key_pc1403.lib` | `PC1403_ROM_KEYSCAN` / `LIB_KEYCL1S` | Key scan; BRK check returns 1/0 in A |
| `_rnd_pc1403.lib` | `LIB_RND_PC1403` | Increments `bRnd` on each 2 ms tick |

### RNG
`LIB_RND_PC1403` is called every main-loop iteration. It tests the 2 ms hardware timer
flag and increments `bRnd` (at `0xE221`) on each tick. At spawn time, `bRnd MOD 7`
(via `LIB_MOD8` from `_div_mod_8.lib`) gives a pseudo-random piece index 0–6.

### Frame delay
At 750 KHz CPU clock, a simple double-loop provides ~150 ms per frame:
- outer counter B = ?
- inner counter A = 256 (DECA + JRNZM = ~11 cycles each)
- total ≈ 40 × 256 × 11 = ~112 640 cycles ≈ 150 ms

In a test from phase 1, setting B to 5 gives a good feel for piece movement speed, 
and leaves room for speed increases in later phases.
---

## Development Plan

### Phase 1 — LCD validation ✅ DONE
- [x] Entry/exit register save/restore
- [x] LCD on + clear screen
- [x] O-piece (2×2 block) scrolling left→right across the field
- [x] DEF key exits cleanly (BRK triggers HW interrupt → use KEYSCAN+keycode 37)
- [x] Frame delay tuned (B=5 outer × 256 inner loops)
- [x] Compiled and loaded in MAME (498 bytes)
- [x] Test on MAME ✅ — block scrolls across screen, DEF exits to BASIC

### Phase 2 — Input & vertical movement
- [x] Read ▼ (keycode 3) / ▲ (keycode 10) → move `piece_y` ±1
- [x] Read `>` (keycode 21) → fast-forward (skip delay)
- [x] Clamp `piece_y` to field bounds (0–5 for 2-tall piece)
- [x] Test on MAME - ✅ — piece moves down every frame, faster with `>`, and can be moved up/down with ▲/▼ keys

### Phase 3 — Tetromino shapes
- [ ] Piece table: 7 shapes × 4 rotations × 4 offsets (dx, dy) = 112 bytes `.DB`
- [ ] Spawn: read `bRnd MOD 7` → shape index; centred Y; X = left edge
- [ ] Rotation: `>` / `<` key cycles `piece_rot` 0–3, redraw
- [ ] Generalise `pset_piece` to loop over 4 offsets from table
- [ ] Test on MAME

### Phase 4 — Board & collision
- [ ] Board array: 13 bytes (one per column), each byte = 7-bit row bitmask
- [ ] `BOARD_COLLISION`: check each piece cell against board bitmask + boundaries
- [ ] `BOARD_LOCK`: OR piece cells into board on landing
- [ ] Gravity: each N frames advance piece_x +1; collision → lock
- [ ] Test on MAME

### Phase 5 — Line clear & score
- [ ] `CHECK_LINES`: scan all 7 rows; full row (all 13 col-bits set) → shift board left
- [ ] Score counter (1 byte, BCD or binary); display via ROM BASIC routine or pixel font
- [ ] Test on MAME

### Phase 6 — Polish
- [ ] Game-over detection (piece locked at X=15 immediately after spawn)
- [ ] "GAME OVER" message on LCD (using BASIC ROM `PRINT` or pixel sprites)
- [ ] Speed increase every N lines cleared (reduce outer delay counter)
- [ ] Next-piece preview in characters 0–2 (left of field)
- [ ] Test on MAME
- [ ] Test on real hardware (PC-1403)

---

## Debugging with MAME

MAME is used as the emulator with the MCP bridge for automated debugging.

See [`mame_mcp_readme.md`](mame_mcp_readme.md) for full setup instructions.

Pre-requisite: having MAME of course, as well as the PC-1403 ROM and layout installed in MAME.

---

## Quick deployment and testing workflow:

### 1. compile and copy to your MAME home
`.\pasm.exe asm\pctris.asm asm\pctris.bin`

`copy asm\pctris.bin C:\Users\mame\pctris.bin`

### 2. start MAME manually
`cd C:\Users\mame`

`mame.exe pc1403 -debug -nomaximize -console`

Then, soft-reset (with `<F3>` on the MAME debugger), until the emulated PC-1403 starts 
(at 'MEMORY ALL CLEAR O.K.?' message; press enter on the emulated machine.)

### 3. in MAME Lua console, activate MCP bridge
`dofile("mame_mcp_bridge.lua")`

### 4. in MAME Lua console, enable key mapping (optional, for testing input)
`dofile("pc1403_key.lua")`

### 5. in MAME Lua console, init PC-1403 memory to accomodate the binary
`keyfile("pc1403_init.key")`

This will init the emulated machine and would need to be done only once,
unless you reset the machine or want to re-test from a clean state.

*Note* - [mame_mcp_bridge.lua](mame_mcp_bridge.lua), [mame_mcp_server.py](mame_mcp_server.py) are inherited from the https://github.com/ffxx68/mame_mcp_server repositiry
, while [pc1403_key.lua](pc1403_key.lua), and [pc1403_init.key](pc1403_init.key) are inherited from the https://github.com/ffxx68/Sharp_LittleC_Compiler project.

### 6. from Copilot / MCP: load binary and set breakpoints

Ask for example in Copilot "Load the PCTris binary into MAME and set a breakpoint at the main game loop"

From here on, you can use both Copilot, or direct MAME interactions, to test and debug...

---

## Known Issues / Notes

- The `erase_piece` → `pset_piece` fall-through relies on no instruction between the
  two labels; do not insert code between them.
- `CPIA` on SC61860 sets Carry=1 if A < immediate (borrow), so `JRCP` branches when A < immediate (still in field) and `JRNCP` branches when A ≥ immediate — use `JRCP` for "in bounds" checks.

