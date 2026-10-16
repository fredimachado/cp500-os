; DE = block, HL = destination. Carry clear copies one sector.
; Carry set returns A = EIO. EI on both returns. DE and HL are restored.

floppy_read:
                push de
                push hl
                di
                ld h, d
                ld l, e
                ld a, (VOL_SPT)
                call div168
                inc a
                ld c, a
                ld a, (VOL_SIDES)
                dec a
                jr z, fr_side0
                ld a, l
                and 1
                ld b, a
                srl h
                rr l
                jr fr_track
fr_side0:
                ld b, 0
fr_track:
                ld a, h
                or a
                jr nz, fr_fail
                ld a, b
                add a, a
                add a, a
                add a, a
                add a, a
                or DISK_DRIVE0 | DISK_MFM
                out (PORT_DISK), a
                ld a, l
                out (FDC_DATA), a
                ld a, FDC_CMD_SEEK | FDC_HEAD_LOAD | FDC_STEP_30MS
                out (FDC_COMMAND), a
                ld de, 0
fr_seek:
                in a, (FDC_STATUS)
                and FDC_BUSY
                jr z, fr_sought
                dec de
                ld a, d
                or e
                jr nz, fr_seek
                jr fr_fail
fr_sought:
                ld a, c
                out (FDC_SECTOR), a
                ld a, FDC_CMD_READ
                out (FDC_COMMAND), a
                pop hl
                push hl
                ld de, 0
                ld bc, FDC_DATA         ; B is 0, so INI moves 256 bytes
fr_poll:
                in a, (FDC_STATUS)
                rrca
                jr nc, fr_fail
                rrca
                jr c, fr_byte
                dec de
                ld a, d
                or e
                jr nz, fr_poll
                jr fr_fail
fr_byte:
                ini
                jr nz, fr_poll
                in a, (FDC_STATUS)
                and FDC_NOT_READY | FDC_CRC_ERROR | FDC_NOT_FOUND | FDC_LOST_DATA
                jr nz, fr_fail
                pop hl
                pop de
                ei
                ret

fr_fail:
                ld a, EIO
                scf
                pop hl
                pop de
                ei
                ret

; HL / A. HL = quotient, A = remainder. The carry out of RLA is the 9th remainder bit.
div168:
                ld e, a
                xor a
                ld b, 16
div_bit:
                add hl, hl
                rla
                jr c, div_sub
                cp e
                jr c, div_next
div_sub:
                sub e
                inc l
div_next:
                djnz div_bit
                ret
