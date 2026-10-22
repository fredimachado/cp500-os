; Software cursor on a 64 by 16 plane, the CP-500's B0h bar. Each console has
; a plane and 14 state bytes; CUR_ROW..BLINK_DIV hold the bound console's.

console_puts:
                ld a, (hl)
                or a
                ret z
                push hl
                ld d, 0
                call console_putc
                pop hl
                inc hl
                jr console_puts

; A = byte, D = console. Brackets the cursor cell so the ISR cannot redraw it mid-update.
console_putc:
                di
                ld c, a
                ld a, (CON_BOUND)
                cp d
                call nz, con_bind
                ld a, (ANSI_STATE)
                or a
                jr z, con_ground
                cp ANSI_ESC
                jp z, con_esc
                call con_csi
con_leave:
                ei
                ret

con_ground:
                ld a, c
                cp 1Bh
                jr z, con_arm_esc
                cp 0Dh
                jr z, con_cr
                cp 0Ah
                jr z, con_lf
                cp 08h
                jr z, con_bs
                cp 20h
                jr c, con_leave
                sub 0C0h
                jr c, con_glyph
                add a, LAT1_GLYPH & 0FFh
                ld l, a
                ld h, LAT1_GLYPH >> 8
                ld c, (hl)
con_glyph:
                ld hl, BLINK_DIV
                set 7, (hl)
                call con_restore
                call con_addr
                ld (hl), c
                call con_advance
                call con_grab
                call con_apply
                jr con_leave

con_arm_esc:
                ld a, ANSI_ESC
                ld (ANSI_STATE), a
                jr con_leave

con_cr:
                call con_restore
                xor a
                ld (CUR_COL), a
                jr con_row_down

con_lf:
                call con_restore
con_row_down:
                ld a, (CUR_ROW)
                inc a
                cp VIDEO_ROWS
                jr c, con_row_ok
                call con_base
                ld d, h
                ld e, l
                ld l, VIDEO_COLS
                ld bc, VIDEO_SIZE - VIDEO_COLS
                ldir
                ld a, VIDEO_ROWS - 1
con_row_ok:
                ld (CUR_ROW), a
                xor a
                ld (CUR_COL), a
                call con_addr
                ld bc, VIDEO_COLS
                call con_fill
                call con_grab
                call con_apply
                jp con_leave

con_bs:
                call con_restore
                ld a, (CUR_COL)
                or a
                jr z, con_bs_stay
                dec a
                ld (CUR_COL), a
con_bs_stay:
                call con_grab
                call con_apply
                jp con_leave

con_esc:
                ld a, c
                cp '7'
                jr z, con_save
                cp '8'
                jr z, con_restore_cur
                cp '['
                jr z, con_arm_csi
                xor a
                ld (ANSI_STATE), a
                jp con_leave

con_save:
                ld a, (CUR_ROW)
                ld (ESC_ROW), a
                ld a, (CUR_COL)
                ld (ESC_COL), a
                xor a
                ld (ANSI_STATE), a
                jp con_leave

con_restore_cur:
                call con_restore
                ld a, (ESC_ROW)
                ld (CUR_ROW), a
                ld a, (ESC_COL)
                ld (CUR_COL), a
                call con_grab
                call con_apply
                xor a
                ld (ANSI_STATE), a
                jp con_leave

con_arm_csi:
                xor a
                ld (ANSI_P0), a
                ld (ANSI_P1), a
                ld (ANSI_N), a
                ld (ANSI_ACC), a
                ld (ANSI_BAD), a
                ld a, ANSI_CSI
                ld (ANSI_STATE), a
                jp con_leave

; C = next CSI byte.
con_csi:
                ld a, c
                cp 1Bh
                jp z, con_arm_esc
                cp '0'
                jr c, con_csi_other
                cp '9' + 1
                jr c, con_digit
con_csi_other:
                cp ';'
                jr z, con_semi
                cp 20h
                jr c, con_csi_endbad
                cp 40h
                jr c, con_csi_mark
                cp 7Fh
                jr c, con_final
con_csi_endbad:
                call con_csi_mark
                jr con_final_skip
con_csi_mark:
                ld a, 1
                ld (ANSI_BAD), a
                ret

con_digit:
                call con_acc
                ret

con_semi:
                call con_store
                xor a
                ld (ANSI_ACC), a
                ret

con_final:
                call con_store
                ld a, (ANSI_BAD)
                or a
                jr nz, con_final_skip
                call con_exec
con_final_skip:
                xor a
                ld (ANSI_STATE), a
                ld (ANSI_N), a
                ld (ANSI_ACC), a
                ld (ANSI_BAD), a
                ret

con_acc:
                ld a, (ANSI_ACC)
                cp 26
                jr nc, con_sat
                ld b, a
                add a, a
                add a, a
                add a, b
                add a, a
                add a, c
                sub '0'
                jr nc, con_acc_ok
