                include "cp500.inc"

                org ORIGIN

                ld c, SYS_WRITE
                ld de, 1
                ld hl, msg
                ld ix, 2
                rst 08h
                ld c, SYS_EXIT
                ld de, 0
                rst 08h

msg:            db "rc"
