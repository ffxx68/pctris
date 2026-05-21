; pctris.asm - Tetris for Sharp PC-1403
; Phase 2: vertical input (v/^), fast-forward (>), DEF exit
; assemble with:  pasm asm\pctris.asm pctris.bin

.ORG    0xE030

; === entry point: save/restore registers I..N (0..11) ===

    LP   0
    LIDP SREG
    LII  11
    EXWD

    CALL main

    LP   0
    LIDP SREG
    LII  11
    MVWD
    RTN

SREG:   .DW 0, 0, 0, 0, 0, 0


; === library includes ===
.include asm\_lcd_pc1403_cls.lib
.include asm\_lcd_pc1403_pset.lib
.include asm\_key_pc1403.lib
.include asm\_rnd_pc1403.lib

; === constants ===
.equ FIELD_X0   15      ; left edge  (LCD char 3  = pixel 15)
.equ FIELD_X1   78      ; max piece_x for 2-wide piece (char 15 right = px 79)
.equ FIELD_Y_C   3      ; centre row (0..6, piece 2 tall → top at row 3)
.equ FIELD_Y0    0      ; visual BOTTOM boundary (Y=0 = bottom in MAME rendering)
.equ FIELD_Y1    5      ; visual TOP boundary (2-tall piece top ≤ 5 → rows 5,6)

; === keycodes (from _key_pc1403.lib keycode table) ===
; | v | | ^ |   →   3     10
.equ KEY_DOWN   3       ; v arrow (keycode 3)  → piece_y + 1 (visually down)
.equ KEY_UP     10      ; ^ arrow (keycode 10) → piece_y - 1 (visually up)
.equ KEY_FAST   21      ; > (fast-forward)
.equ KEY_DEF    37      ; DEF (exit to BASIC)


; ============================================================
main:
    CALL init_game

main_loop:
    CALL LIB_RND_PC1403     ; keep RNG counter ticking

    CALL PC1403_ROM_KEYSCAN ; non-blocking scan → keycode in A, 0 if no key
    LIDP key_cur
    STD                     ; save keycode for reuse this frame

    CPIA KEY_DEF            ; DEF key? (CPIA: A-n, sets Z=1 if A==n, C unchanged)
    JRZP main_exit          ; Z=1: exit (fwd jump to RTN after loop body)

    CALL erase_piece        ; erase OLD position FIRST (before any move)
    CALL handle_input       ; update piece_y from ▼/▲ keys
    CALL move_piece         ; advance piece_x right
    CALL draw_piece         ; draw at NEW position

    ; fast-forward: skip delay if > (KEY_FAST) was pressed
    LIDP key_cur
    LDD                     ; A = keycode
    CPIA KEY_FAST           ; Z=1 if > key
    JRZM main_loop          ; Z=1: skip delay, jump back (backward)

    CALL delay              ; normal frame pacing
    JRM  main_loop          ; loop back (backward)

main_exit:
    RTN                     ; DEF pressed → entry stub restores regs

; ============================================================
init_game:
    ; turn LCD on
    CALL LCD_LIB_ON

    ; clear screen (K=0 → clear mode for LCD_LIB_CLS)
    LIA  0
    LP   0x08               ; P = 8 (register K)
    EXAM                    ; K = 0
    CALL LCD_LIB_CLS

    ; initial piece position
    LIA  FIELD_X0
    LIDP piece_x
    STD                     ; piece_x = 15

    LIA  FIELD_Y_C
    LIDP piece_y
    STD                     ; piece_y = 3
    RTN

; ============================================================
; draw O-piece (2×2) at (piece_x, piece_y) – SET pixels
draw_piece:
    LIA  1
    LP   0x08
    EXAM                    ; K = 1 (set mode)
    CALL pset_piece
    RTN

; erase O-piece (2×2) at (piece_x, piece_y) – CLEAR pixels
erase_piece:
    LIA  0
    LP   0x08
    EXAM                    ; K = 0 (clear mode)
    ; fall through to pset_piece

