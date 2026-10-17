; Child of serboard: shared serial fd 3, second open is EBUSY.

                include "cp500.inc"

                org ORIGIN

                ld c, SYS_OPEN
                ld de, ser_path
                ld b, O_READ | O_WRITE
                rst 08h
                jp nc, exit_ebusy
                cp EBUSY
                jp nz, exit_a
                ld c, SYS_WRITE
                ld de, 3
                ld hl, letter
                ld ix, 1
                rst 08h
                jp c, exit_a
                ld c, SYS_EXIT
                ld de, 15
                rst 08h

exit_ebusy:
                ld c, SYS_EXIT
                ld de, 99
                rst 08h

exit_a:
                ld e, a
                ld d, 0
                ld c, SYS_EXIT
                rst 08h

ser_path:       db "/dev/ser0", 0
letter:         db "x"
