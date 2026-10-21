                include "cp500.inc"

                org ORIGIN

                ld (argv), hl
                ld a, 1
                call arg_ptr
                jp c, exit_einval
                ld a, (hl)
                cp 'n'
                jp z, mode_n
                cp 'c'
                jp z, mode_c
                cp 'p'
                jp z, mode_p
                cp 'f'
                jp z, mode_f
                jp exit_einval

mode_n:
                ld de, null_path
                ld b, O_READ | O_WRITE
                call do_open
                ld a, l
                ld (fd), a
                ld e, a
                ld d, 0
                ld hl, byte
                ld ix, 1
                ld c, SYS_WRITE
                rst 08h
                jp c, exit_a
                ld a, (fd)
                ld e, a
                ld hl, byte
                ld ix, 1
                ld c, SYS_READ
                rst 08h
                jp c, exit_a
                ld a, h
                or l
                jp nz, exit_bad
                jp exit_ok

mode_c:
                ld de, con_path
                ld b, O_WRITE
                call do_open
                ld e, l
                ld d, 0
                ld hl, con_ch
                ld ix, 1
                ld c, SYS_WRITE
                rst 08h
                jp c, exit_a
                jp exit_ok

mode_p:
                ld de, prn_path
                ld b, O_READ | O_WRITE
                call do_open
                ld a, l
                ld (fd), a
                ld e, a
                ld d, 0
                ld hl, byte
                ld ix, 1
                ld c, SYS_READ
                rst 08h
                jp c, exit_a
                ld a, (byte)
                or a
                jr z, prn_busy
                ld a, (fd)
                ld e, a
                ld d, 0
                ld hl, byte
                ld (hl), 'P'
                ld ix, 1
                ld c, SYS_WRITE
                rst 08h
                jp c, exit_a
                jp prn_done
prn_busy:
prn_done:
                ld hl, done
                ld ix, 4
                ld c, SYS_WRITE
                ld de, 1
                rst 08h
                jp exit_zero

mode_f:
                ld c, SYS_OPEN
                ld de, fd_path
                ld b, O_READ
                rst 08h
                jp nc, exit_bad
                jp exit_a

do_open:
                ld c, SYS_OPEN
                rst 08h
                jp c, exit_a
                ret

exit_ok:
                ld c, SYS_WRITE
                ld de, 1
                ld hl, ok_text
                ld ix, 2
                rst 08h
exit_zero:
                ld c, SYS_EXIT
                ld de, 0
                rst 08h

exit_bad:
                ld c, SYS_EXIT
                ld de, 9
                rst 08h

exit_a:
                ld e, a
                ld d, 0
                ld c, SYS_EXIT
                rst 08h

exit_einval:
                ld c, SYS_EXIT
                ld de, EINVAL
                rst 08h

null_path:      db "/dev/null", 0
con_path:       db "/dev/con", 0
prn_path:       db "/dev/prn", 0
fd_path:        db "/mnt/fd1", 0
byte:           db 'Z'
con_ch:         db 'C'
ok_text:        db "ok"
done:           db "done"
argv:           dw 0
fd:             db 0

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
