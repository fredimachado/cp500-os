; /bin/term — Hayes modem terminal (milestone 6).

                include "cp500.inc"

                org ORIGIN

MODE_WAITOK       equ 0
MODE_LOCAL        equ 1
MODE_ONLINE       equ 2

term:
                ld c, SYS_OPEN
                ld de, ser_path
                ld b, O_READ | O_WRITE
                rst 08h
                jp c, fail
                ld a, l
                ld (ser_fd), a
                ld (pfd_ser), a
                ld hl, ate_cmd
                call ser_fd_de
                ld ix, ate_len
                call write_de
                ld a, MODE_WAITOK
                ld (mode), a
                xor a
                ld (ok_pos), a
                ld (conn_pos), a
                ld (last_cr), a

term_loop:
                ld a, (mode)
                cp MODE_WAITOK
                ld hl, 90
                jr z, tl_poll
                ld hl, POLL_FOREVER
tl_poll:
                ld c, SYS_POLL
                ld de, pfd
                ld b, 2
                rst 08h
                ld a, h
                or l
                jr nz, tl_ready
                ld a, (mode)
                cp MODE_WAITOK
                jr nz, term_loop
                ld hl, no_modem
                call puts
                call cr
                ld a, MODE_LOCAL
                ld (mode), a
                jr term_loop
tl_ready:
                ld a, (pfd_ser + 2)
                and POLLIN
                call nz, from_modem
                ld a, (pfd + 2)
                and POLLIN
                call nz, from_keys
                jr term_loop

from_modem:
                call ser_fd_de
                ld hl, byte_buf
                ld ix, 1
                ld c, SYS_READ
                rst 08h
                jp c, fail
                ld a, h
                or l
                jp z, exit0
                ld a, (byte_buf)
                call modem_byte
                ret

modem_byte:
                push af
                ld a, (mode)
                cp MODE_WAITOK
                jr nz, mb_conn
                pop af
                push af
                ld hl, ok_str
                ld a, (ok_pos)
                ld e, a
                ld d, 0
                add hl, de
                cp (hl)
                jr nz, mb_ok_bad
                ld hl, ok_pos
                inc (hl)
                ld a, (hl)
                cp 3
                jr nz, mb_conn_push
                ld a, MODE_LOCAL
                ld (mode), a
                xor a
                ld (ok_pos), a
                pop af
                ret
mb_ok_bad:
                xor a
                ld (ok_pos), a
mb_conn_push:
                pop af
                push af
mb_conn:
                ld hl, conn_str
                ld a, (conn_pos)
                ld e, a
                ld d, 0
                add hl, de
                pop af
                push af
                cp (hl)
                jr nz, mb_conn_bad
                ld hl, conn_pos
                inc (hl)
                ld a, (hl)
                cp 7
                jr nz, mb_out
                call go_online
                xor a
                ld (conn_pos), a
                pop af
                ret
mb_conn_bad:
                xor a
                ld (conn_pos), a
mb_out:
                pop af
                cp 0Ah
                jr nz, mb_nolf
                ld a, (last_cr)
                or a
                ret nz
mb_nolf:
                cp 0Dh
                jr nz, mb_nocr
                ld a, 1
                ld (last_cr), a
                jr mb_emit
mb_nocr:
                xor a
                ld (last_cr), a
mb_emit:
                ld (byte_buf), a
                ld hl, byte_buf
                ld de, 1
                ld ix, 1
                ld c, SYS_WRITE
                rst 08h
                jp c, fail
                ret

go_online:
                ld a, MODE_ONLINE
                ld (mode), a
                call ser_fd_de
                ld hl, SER_GETCFG
                ld ix, cfg
                ld c, SYS_IOCTL
                rst 08h
                jp c, fail
                ld a, (cfg + CFG_FLAGS)
                or CFG_F_RTSCTS | CFG_F_DCD
                ld (cfg + CFG_FLAGS), a
                ld hl, SER_SETCFG
                ld c, SYS_IOCTL
                rst 08h
                jp c, fail
                ret

from_keys:
                ld c, SYS_READ
                ld de, 0
                ld hl, byte_buf
                ld ix, 1
                rst 08h
                jp c, fail
                ld a, h
                or l
                ret z
                ld a, (mode)
                cp MODE_ONLINE
                jr z, fk_ser
                ld hl, byte_buf
                ld de, 1
                ld ix, 1
                ld c, SYS_WRITE
                rst 08h
                jp c, fail
fk_ser:
                ld hl, byte_buf
                call ser_fd_de
                ld ix, 1
                call write_de
                ret

ser_fd_de:
                ld a, (ser_fd)
                ld e, a
                ld d, 0
                ret

write_de:
                ld c, SYS_WRITE
                rst 08h
                jp c, fail
                ret

ser_path:       db "/dev/ser0", 0
ate_cmd:        db "ATE0V1", 0Dh
ate_len:        equ $ - ate_cmd
ok_str:         db "OK", 0Dh
conn_str:       db "CONNECT"
no_modem:       db "no modem", 0

ser_fd:         db 0
mode:           db 0
ok_pos:         db 0
conn_pos:       db 0
last_cr:        db 0
byte_buf:       db 0
cfg:            ds CFG_SIZE, 0

pfd:            db 0, POLLIN, 0
pfd_ser:        db 0, POLLIN, 0

                include "run.inc"
