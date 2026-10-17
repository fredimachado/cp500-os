; DE = block, HL = buffer. Carry clear moves one sector.
; Carry set returns A = EIO. EI on both returns. DE and HL are restored.
; DISK_WAIT is never set. The transfer is the polled DRQ loop, not WAIT plus NMI.

floppy_read:
                ld a, FDC_CMD_READ
                jr floppy_io

floppy_write:
                ld a, FDC_CMD_WRITE

floppy_io:
                ld (io_cmd), a
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
                ld a, (io_cmd)
                out (FDC_COMMAND), a
                pop hl
                push hl
                ld de, 0
                ld bc, FDC_DATA         ; B is 0, so INI/OUTI moves 256 bytes
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
                ld a, (io_cmd)
                cp FDC_CMD_WRITE
                jr z, fr_out
                ini
                jr nz, fr_poll
                jr fr_status
fr_out:
                outi
                jr nz, fr_poll
fr_status:
                in a, (FDC_STATUS)
                ld c, a
                and FDC_NOT_READY | FDC_CRC_ERROR | FDC_NOT_FOUND | FDC_LOST_DATA
                jr nz, fr_fail
                ld a, (io_cmd)
                cp FDC_CMD_WRITE
                jr nz, fr_ok
                ld a, c
                and FDC_WRITE_PROT | FDC_WRITE_FAULT
                jr nz, fr_fail
fr_ok:
                xor a
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

io_cmd:         db 0

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
