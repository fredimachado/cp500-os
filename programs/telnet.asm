; telnet host [port]. Default port 23. Char-at-a-time with local echo.

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
                ex de, hl
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
                ld ix, 1
                rst 08h
                jp c, fail
                ld a, h
                or l
                ret z
                ld hl, buf
                ld de, 1
                ld ix, 1
                ld c, SYS_WRITE
                rst 08h
                jp c, fail
                ld a, (buf)
                cp 0Dh
                jr nz, fs_send1
                ; NVT: Enter is CRLF on the wire; local console already took CR.
                ld a, 0Ah
                ld (buf + 1), a
                ld ix, 2
                jr fs_send
fs_send1:
                ld ix, 1
fs_send:
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

                include "num.inc"

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