; draw/erase the 4 pixels of the O-piece using current K
; K must already be set; XL/YL are set here from piece_x/piece_y
pset_piece:
    ; --- pixel (piece_x, piece_y) ---
    LIDP piece_x
    LDD
    LP   4
    EXAM                    ; XL = piece_x

    LIDP piece_y
    LDD
    LP   6
    EXAM                    ; YL = piece_y
    CALL LCD_LIB_PSET

    ; --- pixel (piece_x+1, piece_y) ---
    LIDP piece_x
    LDD
    INCA
    LP   4
    EXAM                    ; XL = piece_x + 1

    LIDP piece_y
    LDD
    LP   6
    EXAM                    ; YL = piece_y (reload: PSET may clobber it)
    CALL LCD_LIB_PSET

    ; --- pixel (piece_x, piece_y+1) ---
    LIDP piece_x
    LDD
    LP   4
    EXAM                    ; XL = piece_x

    LIDP piece_y
    LDD
    INCA
    LP   6
    EXAM                    ; YL = piece_y + 1
    CALL LCD_LIB_PSET

    ; --- pixel (piece_x+1, piece_y+1) ---
    LIDP piece_x
    LDD
    INCA
    LP   4
    EXAM                    ; XL = piece_x + 1

    LIDP piece_y
    LDD
    INCA
    LP   6
    EXAM                    ; YL = piece_y + 1
    CALL LCD_LIB_PSET

    RTN

; ============================================================
; move piece one pixel right; wrap to FIELD_X0 at right boundary
move_piece:
    LIDP piece_x
    LDD                     ; A = piece_x
    INCA                    ; A = piece_x + 1
    CPIA FIELD_X1+1         ; C=1 → A < 79 (in field);  C=0 → A >= 79 (wrap)
    JRCP move_piece_ok      ; C=1: still in field → keep new value
    LIA  FIELD_X0           ; wrap: reset to left edge
move_piece_ok:
    LIDP piece_x
    STD                     ; piece_x = new value
    RTN

; ============================================================
; handle_input: read key_cur, update piece_y for UP/DOWN
; CPIA = A-n → Z=1 if equal, C=1 if A<n  (table: Test e Confronto)
; JRNZP = fwd jump if Z=0 (A≠n)          (table: Salti Relativi Condizionali)
; JRCP  = fwd jump if C=1 (A<n, in bounds)(table: Salti Relativi Condizionali)
handle_input:
    LIDP key_cur
    LDD                     ; A = keycode

    ; --- v arrow (KEY_DOWN=3): piece_y - 1 (visual DOWN = smaller Y in MAME) ---
    CPIA KEY_DOWN           ; Z=1 if A==3
    JRNZP hi_check_up       ; Z=0: not v, check ^

    LIDP piece_y
    LDD                     ; A = piece_y
    CPIA FIELD_Y0+1         ; C=1 if A < 1 (A==0: already at visual bottom)
    JRCP hi_done            ; C=1: at bottom, no change
    DECA                    ; A = piece_y - 1
    LIDP piece_y
    STD                     ; piece_y = A
    RTN

hi_check_up:
    ; --- ^ arrow (KEY_UP=10): piece_y + 1 (visual UP = larger Y in MAME) ---
    CPIA KEY_UP             ; Z=1 if A==10
    JRNZP hi_done           ; Z=0: not ^, nothing to do

    LIDP piece_y
    LDD                     ; A = piece_y
    INCA                    ; A = piece_y + 1
    CPIA FIELD_Y1+1         ; C=1 if A < 6 (new piece_y ≤ 5, in bounds)
    JRCP hi_set_y           ; C=1: in bounds, keep value in A
    LIA  FIELD_Y1           ; C=0: clamp to 5
hi_set_y:
    LIDP piece_y
    STD                     ; piece_y = A
    RTN

hi_done:
    RTN

; ============================================================
; frame delay  ~60 ms at 750 KHz
; outer (B): 20 × inner (A): 256 × ~11 cycles ≈ 56320 cycles ≈ 75 ms
delay:
    LIB  5                  ; outer counter
delay_outer:
    LIA  0                  ; inner = 256 iterations
delay_inner:
    DECA
    JRNZM delay_inner       ; loop while A != 0
    DECB
    JRNZM delay_outer       ; loop while B != 0
    RTN

; ============================================================
; variables  (inline .DB → writable in user RAM at .ORG 0xE030)
piece_x:    .DB  15         ; current X pixel position of active piece
piece_y:    .DB   3         ; current Y pixel position of active piece
key_cur:    .DB   0         ; keycode captured at top of main_loop
bRnd:       .DB   0         ; free-running RNG counter (used by LIB_RND_PC1403)
