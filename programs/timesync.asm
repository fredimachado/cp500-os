; timesync [host]. RFC 868 on TCP port 37.

                include "cp500.inc"

                org ORIGIN

                ld (argv), hl
                ld a, (hl)
                cp 2
                jr c, ts_res
                ld a, 1
                call arg_ptr
                push hl
                pop de
                jr ts_go
ts_res:
                ld de, def_host
ts_go:
                ld hl, (argv)
                ld a, (hl)
                cp 2
                jr nc, ts_custom
                ld hl, conn
                ld (hl), 10
                inc hl
                ld (hl), 0
                inc hl
                ld (hl), 2
                inc hl
                ld (hl), 2
                jr ts_port
ts_custom:
                ld a, 1
                call arg_ptr
                push hl
                pop de
                ld hl, conn
                call parse_ip
                jp nc, ts_badip
                jr ts_port
ts_badip:
                ld a, EINVAL
                jp fail
ts_port:
                ld hl, 37
                ld a, h
                ld (conn + 4), a
                ld a, l
                ld (conn + 5), a
                xor a
                ld c, SYS_SOCKET
                ld b, 1
                rst 08h
                jp c, fail
                ld a, l
                ld e, a
                ld (sfd), a
                ld c, SYS_CONNECT
                ld e, a
                ld hl, conn
                rst 08h
                jp c, fail
                ld a, (sfd)
                ld e, a
                ld d, 0
                ld hl, raw
                ld ix, 4
                ld b, 0
                ld c, SYS_RECV
                rst 08h
                jp c, fail
                ld a, h
                or a
                jr nz, ts_eio
                ld a, l
                cp 4
                jr z, ts_got
ts_eio:
                ld a, EIO
                jp fail
ts_got:
                call fix_time
                or a
                ld c, SYS_SETTIME
                ld de, t0
                rst 08h
                jp c, fail
                ld hl, msg_ok
                call puts
                call cr
                jp exit0

fix_time:
                ld hl, raw + 3
                ld a, (hl)
                sub 80h
                ld (t0), a
                dec hl
                ld a, (hl)
                sbc a, 24h
                ld (t0 + 1), a
                dec hl
                ld a, (hl)
                sbc a, 79h
                ld (t0 + 2), a
                dec hl
                ld a, (hl)
                sbc a, 96h
                ld (t0 + 3), a
                or a
                ret

                include "ipdot.inc"

def_host:       db "10.0.2.2", 0
msg_ok:         db "TIME OK", 0
sfd:            db 0
conn:           ds 6, 0
ipbuf:          ds 4, 0
raw:            ds 4, 0
t0:             ds 4, 0

                include "run.inc"
