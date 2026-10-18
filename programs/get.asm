; get http://host[:port]/path [outfile]. HTTP/1.0, status 200 only.

                include "cp500.inc"

                org ORIGIN

                ld (argv), hl
                ld a, 1
                call arg_ptr
                ld a, EINVAL
                jp c, fail
                call parse_url
                jp c, fail
                ld a, 2
                call arg_ptr
                jr c, g_no_out
                ld (out_path), hl
                ld a, 1
                ld (use_file), a
                jr g_sock
g_no_out:
                xor a
                ld (use_file), a
g_sock:
                ld hl, (port)
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
                call send_req
                jp c, fail
                call read_status
                jp c, fail
                call skip_headers
                jp c, fail
                ld a, (use_file)
                or a
                jr nz, g_file
g_body_out:
                ld a, (sfd)
                ld e, a
                ld d, 0
                ld hl, buf
                ld ix, 256
                ld b, 0
                ld c, SYS_RECV
                rst 08h
                jp c, fail
                ld a, h
                or l
                jr z, g_ok
                push hl
                pop ix
                ld c, SYS_WRITE
                ld de, 1
                ld hl, buf
                rst 08h
                jp c, fail
                jr g_body_out
g_file:
                ld c, SYS_OPEN
                ld de, out_path
                ld b, O_WRITE | O_CREATE | O_TRUNC
                rst 08h
                jp c, fail
                ld a, l
                ld (out_fd), a
g_body_file:
                ld a, (sfd)
                ld e, a
                ld d, 0
                ld hl, buf
                ld ix, 256
                ld b, 0
                ld c, SYS_RECV
                rst 08h
                jp c, fail
                ld a, h
                or l
                jr z, g_close
                push hl
                pop ix
                ld a, (out_fd)
                ld e, a
                ld d, 0
                ld hl, buf
                ld c, SYS_WRITE
                rst 08h
                jp c, fail
                jr g_body_file
g_close:
                ld a, (out_fd)
                ld e, a
                ld d, 0
                ld c, SYS_CLOSE
                rst 08h
g_ok:
                call cr
                ld hl, msg_ok
                call puts
                call cr
                jp exit0

send_req:
                ld hl, buf
                ld (req_ptr), hl
                ld de, req
                call append_str
                ld de, (path_ptr)
                call append_str
                ld de, req_tail
                call append_str
                ld hl, (req_ptr)
                ld de, buf
                or a
                sbc hl, de
                push hl
                pop ix
                ld a, (sfd)
                ld e, a
                ld d, 0
                ld hl, buf
                ld c, SYS_SEND
                rst 08h
                ret

append_str:
                ld hl, (req_ptr)
as:
                ld a, (de)
                or a
                jr z, as_out
                ld (hl), a
                inc hl
                inc de
                jr as
as_out:
                ld (req_ptr), hl
                ret

read_status:
                ld hl, 0
                ld (hdr_len), hl
rs_loop:
                ld a, (sfd)
                ld e, a
                ld hl, buf
                ld ix, 1
                ld b, 0
                ld c, SYS_RECV
                rst 08h
                jp c, fail
                ld a, h
                or l
                jp z, rs_bad
                ld a, (buf)
                ld hl, (hdr_len)
                ld de, hdr
                add hl, de
                ld (hl), a
                ld hl, (hdr_len)
                inc hl
                ld (hdr_len), hl
                ld a, (hdr_len)
                cp 12
                jr c, rs_loop
                ld hl, hdr
                ld a, (hl)
                cp 'H'
                jr nz, rs_bad
                ld hl, hdr + 9
                ld a, (hl)
                cp '2'
                jr nz, rs_bad
                inc hl
                ld a, (hl)
                cp '0'
                jr nz, rs_bad
                inc hl
                ld a, (hl)
                cp '0'
                jr nz, rs_bad
                or a
                ret
rs_bad:
                ld a, EIO
                scf
                ret

skip_headers:
                xor a
                ld (nl_count), a
sh_loop:
                ld a, (sfd)
                ld e, a
                ld hl, buf
                ld ix, 1
                ld b, 0
                ld c, SYS_RECV
                rst 08h
                jp c, fail
                ld a, h
                or l
                jp z, sh_bad
                ld a, (buf)
                cp 0Ah
                jr nz, sh_loop
                ld a, (nl_count)
                inc a
                ld (nl_count), a
                cp 2
                jr c, sh_loop
                or a
                ret
sh_bad:
                ld a, EIO
                scf
                ret

parse_url:
                ld de, scheme
                call skip_str
                ret c
                ld (host_ptr), hl
                ld de, 0
ph:
                ld a, (hl)
                cp '/'
                jr z, ph_done
                cp ':'
                jr z, ph_port
                cp 0
                jp z, bad
                inc hl
                jr ph
ph_port:
                ld a, 0
                ld (hl), a
                inc hl
                call parse_u16
                jp c, bad
                ld (port), de
                ld a, (hl)
                cp '/'
                jp nz, bad
                jr ph_host
ph_done:
                ld a, 0
                ld (hl), a
                ld hl, 80
                ld (port), hl
ph_host:
                push hl
                ld de, (host_ptr)
                ld hl, conn
                call parse_ip
                pop hl
                jp nc, bad
ph_slash:
                inc hl
                ld (path_ptr), hl
                or a
                ret

skip_str:
                ld a, (de)
                or a
                ret z
                cp (hl)
                jp nz, bad
                inc de
                inc hl
                jr skip_str

parse_u16:
                ld de, 0
pu:
                ld a, (hl)
                cp '/'
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
                or a
                ret
bad:
                ld a, EINVAL
                scf
                ret

bad_ip:
                ld a, EINVAL
                jp fail

                include "ipdot.inc"

scheme:         db "http://", 0
req:            db "GET ", 0
req_tail:       db " HTTP/1.0", 0Dh, 0Ah, 0Dh, 0Ah, 0
req_ptr:        dw 0
msg_ok:         db "GET OK", 0
sfd:            db 0
out_fd:         db 0
use_file:       db 0
host_ptr:       dw 0
path_ptr:       dw 0
out_path:       dw 0
port:           dw 80
conn:           ds 6, 0
hdr_len:        dw 0
nl_count:       db 0
hdr:            ds 16, 0
buf:            ds 256, 0

                include "run.inc"
