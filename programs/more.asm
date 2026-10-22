; One screen is 16 rows: 15 lines and the row the cursor waits on. Space shows the next screen.

                include "cp500.inc"

                org ORIGIN

                ld (argv), hl
                ld a, 1
                call arg_ptr
                ld a, EINVAL
                jp c, fail
                ld c, SYS_OPEN
                ex de, hl
                ld b, O_READ
                rst 08h
                jp c, fail
                ld a, l
                ld (fd), a
                xor a
                ld (lines), a
                ld (col), a
mo_byte:
                ld c, SYS_READ
                ld a, (fd)
                ld e, a
                ld d, 0
                ld hl, ch
                ld ix, 1
                rst 08h
                jp c, fail
                ld a, h
                or l
                jr z, mo_end
                ld a, (ch)
                cp 0Ah
                jr nz, mo_out
                ld a, 0Dh
mo_out:         call putc
                ld a, (ch)
                cp 0Dh
                jr z, mo_nl
                cp 0Ah
                jr z, mo_nl
                ld hl, col
                inc (hl)
                ld a, (hl)
                cp 64
                jr c, mo_byte
mo_nl:
                xor a
                ld (col), a
                ld hl, lines
                inc (hl)
                ld a, (hl)
                cp 15
                jr c, mo_byte
                call mo_wait
                xor a
                ld (lines), a
                jr mo_byte
mo_end:
                jp exit0

mo_wait:
                ld c, SYS_READ
                ld de, 0
                ld hl, ch
                ld ix, 1
                rst 08h
                ret c
                ld a, (ch)
                cp ' '
                jr nz, mo_wait
                ret

fd:             db 0
lines:          db 0
col:            db 0

                include "run.inc"
