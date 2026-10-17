; /lib/sertest.c5x — serial open and ioctl probes for milestone 6 tests.

                include "cp500.inc"

                org ORIGIN

                ld (argv), hl
                ld a, 1
                call arg_ptr
                jr c, open_default
                ld a, (hl)
                cp 'c'
                jr z, open_create
                cp 't'
                jr z, open_trunc
                cp 'a'
                jr z, open_append
                cp 'x'
                jr z, open_excl
                cp 'i'
                jr z, ioctl_console
                jp open_default

open_create:
                ld b, O_WRITE | O_CREATE
                jr open_dev
open_trunc:
                ld b, O_WRITE | O_TRUNC
                jr open_dev
open_append:
                ld b, O_WRITE | O_APPEND
                jr open_dev
open_excl:
                ld b, O_WRITE | O_CREATE | O_EXCL
                jr open_dev

open_default:
                ld b, O_READ | O_WRITE
open_dev:
                ld c, SYS_OPEN
                ld de, ser_path
                rst 08h
                jp c, exit_a
                ld c, SYS_EXIT
                ld de, 100
                rst 08h

ioctl_console:
                ld c, SYS_IOCTL
                ld de, 1
                ld hl, SER_GETCFG
                ld ix, cfg
                rst 08h
                jp c, exit_a
                ld c, SYS_EXIT
                ld de, 0
                rst 08h

exit_a:
                ld e, a
                ld d, 0
                ld c, SYS_EXIT
                rst 08h

ser_path:       db "/dev/ser0", 0
cfg:            ds 6, 0

argv:           dw 0

arg_ptr:
                ld hl, (argv)
                ld b, (hl)
                cp b
                ccf
                ret c
                inc hl
                inc hl
                ld b, a
                inc b
ap_skip:
                dec b
                ret z
ap_ch:
                ld a, (hl)
                inc hl
                or a
                jr nz, ap_ch
                jr ap_skip
