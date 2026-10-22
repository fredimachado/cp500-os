; Decimal input and output for the user programs. putc comes from run.inc.

; HL = text. Digits up to a NUL or a '/', which stays at HL. DE = value.
; Carry and A = EINVAL on any other character or when the value passes 65535.
parse_u16:
                ld de, 0
pu:
                ld a, (hl)
                or a
                ret z
                cp '/'
                ret z
                cp '0'
                jr c, pu_bad
                cp '9' + 1
                jr nc, pu_bad
                sub '0'
                push hl
                ld h, d
                ld l, e
                add hl, hl              ; * 2
                jr c, pu_over
                add hl, hl              ; * 4
                jr c, pu_over
                add hl, de              ; * 5
                jr c, pu_over
                add hl, hl              ; * 10
                jr c, pu_over
                ld e, a
                ld d, 0
                add hl, de
                jr c, pu_over
                ex de, hl
                pop hl
                inc hl
                jr pu
pu_over:
                pop hl
pu_bad:
                ld a, EINVAL
                scf
                ret

; HL = value, B = minimum width. Decimal digits through putc, no leading zeros,
; right-aligned in B columns with spaces. Clobbers AF, BC, DE, HL.
put_dec:
                ld b, 0
put_dec_w:
                ld a, b
                ld (pd_min), a
                ld de, pd_buf
                ld bc, 10000
                call pd_digit
                ld bc, 1000
                call pd_digit
                ld bc, 100
                call pd_digit
                ld bc, 10
                call pd_digit
                ld bc, 1
                call pd_digit
                ld hl, pd_buf
                ld b, 4
pd_zero:
                ld a, (hl)
                cp '0'
                jr nz, pd_pad
                inc hl
                djnz pd_zero
pd_pad:
                ld a, b                 ; digits left = B + 1; the units digit always prints
                inc a
                ld c, a
                ld a, (pd_min)
                sub c
                jr c, pd_out
                jr z, pd_out
                ld b, a
pd_sp:
                ld a, ' '
                push bc
                push hl
                call putc
                pop hl
                pop bc
                djnz pd_sp
pd_out:
                ld a, (hl)
                push bc
                push hl
                call putc
                pop hl
                pop bc
                inc hl
                dec c
                jr nz, pd_out
                ret

; DE = next digit slot, BC = place value, HL = remainder below 10 * BC.
; Stores one ASCII digit at (DE) and advances DE. HL becomes the new remainder.
pd_digit:
                ld a, '0'
pd_sub:
                or a
                sbc hl, bc
                jr c, pd_back
                inc a
                jr pd_sub
pd_back:
                add hl, bc
                ld (de), a
                inc de
                ret

pd_min:         db 0
pd_buf:         ds 5, 0
