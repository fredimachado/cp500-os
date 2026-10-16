                include "cp500.inc"

                org ORIGIN

                ld (argv), hl
                ld a, 1
                call arg_ptr
                jp c, fail_inval
                push hl
                ld a, 2
                call arg_ptr
                jp c, fail_inval
                ld (dst), hl
                pop hl
                ld c, SYS_OPEN
                ex de, hl
                ld b, O_READ
                rst 08h
                jp c, fail
                ld a, l
                ld (srcfd), a
                ld c, SYS_OPEN
                ld hl, (dst)
                ex de, hl
                ld b, O_WRITE | O_CREATE | O_TRUNC
                rst 08h
                jp c, fail
                ld a, l
                ld (dstfd), a
cp_read:
                ld c, SYS_READ
                ld a, (srcfd)
                ld e, a
                ld d, 0
                ld hl, buf
                ld ix, 256
                rst 08h
                jp c, fail
                ld a, h
                or l
                jp z, exit0
                push hl
                pop ix
                ld c, SYS_WRITE
                ld a, (dstfd)
                ld e, a
                ld d, 0
                ld hl, buf
                rst 08h
                jp c, fail
                jr cp_read

fail_inval:
                ld a, EINVAL
                jp fail

srcfd:          db 0
dstfd:          db 0
dst:            dw 0

                include "run.inc"

buf:
