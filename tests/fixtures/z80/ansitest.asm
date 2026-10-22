; Console ANSI self-test, once the boot banner. Clears the screen, then leaves
; "ansi/" on row 1 and "XX" on row 3 when clear, home, save and restore,
; position and erase to end of line all work. The prompt follows on row 4.

                include "cp500.inc"

                org ORIGIN

                ld c, SYS_WRITE
                ld de, 1
                ld hl, seq
                ld ix, seq_end - seq
                rst 08h
                ld de, 0
                ld c, SYS_EXIT
                rst 08h

seq:
                db 1Bh, "[2J"
                db 1Bh, "[H"
                db "ansi"
                db 1Bh, "7"
                db 1Bh, "[3;1H"
                db "XXXX"
                db 1Bh, "[3;3H"
                db 1Bh, "[K"
                db 1Bh, "8"
                db "/"
                db 1Bh, "[3;1H"
seq_end:
