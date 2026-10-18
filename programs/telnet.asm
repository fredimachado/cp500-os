; telnet host [port]. Default port 23. Raw byte bridge.

                include "cp500.inc"

                org ORIGIN

                ld (argv), hl
                ld a, 1
                call arg_ptr
                ld a, EINVAL
                jp c, fail
                push hl
                pop de
                ld hl, conn
                call parse_ip
                jp nc, tn_badip
                ld hl, 23
                ld a, 2
                call arg_ptr
                jr c, tn_sock
                call parse_u16
                jp c, fail
tn_sock:
                ld (port), hl
                ld a, h
                ld (conn + 4), a
                ld a, l
                ld (conn + 5), a
                ld c, SYS_SOCKET
                ld b, 1
                rst 08h
                jp c, fail
                ld a, l
                ld (sfd), a
                ld c, SYS_CONNECT
                ld e, a
                ld hl, conn
                rst 08h
                jp c, fail
                ld hl, msg_conn
                call puts
                call cr
                ld a, (sfd)
                ld (pfd + 3), a
tn_loop:
                ld de, pfd
                ld b, 2
                ld hl, POLL_FOREVER
                ld c, SYS_POLL
                rst 08h
                jp c, fail
                ld a, (pfd + 2)
                and POLLIN
                call nz, from_stdin
                ld a, (pfd + 5)
                and POLLIN
                call nz, from_sock
                jr tn_loop

from_stdin:
                ld c, SYS_READ
                ld de, 0
                ld hl, buf
                ld ix, 256
                rst 08h
                jp c, fail
                ld a, h
                or l
                ret z
                push hl
                pop ix
                ld a, (sfd)
                ld e, a
                ld d, 0
                ld hl, buf
                ld c, SYS_SEND
                rst 08h
                jp c, fail
                ret

from_sock:
                ld a, (sfd)
                ld e, a
                ld d, 0
                ld hl, buf
                ld ix, 256
                ld c, SYS_RECV
                rst 08h
                jp c, fail
                ld a, h
                or l
                jr nz, fs_out
                ld hl, msg_closed
                call puts
                call cr
                jp exit0
fs_out:
                push hl
                pop ix
                ld c, SYS_WRITE
                ld de, 1
                ld hl, buf
                rst 08h
                jp c, fail
                ret

                include "ipdot.inc"

parse_u16:
                ld de, 0
pu:
                ld a, (hl)
                or a
                jr z, pu_done
                cp '0'
                jp c, bad
                cp '9' + 1
                jp nc, bad
                sub '0'
                push hl
                ld h, d
                ld l, e
                add hl, hl
                add hl, hl
                add hl, de
                add hl, hl
                ld e, a
                ld d, 0
                add hl, de
                ex de, hl
                pop hl
                inc hl
                jr pu
pu_done:
                ex de, hl
                or a
                ret
bad:
                ld a, EINVAL
                scf
                ret

tn_badip:
                ld a, EINVAL
                jp fail

msg_conn:       db "connected", 0
msg_closed:     db "closed", 0
sfd:            db 0
port:           dw 0
conn:           ds 6, 0
pfd:            db 0, POLLIN, 0
                db 0, POLLIN, 0
buf:            ds 256, 0

                include "run.inc"