con_sat:
                ld a, 255
con_acc_ok:
                ld (ANSI_ACC), a
                ret

con_store:
                ld a, (ANSI_N)
                cp 2
                jr nc, con_csi_mark
                ld hl, ANSI_P0
                ld e, a
                ld d, 0
                add hl, de
                ld a, (ANSI_ACC)
                ld (hl), a
                ld hl, ANSI_N
                inc (hl)
                ret

con_exec:
                ld a, c
                cp 'A'
                jr z, con_up
                cp 'B'
                jr z, con_down
                cp 'C'
                jr z, con_right
                cp 'D'
                jr z, con_left
                cp 'H'
                jr z, con_cup
                cp 'f'
                jr z, con_cup
                cp 'J'
                jp z, con_ed
                cp 'K'
                jp z, con_el
                ret

con_up:
                call con_count
                ld b, a
                call con_restore
con_up_loop:
                ld a, (CUR_ROW)
                or a
                jr z, con_moved
                dec a
                ld (CUR_ROW), a
                djnz con_up_loop
                jr con_moved

con_down:
                call con_count
                ld b, a
                call con_restore
con_down_loop:
                ld a, (CUR_ROW)
                cp VIDEO_ROWS - 1
                jr z, con_moved
                inc a
                ld (CUR_ROW), a
                djnz con_down_loop
                jr con_moved

con_right:
                call con_count
                ld b, a
                call con_restore
con_right_loop:
                ld a, (CUR_COL)
                cp VIDEO_COLS - 1
                jr z, con_moved
                inc a
                ld (CUR_COL), a
                djnz con_right_loop
                jr con_moved

con_left:
                call con_count
                ld b, a
                call con_restore
con_left_loop:
                ld a, (CUR_COL)
                or a
                jr z, con_moved
                dec a
                ld (CUR_COL), a
                djnz con_left_loop
con_moved:
                call con_grab
                jp con_apply

; Missing and zero both move by one.
con_count:
                ld a, (ANSI_P0)
                or a
                ret nz
                ld a, 1
                ret

con_cup:
                call con_restore
                ld a, (ANSI_P0)
                or a
                jr nz, con_cup_row
                ld a, 1
con_cup_row:
                dec a
                cp VIDEO_ROWS
                jr c, con_cup_row_ok
                ld a, VIDEO_ROWS - 1
con_cup_row_ok:
                ld (CUR_ROW), a
                ld a, (ANSI_N)
                cp 2
                jr c, con_cup_col_default
                ld a, (ANSI_P1)
                or a
                jr nz, con_cup_col
con_cup_col_default:
                ld a, 1
con_cup_col:
                dec a
                cp VIDEO_COLS
                jr c, con_cup_col_ok
                ld a, VIDEO_COLS - 1
con_cup_col_ok:
                ld (CUR_COL), a
                jr con_moved

con_ed:
                ld a, (ANSI_P0)
                cp 3
                ret nc
                push af
                call con_restore
                pop af
                or a
                jr z, con_ed_forward
                dec a
                jr z, con_ed_back
                call con_base
                ld bc, VIDEO_SIZE
                call con_fill
                jr con_ed_done
con_ed_forward:
                call con_addr
                push hl
                call con_base
                add a, VIDEO_SIZE >> 8
                ld h, a
                pop de
                or a
                sbc hl, de
                ld b, h
                ld c, l
                ex de, hl
                call con_fill
                jr con_ed_done
con_ed_back:
                call con_base
                push hl
                call con_addr
                pop de
                or a
                sbc hl, de
                inc hl
                ld b, h
                ld c, l
                ex de, hl
                call con_fill
con_ed_done:
                ld a, ' '
                ld (CUR_UNDER), a
                jp con_apply

con_el:
                ld a, (ANSI_P0)
                cp 3
                ret nc
                push af
                call con_restore
                pop af
                ld b, a
                ld a, (CUR_ROW)
                ld c, a
                ld a, b
                or a
                jr z, con_el_forward
                dec a
                jr z, con_el_back
                ld b, 0
                ld a, VIDEO_COLS
                jr con_el_span
con_el_forward:
                ld a, (CUR_COL)
                ld b, a
                ld a, VIDEO_COLS
                sub b
                jr con_el_span
con_el_back:
                ld b, 0
                ld a, (CUR_COL)
                inc a
con_el_span:
                push af
                ld a, c
                call con_row_only
                pop af
                push af
                ld a, b
                add a, l
                ld l, a
                jr nc, con_el_no_carry
                inc h
con_el_no_carry:
                pop af
                ld c, a
                ld b, 0
                call con_fill
                ld a, ' '
                ld (CUR_UNDER), a
                jp con_apply

con_fill:
                ld a, c
                or b
                ret z
                ld (hl), ' '
                dec bc
                inc hl
                jr con_fill

