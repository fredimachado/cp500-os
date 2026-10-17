; Present-board integration test; exits 100 when the port behaves per contract.

                include "cp500.inc"

                org ORIGIN

                ld c, SYS_OPEN
                ld de, ser_path
                ld b, O_READ | O_WRITE
                rst 08h
                jp c, exit_a
                ld a, l
                ld (ser_fd), a
                ld c, SYS_IOCTL
                ld e, a
                ld d, 0
                ld hl, SER_GETCFG
                ld ix, cfg
                rst 08h
                jp c, exit_a
                call check_defaults
                jp nz, exit_bad
                ld c, SYS_OPEN
                ld de, ser_path
                ld b, O_READ | O_WRITE
                rst 08h
                jp nc, exit_bad
                cp EBUSY
                jp nz, exit_a
                ld hl, spawn_map
                ld (hl), 0
                inc hl
                ld (hl), 1
                inc hl
                ld (hl), 2
                inc hl
                ld a, (ser_fd)
                ld (hl), a
                inc hl
                ld a, 0FFh
                ld b, 4
sm_fill:
                ld (hl), a
                inc hl
                djnz sm_fill
                ld de, kid_path
                ld hl, kid_argv
                ld ix, spawn_map
                ld c, SYS_SPAWN
                rst 08h
                jp c, exit_a
                ld c, SYS_WAIT
                rst 08h
                jp c, exit_a
                ld a, l
                cp 15
                jp nz, exit_bad
                ld a, (ser_fd)
                ld e, a
                ld d, 0
                ld hl, bad_baud
                ld ix, cfg
                ld (ix), 10h
                ld c, SYS_IOCTL
                rst 08h
                jp nc, exit_bad
                cp EINVAL
                jp nz, exit_a
                ld c, SYS_IOCTL
                ld hl, SER_STATS
                ld ix, stats
                rst 08h
                jp c, exit_a
                call stats_zero
                jp nz, exit_bad
                ld c, SYS_IOCTL
                ld hl, SER_BREAK
                ld ix, break2
                rst 08h
                jp c, exit_a
                ld c, SYS_IOCTL
                ld hl, SER_GETLINES
                rst 08h
                jp c, exit_a
                ld c, SYS_CLOSE
                ld e, (ser_fd)
                ld d, 0
                rst 08h
                jp c, exit_a
                call wait_gap
                ld c, SYS_OPEN
                ld de, ser_path
                ld b, O_READ | O_WRITE
                rst 08h
                jp c, exit_a
                ld c, SYS_CLOSE
                ld e, l
                ld d, 0
                rst 08h
                ld c, SYS_EXIT
                ld de, 100
                rst 08h

exit_bad:
                ld c, SYS_EXIT
                ld de, 98
                rst 08h

exit_a:
                ld e, a
                ld d, 0
                ld c, SYS_EXIT
                rst 08h

check_defaults:
                ld hl, def_baud
                ld de, cfg
                ld b, 6
cd_loop:
                ld a, (de)
                cp (hl)
                jr nz, cd_fail
                inc hl
                inc de
                djnz cd_loop
                xor a
                ret
cd_fail:
                ld a, 1
                ret

stats_zero:
                ld hl, stats
                ld b, 8
sz_loop:
                ld a, (hl)
                or a
                jr nz, sz_fail
                inc hl
                djnz sz_loop
                xor a
                ret
sz_fail:
                ld a, 1
                ret

wait_gap:
                ld b, 120
wg_loop:
                ld c, SYS_YIELD
                rst 08h
                djnz wg_loop
                ret

ser_path:       db "/dev/ser0", 0
kid_path:       db "/lib/serkid.c5x", 0
ser_fd:         db 0
spawn_map:      ds 8, 0
kid_argv:       db 1, 0
kid_name:       db "serkid", 0
cfg:            ds 6, 0
stats:          ds 8, 0
break2:         dw 2
def_baud:       db 0Eh, 8, 0, 1, CFG_F_RTSCTS, 0
bad_baud:       db 0
