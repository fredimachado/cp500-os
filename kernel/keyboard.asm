; Matrix scan. Row n is the byte at KBD_BASE | (1 << n). Keys are active high.
; SHIFT is row 7 bit 0. Arrow keys expand to ESC [ B/D/C before the ring.

kbd_scan:
                ld hl, kbd_now
                ld c, 1
                ld b, 8
kbd_read:
                push hl
                ld h, KBD_BASE >> 8
                ld l, c
                ld a, (hl)
                pop hl
                ld (hl), a
                inc hl
                ld a, c
                add a, a
                ld c, a
                djnz kbd_read

                ld c, 0
kbd_row:
                push bc
                ld b, 0
                ld hl, kbd_now
                add hl, bc
                ld a, (hl)
                ld e, a
                ld hl, KBD_PREV
                add hl, bc
                ld a, (hl)
                and e
                ld d, a
                ld hl, KBD_ACCEPTED
                add hl, bc
                ld a, (hl)
                xor d
                and d
                ld (hl), d
                ld hl, kbd_fresh
                add hl, bc
                ld (hl), a
                ld hl, KBD_PREV
                add hl, bc
                ld (hl), e
                pop bc
                inc c
                ld a, c
                cp 8
                jr nz, kbd_row

                xor a
                ld (kbd_replaced), a
                ld c, 0
                ld hl, kbd_fresh
kbd_emit_row:
                ld a, (hl)
                push hl
                push bc
                ld b, 0
kbd_emit_bit:
                srl a
                jr nc, kbd_next_bit
                push af
                push bc
                call kbd_fresh_key
                pop bc
                pop af
kbd_next_bit:
                inc b
                ld d, a
                ld a, b
                cp 8
                ld a, d
                jr nz, kbd_emit_bit
                pop bc
                pop hl
                inc hl
                inc c
                ld a, c
                cp 8
                jr nz, kbd_emit_row

                ld a, (kbd_replaced)
                or a
                ret nz
                ld a, (KBD_REP_ROW)
                cp 0FFh
                ret z
                ld c, a
                ld hl, KBD_ACCEPTED
                ld b, 0
                add hl, bc
                ld a, (KBD_REP_COL)
                ld b, a
                ld a, 1
kbd_shift_mask:
                dec b
                jp m, kbd_have_mask
                add a, a
                jr kbd_shift_mask
kbd_have_mask:
                and (hl)
                jr nz, kbd_still_down
                ld a, 0FFh
                ld (KBD_REP_ROW), a
                ret
kbd_still_down:
                ld hl, KBD_REP_AGE
                inc (hl)
                ld a, (hl)
                cp 15
                ret c
                ld (hl), 12
                ld a, (KBD_REP_ROW)
                ld c, a
                ld a, (KBD_REP_COL)
                ld b, a
                call kbd_lookup
                ret

; C = row, B = column.
kbd_fresh_key:
                call kbd_lookup
                ret c
                ld a, c
                ld (KBD_REP_ROW), a
                ld a, b
                ld (KBD_REP_COL), a
                xor a
                ld (KBD_REP_AGE), a
                ld a, 1
                ld (kbd_replaced), a
                ret

; Carry set when the cell is dropped. C and B are kept.
kbd_lookup:
                push bc
                ld a, (KBD_ACCEPTED + 7)
                and 1
                ld hl, KBD_UNSHIFTED
                jr z, kbd_picked
                ld hl, KBD_SHIFTED
kbd_picked:
                ld a, c
                add a, a
                add a, a
                add a, a
                add a, b
                ld e, a
                ld d, 0
                add hl, de
                ld a, (hl)
                pop bc
                or a
                scf
                ret z
                cp K_BREAK
                jr c, kbd_arrow
                push bc
                call kbd_key
                pop bc
                ret

; A = table byte. Carry when the key must not auto-repeat.
kbd_key:
                ld hl, KBD_PREFIX
                ld e, (hl)
                ld (hl), 0
                cp K_CLEAR
                jr nz, kbd_not_clear
                ld (hl), a
                scf
                ret
kbd_not_clear:
                ld c, a
                ld a, (CON_ACTIVE)
                add a, CON_MODE & 0FFh
                ld l, a
                ld a, c
                cp K_BREAK
                jr z, kbd_break
                ld a, e
                cp K_CLEAR
                ld a, c
                jp nz, kbd_put
                sub '1'
                cp NCON
                ld a, c
                jp nc, kbd_put
                sub '1'
                call con_show
                scf
                ret

; HL = CON_MODE of the shown console. Raw mode reads BREAK as a key;
; otherwise it ends the foreground task, if there is one.
kbd_break:
                bit 0, (hl)
                ld a, KEY_BREAK
                jp nz, kbd_put
                dec l
                dec l
                ld a, (hl)
                or a
                call nz, kill_mark
                scf
                ret

kbd_arrow:
                dec a
                ld e, a
                ld d, 0
                ld hl, kbd_arrow_final
                add hl, de
                ld a, (hl)
                push af
                call kbd_room3
                jr nc, kbd_arrow_send
                pop af
                scf
                ret
kbd_arrow_send:
                ld a, 1Bh
                call kbd_put
                ld a, '['
                call kbd_put
                pop af
                call kbd_put
                or a
                ret

; Carry set when fewer than 3 slots are free.
kbd_room3:
                ld a, (KBD_HEAD)
                ld l, a
                ld a, (KBD_TAIL)
                ld h, a
                ld a, l
                sub h
                and KBD_RING_SIZE - 1
                cp KBD_RING_SIZE - 3
                ccf
                ret

; A = byte. Carry set when the ring is full.
kbd_put:
                push bc
                ld c, a
                ld a, (KBD_HEAD)
                ld b, a
                inc a
                and KBD_RING_SIZE - 1
                ld l, a
                ld a, (KBD_TAIL)
                cp l
                jr z, kbd_full
                ld a, b
                ld l, a
                ld h, 0
                ld de, KBD_RING
                add hl, de
                ld (hl), c
                ld a, b
                inc a
                and KBD_RING_SIZE - 1
                ld (KBD_HEAD), a
                pop bc
                or a
                ret
kbd_full:
                pop bc
                scf
                ret

; Carry set and A = byte, or carry clear when the ring is empty.
kbd_get:
                ld a, (KBD_HEAD)
                ld l, a
                ld a, (KBD_TAIL)
                cp l
                ret z
                ld l, a
                ld h, 0
                ld de, KBD_RING
                add hl, de
                ld a, (hl)
                ld c, a
                ld a, (KBD_TAIL)
                inc a
                and KBD_RING_SIZE - 1
                ld (KBD_TAIL), a
                ld a, c
                scf
                ret

                kvar kbd_now, 8
                kvar kbd_fresh, 8
                kvar kbd_replaced, 1

kbd_arrow_final:
                db 'B', 'D', 'C'