con_advance:
                ld a, (CUR_COL)
                inc a
                cp VIDEO_COLS
                jr c, con_set_col
                xor a
                ld (CUR_COL), a
                ld a, (CUR_ROW)
                inc a
                cp VIDEO_ROWS
                jr c, con_set_row
                ld a, VIDEO_ROWS - 1
                ld (CUR_ROW), a
                ld a, VIDEO_COLS - 1
con_set_col:
                ld (CUR_COL), a
                ret
con_set_row:
                ld (CUR_ROW), a
                ret

con_restore:
                ld a, (CUR_SHOWN)
                or a
                ret z
                call con_addr
                ld a, (CUR_UNDER)
                ld (hl), a
                xor a
                ld (CUR_SHOWN), a
                ret

con_grab:
                call con_addr
                ld a, (hl)
                ld (CUR_UNDER), a
                xor a
                ld (CUR_SHOWN), a
                ret

con_apply:
                ld a, (CUR_PHASE)
                or a
                jr z, con_hide
                call con_addr
                ld (hl), CURSOR_BLOCK
                ld a, 1
                ld (CUR_SHOWN), a
                ret
con_hide:
                call con_addr
                ld a, (CUR_UNDER)
                ld (hl), a
                xor a
                ld (CUR_SHOWN), a
                ret

; HL = video address of the cursor.
con_addr:
                ld a, (CUR_ROW)
                call con_row_only
                ld a, (CUR_COL)
                ld e, a
                ld d, 0
                add hl, de
                ret

con_row_only:
                ld l, a
                ld h, 0
                add hl, hl
                add hl, hl
                add hl, hl
                add hl, hl
                add hl, hl
                add hl, hl
                ld a, (CON_PLANE_CUR)
                add a, h
                ld h, a
                ret

; HL = the bound plane, A = its page.
con_base:
                ld a, (CON_PLANE_CUR)
                ld h, a
                ld l, 0
                ret

; D = console. Interrupts off. Keeps BC, DE and HL.
con_bind:
                push bc
                push hl
                push de
                call con_unbind
                pop de
                push de
                ld a, d
                ld (CON_BOUND), a
                call con_block
                ld de, CUR_ROW
                ld bc, 14
                ldir
                ld a, (CON_BOUND)
                add a, CON_PLANE & 0FFh
                ld l, a
                ld h, CON_PLANE >> 8
                ld a, (hl)
                ld (CON_PLANE_CUR), a
                pop de
                pop hl
                pop bc
                ret

; Saves the bound console's state and unbinds it.
con_unbind:
                ld a, (CON_BOUND)
                inc a
                ret z
                dec a
                call con_block
                ex de, hl
                ld hl, CUR_ROW
                ld bc, 14
                ldir
                ld a, 0FFh
                ld (CON_BOUND), a
                ret

; A = console. HL = its saved state.
con_block:
                ld hl, CON_BLOCK
                or a
                ret z
                ld l, (CON_BLOCK + 14) & 0FFh
                ret

; A = console. ISR only. Swaps it into video RAM, drops typed-ahead keys, and
; asks init for a shell the first time the console is shown.
con_show:
                cp NCON
                ret nc
                ld hl, CON_ACTIVE
                cp (hl)
                ret z
                ld e, a
                push de
                call con_unbind
                pop de
                ld a, e
                add a, CON_PLANE & 0FFh
                ld l, a
                ld h, CON_PLANE >> 8
                ld d, (hl)
                ld (hl), VIDEO_BASE >> 8
                ld a, (CON_ACTIVE)
                add a, CON_PLANE & 0FFh
                ld l, a
                ld (hl), d
                ld a, e
                ld (CON_ACTIVE), a
                ld e, 0
                ld hl, VIDEO_BASE
                ld bc, VIDEO_SIZE
con_swap:
                ld a, (de)
                ldi
                dec hl
                ld (hl), a
                inc hl
                jp pe, con_swap
                ld a, (KBD_HEAD)
                ld (KBD_TAIL), a
                xor a
                ld (KBD_PREFIX), a
                ld a, (CON_ACTIVE)
                ld e, a
                add a, CON_STATE & 0FFh
                ld l, a
                ld h, CON_STATE >> 8
                ld a, (hl)
                or a
                ret nz
                inc (hl)
                ld a, e
                inc a
                ld hl, CON_WANT
                or (hl)
                ld (hl), a
                ret

console_blink:
                ld a, (CON_ACTIVE)
                ld d, a
                ld a, (CON_BOUND)
                cp d
                call nz, con_bind
; BLINK_DIV bit 7 enables the caret. A console's first printed glyph sets it,
; so no caret shows before its shell prints sh>. It toggles every 7 ticks.
                ld hl, BLINK_DIV
                bit 7, (hl)
                ret z
                inc (hl)
                ld a, (hl)
                cp 80h + 7
                ret c
                ld (hl), 80h
                ld a, (CUR_PHASE)
                xor 1
                ld (CUR_PHASE), a
                jp con_apply
