                include "cp500.inc"

                org ORIGIN

                ld (argv), hl
                ld a, 1
                call arg_ptr
                ld a, EINVAL
                jp c, fail
                ld c, SYS_MKDIR
                ex de, hl
                rst 08h
                jp c, fail
                jp exit0

                include "run.inc"
