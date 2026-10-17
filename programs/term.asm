; /bin/term — Hayes modem terminal (milestone 6). Stub opens ser0 only until completed.

                include "cp500.inc"

                org ORIGIN

term:
                ld c, SYS_OPEN
                ld de, ser_path
                ld b, O_READ | O_WRITE
                rst 08h
                jp c, fail
                ld c, SYS_EXIT
                ld de, 0
                rst 08h

                include "run.inc"

ser_path:       db "/dev/ser0", 0
