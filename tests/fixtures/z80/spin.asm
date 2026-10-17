; Counts forever without entering the kernel. The 32-bit count sits at offset 2.

                include "cp500.inc"

                org ORIGIN

                jr spin
count:          dw 0, 0
spin:
                ld hl, (count)
                inc hl
                ld (count), hl
                ld a, h
                or l
                jr nz, spin
                ld hl, (count + 2)
                inc hl
                ld (count + 2), hl
                jr spin
