; pctris.asm - Tetris for Sharp PC-1403
; Phase 3a: loop-based draw via IXL (O-piece cell table, 4 cells)
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
.include asm\_div_mod_8.lib

; === constants ===
.equ FIELD_X0   15      ; left edge  (LCD char 3  = pixel 15)
.equ FIELD_X1   78      ; max piece_x for 2-wide piece (char 15 right = px 79)
.equ FIELD_Y_C   2      ; centre row (0..6, piece spawn centered)
.equ FIELD_Y0    0      ; visual BOTTOM boundary (Y=0 = bottom)
.equ FIELD_Y1    5      ; visual TOP boundary (max_dy=1 for 2-tall pieces → Y=6)

; === keycodes (from _key_pc1403.lib keycode table) ===
; | v | | ^ |   →   3     10
.equ KEY_DOWN   3       ; v arrow (keycode 3)  → piece_y + 1 (visually down)
.equ KEY_UP     10      ; ^ arrow (keycode 10) → piece_y - 1 (visually up)
.equ KEY_ROTATE 16      ; < (rotate piece CW)
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

    ; update key_prev for next frame's edge detection
    LIDP key_cur
    LDD                     ; A = key_cur
    LIDP key_prev
    STD                     ; key_prev = key_cur

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

    ; spawn first piece (uses bRnd MOD 7 for piece_type)
    CALL spawn_piece
    RTN

