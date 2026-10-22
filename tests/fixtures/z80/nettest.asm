                include "cp500.inc"

                org ORIGIN

                ld (argv), hl
                ld a, 1
                call arg_ptr
                jr c, no_chip
                ld a, (hl)
                cp 'b'
                jp z, bad_call
                cp 't'
                jp z, bad_type

no_chip:
                ld c, SYS_SOCKET
                ld b, 1
                rst 08h
                jp c, exit_a
                jp exit_bad

bad_type:
                ld c, SYS_SOCKET
                ld b, 2
                rst 08h
                jp nc, exit_bad
                cp EINVAL
                jp exit_a
bad_call:
                ld c, 59h
                rst 08h
                jp nc, exit_bad
                cp EINVAL
                jp exit_a

exit_a:
                ld c, SYS_EXIT
                ld d, 0
                ld e, a
                rst 08h

exit_bad:
                ld c, SYS_EXIT
                ld de, 1
                rst 08h

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
