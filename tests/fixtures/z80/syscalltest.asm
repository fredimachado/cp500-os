                include "cp500.inc"

                org ORIGIN

                ld (argv), hl
                ld a, 1
                call arg_ptr
                jp c, exit_einval
                ld a, (hl)
                cp 'z'
                jp z, mode_z
                cp 's'
                jp z, mode_s
                cp 'u'
                jp z, mode_u
                cp 'm'
                jp z, mode_m
                cp 'a'
                jp z, mode_a
                cp 'f'
                jp z, mode_f
                cp 'b'
                jp z, mode_b
                cp 'd'
                jp z, mode_d
                cp 'r'
                jp z, mode_r
                jp exit_einval

mode_z:
                ld de, 0
                ld c, SYS_SLEEP
                rst 08h
                jp c, exit_a
                jp exit_ok

mode_s:
                ld de, tbuf
                ld c, SYS_UPTIME
                rst 08h
                jp c, exit_a
                ld hl, (tbuf)
                ld (t0), hl
                ld de, 4
                ld c, SYS_SLEEP
                rst 08h
                jp c, exit_a
                ld de, tbuf
                ld c, SYS_UPTIME
                rst 08h
                jp c, exit_a
                ld hl, (tbuf)
                ld de, (t0)
                or a
                sbc hl, de
                ld a, l
                cp 4
                jp nc, exit_ok
                ld c, SYS_EXIT
                ld de, 9
                rst 08h

mode_u:
                ld de, tbuf
                ld c, SYS_UPTIME
                rst 08h
                jp c, exit_a
                ld hl, (TICK_COUNT)
                ld de, (tbuf)
                or a
                sbc hl, de
                jp c, mode_u_bad
                ld a, l
                cp 30
                jp nc, mode_u_bad
                jp exit_ok
mode_u_bad:
                ld c, SYS_EXIT
                ld de, 9
                rst 08h

mode_m:
                ld de, minfo
                ld c, SYS_MEMINFO
                rst 08h
                jp c, exit_a
                call check_minfo
                jp exit_ret

mode_a:
                ld de, minfo
                ld c, SYS_MEMINFO
                rst 08h
                jp c, exit_a
                ld hl, (minfo)
                ld (free0), hl
                ld de, 1
                ld c, SYS_ALLOC
                rst 08h
                jp c, exit_a
                ld a, l
                or a
                jp nz, exit_bad
                ld (alloc_addr), hl
                ld de, minfo
                ld c, SYS_MEMINFO
                rst 08h
                jp c, exit_a
                ld hl, (minfo)
                ld de, (free0)
                or a
                sbc hl, de
                ld a, l
                inc a
                jp nz, exit_bad
                ld de, (alloc_addr)
                ld c, SYS_FREE
                rst 08h
                jp c, exit_a
                ld de, minfo
                ld c, SYS_MEMINFO
                rst 08h
                jp c, exit_a
                ld hl, (minfo)
                ld de, (free0)
                or a
                sbc hl, de
                jp nz, exit_bad
                jp exit_ok

mode_f:
                ld de, 1
                ld c, SYS_FREE
                rst 08h
                jp exit_a

mode_b:
                ld de, 8
                ld hl, 3
                ld c, SYS_DUP2
                rst 08h
                jp exit_a

mode_d:
                ld de, 1
                ld hl, 3
                ld c, SYS_DUP2
                rst 08h
                jp c, exit_a
                ld c, SYS_CLOSE
                ld e, 1
                ld d, 0
                rst 08h
                jp c, exit_a
                ld c, SYS_WRITE
                ld e, 3
                ld d, 0
                ld hl, qbyte
                ld ix, 1
                rst 08h
                jp c, exit_a
                ld c, SYS_WRITE
                ld e, 3
                ld hl, cr_ok
                ld ix, 3
                rst 08h
                jp exit_zero

mode_r:
                ld c, SYS_OPEN
                ld de, ser_path
                ld b, O_READ | O_WRITE
                rst 08h
                jp c, exit_a
                ld a, l
                ld (ser_fd), a
                ld e, a
                ld d, 0
                ld hl, 4
                ld c, SYS_DUP2
                rst 08h
                jp c, exit_a
                ld c, SYS_OPEN
                ld de, ser_path
                ld b, O_READ | O_WRITE
                rst 08h
                jp nc, exit_bad
                cp EBUSY
                jp nz, exit_a
                ld c, SYS_IOCTL
                ld a, (ser_fd)
                ld e, a
                ld d, 0
                ld hl, SER_GETCFG
                ld ix, cfg
                rst 08h
                jp c, exit_a
                ld c, SYS_CLOSE
                ld a, 4
                ld e, a
                ld d, 0
                rst 08h
                jp c, exit_a
                ld c, SYS_IOCTL
                ld a, (ser_fd)
                ld e, a
                ld d, 0
                ld hl, SER_GETCFG
                ld ix, cfg
                rst 08h
                jp c, exit_a
                ld c, SYS_CLOSE
                ld a, (ser_fd)
                ld e, a
                ld d, 0
                rst 08h
                jp c, exit_a
                jp exit_ok

check_minfo:
                ld hl, (minfo + 4)
                ld bc, 142
                or a
                sbc hl, bc
                jr nz, mi_bad
                ld hl, (minfo)
                ld de, (minfo + 4)
                or a
                sbc hl, de
                jr nc, mi_bad
                ld hl, (minfo)
                ld de, (minfo + 2)
                or a
                sbc hl, de
                jr c, mi_bad
                xor a
                ret
mi_bad:
                ld a, 9
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

exit_ret:
                or a
                jp z, exit_ok
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

ok_text:        db "ok"
cr_ok:          db 0Dh, "ok"
ser_path:       db "/dev/ser0", 0
qbyte:          db 'Q'
tbuf:           ds 4
t0:             dw 0
minfo:          ds 6
free0:          dw 0
alloc_addr:     dw 0
ser_fd:         db 0
cfg:            ds 8
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
