                include "cp500.inc"

                org ORIGIN

                ld (argv), hl
                ld a, 1
                call arg_ptr
                ld a, EINVAL
                jp c, fail
                push hl
                ld a, 2
                call arg_ptr
                ld a, EINVAL
                jp c, fail
                pop de
                ld c, SYS_RENAME
                rst 08h
                jp c, fail
                jp exit0

                include "run.inc"
