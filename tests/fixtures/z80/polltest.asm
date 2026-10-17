; /lib/polltest.c5x — poll syscall probes (arg: 0|t|k|p|n|b|w|f).

                include "cp500.inc"

                org ORIGIN

                ld (argv), hl
                ld a, 1
                call arg_ptr
                jp c, exit_einval
                ld a, (hl)
                cp '0'
                jp z, mode_0
                cp 't'
                jp z, mode_t
                cp 'k'
                jp z, mode_k
                cp 'p'
                jp z, mode_p
                cp 'n'
                jp z, mode_n
                cp 'b'
                jp z, mode_b
                cp 'w'
                jp z, mode_w
                cp 'f'
                jp z, mode_f
                jp exit_einval

mode_0:
                ld de, pfd0
                ld b, 1
                ld hl, 0
                call do_poll
                jp c, exit_a
                ld a, (pfd0 + 2)
                jp exit_ret

mode_t:
                ld hl, (TICK_COUNT)
                ld (t0), hl
                ld de, pfd0
                ld b, 1
                ld hl, 30
                call do_poll
                jp c, exit_a
                ld hl, (TICK_COUNT)
                ld de, (t0)
                or a
                sbc hl, de
                ld a, l
                cp 30
                jr nc, mode_t_ok
                ld c, SYS_EXIT
                ld de, 9
                rst 08h
mode_t_ok:
                ld a, (pfd0 + 2)
                jp exit_ret

mode_k:
                ld de, pfd0
                ld b, 1
                ld hl, POLL_FOREVER
                call do_poll
                jp c, exit_a
                ld a, (pfd0 + 2)
                jp exit_ret

mode_p:
                ld de, pipefds
                ld c, SYS_PIPE
                rst 08h
                jp c, exit_a
                ld a, (pipefds)
                ld (pfd_p), a
                ld c, SYS_CLOSE
                ld a, (pipefds_w)
                ld e, a
                ld d, 0
                rst 08h
                ld de, pfd_p
                ld b, 1
                ld hl, 0
                call do_poll
                jp c, exit_a
                ld a, (pfd_p + 2)
                jp exit_ret

mode_n:
                ld de, pfd_n
                ld b, 1
                ld hl, 0
                call do_poll
                jp c, exit_a
                ld a, (pfd_n + 2)
                jp exit_ret

mode_b:
                ld de, pfd0
                ld b, 9
                ld hl, 0
                call do_poll
                jp exit_a

mode_w:
                ld de, pfd_w
                ld b, 1
                ld hl, 0
                call do_poll
                jp c, exit_a
                ld a, (pfd_w + 2)
                jp exit_ret

mode_f:
                ld c, SYS_OPEN
                ld de, note_path
                ld b, O_READ
                rst 08h
                jp c, exit_a
                ld a, l
                ld (pfd_f), a
                ld de, pfd_f
                ld b, 1
                ld hl, 0
                call do_poll
                jp c, exit_a
                ld a, (pfd_f + 2)
                jp exit_ret

do_poll:
                ld c, SYS_POLL
                rst 08h
                ret

exit_ret:
                add a, 128
                ld e, a
                ld d, 0
                ld c, SYS_EXIT
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

pfd0:           db 0, POLLIN, 0
pfd_w:          db 1, POLLOUT, 0
pfd_n:          db 7, POLLIN, 0
pfd_p:          db 0, POLLIN, 0
pfd_f:          db 0, POLLIN | POLLOUT, 0
note_path:      db "/home/note", 0
t0:             dw 0
pipefds:        db 0
pipefds_w:      db 0

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