; ============================================================
; spawn_piece: set piece_type from bRnd MOD 7, reset position, compute cell_ptr
; cell_ptr = PIECE_TABLE + piece_type × 32 + piece_rot × 8 - 1
; (the -1 compensates for IXL's pre-increment behavior)
;
; Algorithm for piece_type × 32:
;   piece_type × 32 = (piece_type << 5)
;   Using: SL (shift left) 5 times, or RC (rotate with carry) trick
spawn_piece:
    ; piece_type = bRnd MOD 7
    LIDP bRnd
    LDD                     ; A = bRnd
    ; call LIB_MOD8 with A=dividend, B=7 → A=remainder
    LIB  7
    CALL LIB_MOD8           ; A = bRnd MOD 7
    LIDP piece_type
    STD                     ; piece_type = A (0-6)

    ; piece_rot = 0 (for Phase 4, no rotation yet)
    LIA  0
    LIDP piece_rot
    STD

    ; reset piece position
    LIA  FIELD_X0
    LIDP piece_x
    STD                     ; piece_x = 15

    LIA  FIELD_Y_C
    LIDP piece_y
    STD                     ; piece_y = 3

    ; compute cell_ptr = PIECE_TABLE_DUMMY + piece_type × 32 + piece_rot × 8
    ; = PIECE_TABLE_DUMMY + piece_type × 32 (since piece_rot = 0)
    ;
    ; piece_type × 32 = piece_type << 5
    ; We build a 16-bit offset in M:N (low:high), then add to PIECE_TABLE_DUMMY address
    
    LIDP piece_type
    LDD                     ; A = piece_type (0-6)
    
    ; shift left 5 times: A × 32 → result in M:N (M=low, N=high)
    ; Max value: 6 × 32 = 192, fits in 8 bits, so N=0 always for this range
    LP   11
    LIA  0
    EXAM                    ; N = 0 (high byte of offset)
    
    LIDP piece_type
    LDD                     ; A = piece_type
    SL                      ; A = piece_type × 2
    SL                      ; A = piece_type × 4
    SL                      ; A = piece_type × 8
    SL                      ; A = piece_type × 16
    SL                      ; A = piece_type × 32
    LP   10
    EXAM                    ; M = piece_type × 32 (low byte of offset)

    ; cell_ptr = PIECE_TABLE_DUMMY + offset
    ; cell_ptr_lo = LB(PIECE_TABLE_DUMMY) + M
    ; cell_ptr_hi = HB(PIECE_TABLE_DUMMY) + N + carry
    
    LIA  LB(PIECE_TABLE_DUMMY)
    LP   10
    ADM                     ; M = LB(PIECE_TABLE_DUMMY) + offset_lo (may carry)
    
    ; save carry state: if M < offset_lo, there was a carry
    ; SC61860: ADM sets C if there was overflow (result >= 256)
    ; We need to check if addition carried
    LP   10
    LDM                     ; A = result (new M)
    LIDP cell_ptr_lo
    STD                     ; cell_ptr_lo = low byte result
    
    ; high byte: HB(PIECE_TABLE_DUMMY) + N + carry_from_low_addition
    ; Since N=0 and PIECE_TABLE_DUMMY is at a known address, 
    ; and max offset is 192, we just add HB + 0 + possible carry
    ; For simplicity, compute full 16-bit add:
    LIA  HB(PIECE_TABLE_DUMMY)
    LP   11
    ADM                     ; N = HB(PIECE_TABLE_DUMMY) + 0 (carry already added by ADM above? need to check)
    
    ; Actually SC61860 ADM doesn't propagate carry to next ADM
    ; So we handle carry manually: check if cell_ptr_lo < LB(PIECE_TABLE_DUMMY)
    ; If so, increment high byte
    
    LP   11
    LDM                     ; A = N (should be HB)
    LIDP cell_ptr_hi
    STD                     ; cell_ptr_hi = high byte
    
    ; Check for carry: if cell_ptr_lo < LB(PIECE_TABLE_DUMMY), add 1 to high
    ; Actually let's do it properly with 16-bit arithmetic
    ; Since offset is max 192 and PIECE_TABLE_DUMMY is near E2xx, 
    ; adding 192 to xx could overflow low byte
    
    ; Proper carry check:
    LIDP cell_ptr_lo
    LDD                     ; A = cell_ptr_lo
    CPIA LB(PIECE_TABLE_DUMMY)   ; if cell_ptr_lo < base_lo, there was carry
    JRNCP spawn_no_carry    ; C=0 means A >= imm, no carry needed
    ; C=1 means A < imm, which means we wrapped, add 1 to high
    LIDP cell_ptr_hi
    LDD
    INCA
    LIDP cell_ptr_hi
    STD
spawn_no_carry:
    RTN

; ============================================================
; update_cell_ptr: recompute cell_ptr from piece_type and piece_rot
; cell_ptr = PIECE_TABLE_DUMMY + piece_type × 32 + piece_rot × 8
;
; Called after rotation to update the table pointer
update_cell_ptr:
    ; Build offset = piece_type × 32 + piece_rot × 8
    ; Store in M:N (M=low, N=high)
    
    ; First: piece_type × 32 → M
    LIDP piece_type
    LDD                     ; A = piece_type (0-6)
    SL                      ; A = piece_type × 2
    SL                      ; A = piece_type × 4
    SL                      ; A = piece_type × 8
    SL                      ; A = piece_type × 16
    SL                      ; A = piece_type × 32
    LP   10
    EXAM                    ; M = piece_type × 32
    
    ; Second: piece_rot × 8 → add to M
    LIDP piece_rot
    LDD                     ; A = piece_rot (0-3)
    SL                      ; A = piece_rot × 2
    SL                      ; A = piece_rot × 4
    SL                      ; A = piece_rot × 8
    LP   10
    ADM                     ; M = piece_type × 32 + piece_rot × 8
    
    ; N = 0 (high byte, no overflow possible: max = 6×32 + 3×8 = 216)
    LP   11
    LIA  0
    EXAM                    ; N = 0
    
    ; cell_ptr = PIECE_TABLE_DUMMY + M (16-bit add)
    LIA  LB(PIECE_TABLE_DUMMY)
    LP   10
    ADM                     ; M = LB(PIECE_TABLE_DUMMY) + offset_lo
    LP   10
    LDM                     ; A = result
    LIDP cell_ptr_lo
    STD                     ; cell_ptr_lo = low byte
    
    ; high byte with carry check
    LIA  HB(PIECE_TABLE_DUMMY)
    LIDP cell_ptr_hi
    STD                     ; cell_ptr_hi = HB (tentative)
    
    ; check for carry: if cell_ptr_lo < LB(PIECE_TABLE_DUMMY), add 1 to high
    LIDP cell_ptr_lo
    LDD                     ; A = cell_ptr_lo
    CPIA LB(PIECE_TABLE_DUMMY)
    JRNCP update_ptr_done   ; C=0: A >= imm, no carry
    ; C=1: wrapped, add 1 to high byte
    LIDP cell_ptr_hi
    LDD
    INCA
    LIDP cell_ptr_hi
    STD
update_ptr_done:
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

; draw/erase 4 cells of current piece via (dx,dy) table
; K must already be set (1=set pixel, 0=clear pixel)
; Reads 4×(dx,dy) pairs from O_PIECE_DATA using IXL (pre-increment X)
; IXL: X+1→X, X→DP, (DP)→A  — sequential auto-advance
;
; IMPORTANT constraints:
;   - PSET uses I (LII 7 in its internal loop) → outer loop uses J (safe)
;   - PSET calls IXL internally → clobbers XL:XH after each call
;   - ptr_lo/ptr_hi save XL:XH across PSET calls so IXL can resume
;   - M (P=10) = tmp dx ;  N (P=11) = tmp dy
;   - PSET has built-in Y>6 clip, so no extra guard needed here
pset_piece:
    LIJ  4                      ; J = 4: outer loop counter (PSET clobbers I, not J)
    ; Load cell_ptr (pointer to current piece's rotation data)
    ; cell_ptr is set by spawn_piece to PIECE_TABLE + piece_type*32 + piece_rot*8 - 1
    ; (the -1 is because IXL pre-increments X before reading)
    LIDP cell_ptr_lo
    LDD
    LP   4
    EXAM                        ; XL = cell_ptr_lo
    LIDP cell_ptr_hi
    LDD
    LP   5
    EXAM                        ; XH = cell_ptr_hi
pset_cell_loop:
    IXL                         ; X++, A = dx; X = &O_PIECE_DATA[2*cell]
    LP   10
    EXAM                        ; M = dx  (A = discarded old M)
    IXL                         ; X++, A = dy; X = &O_PIECE_DATA[2*cell+1]
    LP   11
    EXAM                        ; N = dy  (A = discarded old N)

    ; save X (= address of just-read dy byte) → ptr_lo/ptr_hi
    ; so we can restore X after PSET clobbers it
    LP   4
    LDM                         ; A = XL  (LDM: (P)→A, non-destructive)
    LIDP ptr_lo
    STD                         ; ptr_lo = XL
    LP   5
    LDM                         ; A = XH
    LIDP ptr_hi
    STD                         ; ptr_hi = XH

    ; pixel_x = piece_x + dx(M)
    LIDP piece_x
    LDD                         ; A = piece_x
    LP   10
    ADM                         ; M = dx + piece_x  (ADM: (P)+A→(P))

    ; pixel_y = piece_y + dy(N)
    LIDP piece_y
    LDD                         ; A = piece_y
    LP   11
    ADM                         ; N = dy + piece_y

    ; --- Y boundary clip: skip PSET if pixel_y > 6 ---
    LP   11
    LDM                         ; A = pixel_y (N)
    CPIA 7                      ; C=1 if A < 7 (in bounds), C=0 if A >= 7
    JRNCP pset_skip_cell        ; C=0: Y >= 7, skip this cell

    ; load XL = pixel_x for PSET
    LP   10
    LDM                         ; A = pixel_x
    LP   4
    EXAM                        ; XL = pixel_x

    ; load YL = pixel_y for PSET
    LP   11
    LDM                         ; A = pixel_y
    LP   6
    EXAM                        ; YL = pixel_y

    CALL LCD_LIB_PSET           ; set/clear pixel; K already set by caller
                                ; PSET clobbers X (XL:XH), I, A, B

pset_skip_cell:
    ; restore X pointer for next IXL
    LIDP ptr_lo
    LDD                         ; A = saved XL
    LP   4
    EXAM                        ; XL = ptr_lo
    LIDP ptr_hi
    LDD                         ; A = saved XH
    LP   5
    EXAM                        ; XH = ptr_hi

    DECJ                        ; J--; Z=1 when J hits 0
    JRNZM pset_cell_loop        ; loop while J != 0

    RTN

; ============================================================
; move piece one pixel right; wrap to FIELD_X0 at right boundary → spawn new piece
move_piece:
    LIDP piece_x
    LDD                     ; A = piece_x
    INCA                    ; A = piece_x + 1
    CPIA FIELD_X1+1         ; C=1 → A < 79 (in field);  C=0 → A >= 79 (wrap)
    JRCP move_piece_ok      ; C=1: still in field → keep new value
    ; wrap: spawn new random piece
    CALL spawn_piece
    RTN
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
    LIDP key_cur
    LDD
    CPIA KEY_UP
    JRNZP hi_check_rotate   ; not UP key

    ; Step 1: compute new_y = piece_y + 1
    LIDP piece_y
    LDD                     ; A = piece_y
    INCA                    ; A = new_y
    LIDP tmp_new_y
    STD                     ; tmp_new_y = new_y
    
    ; Step 2: get max_y for this piece/rotation
    CALL get_max_y          ; A = max_y
    LP   10
    EXAM                    ; M = max_y
    
    ; Step 3: compare - is new_y > max_y?
    ; CPMA does M - A, sets C=1 if M < A (i.e., max_y < new_y)
    LIDP tmp_new_y
    LDD                     ; A = new_y
    LP   10
    CPMA                    ; M - A = max_y - new_y
                            ; C=0 if max_y >= new_y (in bounds)
                            ; C=1 if max_y < new_y (out of bounds)
    
    JRCP hi_clamp           ; C=1: out of bounds, need to clamp
    
    ; In bounds: use new_y
    LIDP tmp_new_y
    LDD                     ; A = new_y
    LIDP piece_y
    STD                     ; piece_y = new_y
    RTN

hi_clamp:
    ; Out of bounds: use max_y
    LP   10
    LDM                     ; A = max_y (from M register)
    LIDP piece_y
    STD                     ; piece_y = max_y
    RTN

hi_check_rotate:
    ; --- < key (KEY_ROTATE=16): piece_rot = (piece_rot + 1) MOD 4 ---
    ; Edge detection: only rotate if key_cur != key_prev (new press)
    LIDP key_cur
    LDD                     ; A = keycode
    CPIA KEY_ROTATE         ; Z=1 if A==16
    JRNZP hi_done           ; Z=0: not <, nothing to do
    
    ; Check edge: is this a NEW press? (key_prev != KEY_ROTATE)
    LIDP key_prev
    LDD                     ; A = key_prev
    CPIA KEY_ROTATE         ; Z=1 if key_prev == KEY_ROTATE (still held)
    JRZP hi_done            ; Z=1: key still held from last frame, skip

    LIDP piece_rot
    LDD                     ; A = piece_rot (0-3)
    INCA                    ; A = piece_rot + 1
    ANIA 0x03               ; A = A AND 3 = (piece_rot + 1) MOD 4
    LIDP piece_rot
    STD                     ; piece_rot = new value

    ; recompute cell_ptr after rotation change
    CALL update_cell_ptr

    ; clamp piece_y after rotation so piece stays in bounds
    CALL get_max_y          ; A = max allowed piece_y
    LP   10
    EXAM                    ; M = max_y, A = old M (discarded)
    
    LIDP piece_y
    LDD                     ; A = piece_y
    ; compare: is piece_y > max_y?
    ; CPMA does M - A: C=1 if M < A (piece_y > max_y)
    LP   10
    CPMA
    JRNCP hi_done           ; C=0: max_y >= piece_y, in bounds
    ; C=1: piece_y > max_y, clamp it
    LP   10
    LDM                     ; A = max_y
    LIDP piece_y
    STD                     ; piece_y = max_y
    RTN

hi_done:
    RTN

; ============================================================
; get_max_y: get max allowed piece_y for current piece/rotation
; Returns: A = MAX_Y_TABLE[piece_type * 4 + piece_rot]
; Simple loop approach: start at table base, read index+1 times
get_max_y:
    ; compute index = piece_type * 4 + piece_rot → store in B
    LIDP piece_type
    LDD                     ; A = piece_type (0-6)
    SL                      ; A = piece_type * 2
    SL                      ; A = piece_type * 4
    LIDP piece_rot
    EXAB                    ; B = piece_type * 4, A = garbage
    LDD                     ; A = piece_rot (0-3)
    EXAB                    ; A = piece_type * 4, B = piece_rot
    ADB                     ; B = piece_type * 4 + piece_rot = index
    
    ; X = MAX_Y_TABLE - 1 (for IXL which pre-increments)
    LIA  LB(MAX_Y_TABLE)
    DECA
    LP   4
    EXAM                    ; XL = LB - 1
    LIA  HB(MAX_Y_TABLE)
    LP   5
    EXAM                    ; XH = HB
    ; if LB was 0, XL is now 0xFF → XH should be decremented
    ; but LB(MAX_Y_TABLE) = 0x96 != 0, so no underflow possible here
    
    ; Loop: read B+1 times (B = index, we want element at index)
    INCB                    ; B = index + 1
get_max_y_loop:
    IXL                     ; X++, A = (X)
    DECB                    ; B--
    JRNZM get_max_y_loop    ; loop while B != 0
    
    ; A = MAX_Y_TABLE[index]
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
piece_x:        .DB  15     ; current X pixel position of active piece
piece_y:        .DB   3     ; current Y pixel position of active piece
piece_type:     .DB   3     ; current piece type (0-6: I,J,L,O,S,T,Z) - default O
piece_rot:      .DB   0     ; current rotation (0-3: 0°,90°,180°,270°)
key_cur:        .DB   0     ; keycode captured at top of main_loop
key_prev:       .DB   0     ; keycode from previous frame (for edge detection)
bRnd:           .DB   0     ; free-running RNG counter (used by LIB_RND_PC1403)
ptr_lo:         .DB   0     ; saved XL (low byte of table ptr) across PSET calls
ptr_hi:         .DB   0     ; saved XH (high byte of table ptr) across PSET calls
cell_ptr_lo:    .DB   0     ; low byte of pointer to current piece's cell data
cell_ptr_hi:    .DB   0     ; high byte of pointer to current piece's cell data
tmp_max_y:      .DB   0     ; temporary storage for max_y during comparison
tmp_new_y:      .DB   0     ; temporary storage for new_y during comparison

; === MAX_Y Table ===
; max allowed piece_y for each piece/rotation (pre-computed: 6 - max_dy)
; 7 pieces × 4 rotations = 28 bytes
; Order: I(0-3), J(0-3), L(0-3), O(0-3), S(0-3), T(0-3), Z(0-3)
MAX_Y_TABLE:
    .DB 6, 3, 6, 3      ; I: rot0=horiz(6), rot1=vert(3), rot2=horiz(6), rot3=vert(3)
    .DB 5, 4, 5, 4      ; J: rot0(5), rot1(4), rot2(5), rot3(4)
    .DB 5, 4, 5, 4      ; L: rot0(5), rot1(4), rot2(5), rot3(4)
    .DB 5, 5, 5, 5      ; O: all rotations same (5)
    .DB 5, 4, 5, 4      ; S: rot0(5), rot1(4), rot2(5), rot3(4)
    .DB 5, 4, 5, 4      ; T: rot0(5), rot1(4), rot2(5), rot3(4)
    .DB 5, 4, 5, 4      ; Z: rot0(5), rot1(4), rot2(5), rot3(4)

; === Piece Table ===
; 7 shapes × 4 rotations × 4 cells × 2 bytes (dx, dy) = 224 bytes
; Pieces: I=0, J=1, L=2, O=3, S=4, T=5, Z=6
; Rotation: 0=spawn, 1=90°CW, 2=180°, 3=270°CW
; NORMALIZED: all rotations have min_dy=0 (anchored to top of bounding box)
;
; PIECE_TABLE_DUMMY is 1 byte before PIECE_TABLE so that X = PIECE_TABLE_DUMMY
; and the first IXL (pre-increment) lands exactly on PIECE_TABLE[0].

PIECE_TABLE_DUMMY:  .DB 0

PIECE_TABLE:
; --- I-piece (index 0) ---
; Rot 0:  XXXX      Rot 1:  .X..      Rot 2:  XXXX      Rot 3:  ..X.
;         ....              .X..              ....              ..X.
;         ....              .X..              ....              ..X.
;         ....              .X..              ....              ..X.
    .DB 0,0, 1,0, 2,0, 3,0      ; I rot 0: horizontal (was dy=1, shifted -1)
    .DB 1,0, 1,1, 1,2, 1,3      ; I rot 1: vertical (already min_dy=0)
    .DB 0,0, 1,0, 2,0, 3,0      ; I rot 2: horizontal (was dy=2, shifted -2)
    .DB 2,0, 2,1, 2,2, 2,3      ; I rot 3: vertical (already min_dy=0)

; --- J-piece (index 1) ---
; Rot 0:  X...      Rot 1:  .XX.      Rot 2:  XXX.      Rot 3:  .X..
;         XXX.              .X..              ..X.              .X..
;         ....              .X..              ....              XX..
;         ....              ....              ....              ....
    .DB 0,0, 0,1, 1,1, 2,1      ; J rot 0 (already min_dy=0)
    .DB 1,0, 2,0, 1,1, 1,2      ; J rot 1 (already min_dy=0)
    .DB 0,0, 1,0, 2,0, 2,1      ; J rot 2 (was dy=1,1,1,2, shifted -1)
    .DB 1,0, 1,1, 0,2, 1,2      ; J rot 3 (already min_dy=0)

; --- L-piece (index 2) ---
; Rot 0:  ..X.      Rot 1:  .X..      Rot 2:  XXX.      Rot 3:  .XX.
;         XXX.              .X..              X...              ..X.
;         ....              .XX.              ....              ..X.
;         ....              ....              ....              ....
    .DB 2,0, 0,1, 1,1, 2,1      ; L rot 0 (already min_dy=0)
    .DB 1,0, 1,1, 1,2, 2,2      ; L rot 1 (already min_dy=0)
    .DB 0,0, 1,0, 2,0, 0,1      ; L rot 2 (was dy=1,1,1,2, shifted -1)
    .DB 0,0, 1,0, 1,1, 1,2      ; L rot 3 (already min_dy=0)

; --- O-piece (index 3) ---
; All rotations identical (2×2 block)
; Rot 0-3: .XX.
;          .XX.
;          ....
;          ....
    .DB 1,0, 2,0, 1,1, 2,1      ; O rot 0
    .DB 1,0, 2,0, 1,1, 2,1      ; O rot 1 (same)
    .DB 1,0, 2,0, 1,1, 2,1      ; O rot 2 (same)
    .DB 1,0, 2,0, 1,1, 2,1      ; O rot 3 (same)

; --- S-piece (index 4) ---
; Rot 0:  .XX.      Rot 1:  .X..      Rot 2:  .XX.      Rot 3:  X...
;         XX..              .XX.              XX..              XX..
;         ....              ..X.              ....              .X..
;         ....              ....              ....              ....
    .DB 1,0, 2,0, 0,1, 1,1      ; S rot 0 (already min_dy=0)
    .DB 1,0, 1,1, 2,1, 2,2      ; S rot 1 (already min_dy=0)
    .DB 1,0, 2,0, 0,1, 1,1      ; S rot 2 (was dy=1,1,2,2, shifted -1) = same as rot 0
    .DB 0,0, 0,1, 1,1, 1,2      ; S rot 3 (already min_dy=0)

; --- T-piece (index 5) ---
; Rot 0:  .X..      Rot 1:  .X..      Rot 2:  XXX.      Rot 3:  .X..
;         XXX.              .XX.              .X..              XX..
;         ....              .X..              ....              .X..
;         ....              ....              ....              ....
    .DB 1,0, 0,1, 1,1, 2,1      ; T rot 0 (already min_dy=0)
    .DB 1,0, 1,1, 2,1, 1,2      ; T rot 1 (already min_dy=0)
    .DB 0,0, 1,0, 2,0, 1,1      ; T rot 2 (was dy=1,1,1,2, shifted -1)
    .DB 1,0, 0,1, 1,1, 1,2      ; T rot 3 (already min_dy=0)

; --- Z-piece (index 6) ---
; Rot 0:  XX..      Rot 1:  ..X.      Rot 2:  XX..      Rot 3:  .X..
;         .XX.              .XX.              .XX.              XX..
;         ....              .X..              ....              X...
;         ....              ....              ....              ....
    .DB 0,0, 1,0, 1,1, 2,1      ; Z rot 0 (already min_dy=0)
    .DB 2,0, 1,1, 2,1, 1,2      ; Z rot 1 (already min_dy=0)
    .DB 0,0, 1,0, 1,1, 2,1      ; Z rot 2 (was dy=1,1,2,2, shifted -1) = same as rot 0
    .DB 1,0, 0,1, 1,1, 0,2      ; Z rot 3 (already min_dy=0)
