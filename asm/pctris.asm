; pctris.asm - Tetris for Sharp PC-1403
; proof-of-concept: O-piece scrolling right on LCD to validate LCD access
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


; ============================================================
main:
    CALL init_game

main_loop:
    CALL LIB_RND_PC1403     ; keep RNG counter ticking

    CALL erase_piece         ; clear current 2x2 block from LCD
    CALL move_piece          ; advance piece_x right (wraps at FIELD_X1)
    CALL draw_piece          ; draw 2x2 block at new position

    CALL delay               ; ~150 ms frame delay

    CALL LIB_KEYCL1S         ; returns 1 if BRK pressed, 0 otherwise
    CPIA 0
    JRZP main_loop           ; A=0 → no BRK → keep looping
    RTN                      ; BRK pressed → exit → entry code restores regs

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
    CPIA FIELD_X1+1         ; C=0 → A < 79 (ok);  C=1 → A >= 79 (wrap)
    JRNCP move_piece_ok     ; C=0: still in field
    LIA  FIELD_X0           ; wrap: reset to left edge
move_piece_ok:
    LIDP piece_x
    STD                     ; piece_x = new value
    RTN

; ============================================================
; frame delay  ~150 ms at 750 KHz
; outer (B): 40 iterations × inner (A): 256 × 11 cycles ≈ 150 ms
delay:
    LIB  40                 ; outer counter
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
bRnd:       .DB   0         ; free-running RNG counter (used by LIB_RND_PC1403)
