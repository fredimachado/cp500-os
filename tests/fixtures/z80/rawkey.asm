; Puts its console in raw mode, prints ready, reads one byte and exits with it.
; A failed call exits with the error code.

                include "cp500.inc"

                org ORIGIN

                ld c, SYS_IOCTL
                ld de, 0
                ld hl, IOCTL_SETMODE
                ld ix, CON_RAW
                rst 08h
                jr c, quit
                ld c, SYS_WRITE
                ld de, 1
                ld hl, ready
                ld ix, ready_end - ready
                rst 08h
                ld c, SYS_READ
                ld de, 0
                ld hl, key
                ld ix, 1
                rst 08h
                jr c, quit
                ld a, (key)
quit:
                ld e, a
                ld d, 0
                ld c, SYS_EXIT
                rst 08h

ready:          db "ready", 0Dh
ready_end:
key:            db 0
