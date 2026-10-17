; Stats /home/note forever. Each correct size bumps the count at offset 2; a
; wrong answer prints BAD and exits 9.

                include "cp500.inc"

                org ORIGIN

                jr again
count:          dw 0
again:
                ld c, SYS_STAT
                ld de, path
                ld hl, st
                rst 08h
                jr c, bad
                ld a, (st + 4)
                cp 5
                jr nz, bad
                ld hl, (count)
                inc hl
                ld (count), hl
                jr again
bad:
                ld c, SYS_WRITE
                ld de, 1
                ld hl, bad_text
                ld ix, 4
                rst 08h
                ld c, SYS_EXIT
                ld de, 9
                rst 08h

path:           db "/home/note", 0
bad_text:       db "BAD", 0Dh
st:             ds 16, 0
