                include "cp500.inc"

                org ORIGIN

                ld (argv), hl
                ld a, 1
                call arg_ptr
                jp c, fail_inval
                ld c, SYS_OPEN
                ex de, hl
                ld b, O_READ
                rst 08h
                jp c, fail
                ld a, l
                ld (fd), a
cat_read:
                ld c, SYS_READ
                ld a, (fd)
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
                ld de, 1
                ld hl, buf
                rst 08h
                jp c, fail
                jr cat_read

fail_inval:
                ld a, EINVAL
                jp fail

fd:             db 0

                include "run.inc"

buf:
