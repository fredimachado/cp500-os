; kill id. The id is 1-7; the kernel answers EINVAL for anything else, and EBUSY
; for a task it will not stop.

                include "cp500.inc"

                org ORIGIN

                ld (argv), hl
                ld a, 1
                call arg_ptr
                ld a, EINVAL
                jp c, fail
                call parse_u16
                jp c, fail
                ld a, d
                or a
                jr z, kill_go
                ld a, EINVAL
                jp fail
kill_go:
                ld c, SYS_KILL
                rst 08h
                jp c, fail
                jp exit0

                include "num.inc"
                include "run.inc"
