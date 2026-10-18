; Hayes modem transport (live /dev/ser0).

TR_KIND_REPLAY  equ 0
TR_KIND_MODEM   equ 1

MOD_COMMAND      equ 0
MOD_WAIT_OK      equ 1
MOD_WAIT_CONNECT equ 2
MOD_ONLINE       equ 3
MOD_FAILED       equ 4

MODP_NONE        equ 0
MODP_EOF         equ 1
MODP_ERR         equ 2

mod_open:
                ld a, TR_KIND_MODEM
                ld (tr_kind), a
                ld a, 0FFh
                ld (tr_rfd), a
                ld (tr_wfd), a
                ld (mod_host), hl
                xor a
                ld (mod_phase), a
                ld (mod_line_len), a
                ld (mod_line_over), a
                ld (mod_pending), a
                ld (mod_pending_err), a
                ld c, SYS_OPEN
                ld de, mod_ser_path
                ld b, O_READ | O_WRITE
                rst 08h
                jp c, mo_sysfail
                ld a, l
                ld (tr_rfd), a
                ld (live_pfd_ser), a
                ld a, POLLIN
                ld (live_pfd_con + 1), a
                ld (live_pfd_ser + 1), a
                ld hl, mod_ate
                ld bc, mod_ate_len
                call mo_write
                jp c, mo_iofail
                ld a, MOD_WAIT_OK
                ld (mod_phase), a
mo_waitok:
                ld hl, 90
                call mo_poll1
                jp c, mo_iofail
                ld a, h
                or l
                jr nz, mo_wok_got
                call mod_close
                ld hl, mod_nomodem
                ld a, EIO
                scf
                ret
mo_wok_got:
                call mo_read1
                jp c, mo_iofail
                ld a, h
                or l
                jr z, mo_waitok
                ld a, (byte_buf)
                call mo_feed
                ld a, (mod_phase)
                cp MOD_FAILED
                jp z, mo_failret
                cp MOD_COMMAND
                jr nz, mo_waitok
                ld hl, mod_atdt
mo_atdt:
                ld a, (hl)
                or a
                jr z, mo_atdt_done
                push hl
                ld a, (hl)
                ld b, 1
                call mo_wchr
                pop hl
                jp c, mo_iofail
                inc hl
                jr mo_atdt
mo_atdt_done:
                ld hl, (mod_host)
mo_dial:
                ld a, (hl)
                or a
                jr z, mo_dial_cr
                push hl
                ld a, (hl)
                ld b, 1
                call mo_wchr
                pop hl
                jp c, mo_iofail
                inc hl
                jr mo_dial
mo_dial_cr:
                ld a, 0Dh
                ld b, 1
                call mo_wchr
                jp c, mo_iofail
                ld a, MOD_WAIT_CONNECT
                ld (mod_phase), a
                xor a
                ld (mod_line_len), a
mo_waitconn:
                ld hl, POLL_FOREVER
                call mo_poll1
                jp c, mo_iofail
                call mo_read1
                jp c, mo_iofail
                ld a, h
                or l
                jr z, mo_waitconn
                ld a, (byte_buf)
                call mo_feed
                ld a, (mod_phase)
                cp MOD_FAILED
                jp z, mo_failret
                cp MOD_ONLINE
                jr nz, mo_waitconn
                push ix
                call mo_online
                pop ix
                jp nc, mo_ok
mo_iofail:
                push af
                call mod_close
                pop af
                ld hl, 0
                scf
                ret
mo_sysfail:
                ld hl, 0
                scf
                ret
mo_ok:
                or a
                ret
mo_failret:
                ld hl, (mod_failmsg)
                ld a, EIO
                scf
                ret

mo_online:
                call mod_fd_de
                ld hl, SER_GETCFG
                ld ix, tr_chunk
                ld c, SYS_IOCTL
                rst 08h
                ret c
                ld a, (tr_chunk + CFG_FLAGS)
                or CFG_F_RTSCTS | CFG_F_DCD
                ld (tr_chunk + CFG_FLAGS), a
                call mod_fd_de
                ld ix, tr_chunk
                ld hl, SER_SETCFG
                ld c, SYS_IOCTL
                rst 08h
                ret

mo_write:
                call mod_fd_de
                ld c, SYS_WRITE
                rst 08h
                ret

mo_wchr:
                ld (byte_buf), a
                ld hl, byte_buf
                ld bc, 1
                jp mo_write

mo_poll1:
                ld (mo_ptmo), hl
                ld a, (tr_rfd)
                ld (mod_pollfd), a
                ld a, POLLIN
                ld (mod_pollfd + 1), a
                xor a
                ld (mod_pollfd + 2), a
                ld hl, (mo_ptmo)
                ld c, SYS_POLL
                ld de, mod_pollfd
                ld b, 1
                rst 08h
                ret
mo_ptmo:        dw 0

mo_read1:
                ld a, (mod_pollfd + 2)
                and POLLIN
                jr nz, mo_r1_do
                xor a
                ld h, a
                ld l, a
                ret
mo_r1_do:
                call mod_fd_de
                ld hl, byte_buf
                ld ix, 1
                ld c, SYS_READ
                rst 08h
                ret

mod_fd_de:
                ld a, (tr_rfd)
                ld e, a
                ld d, 0
                ret

mo_feed:
                cp 0Dh
                jr z, mo_line
                cp 0Ah
                jr z, mo_line
                push af
                ld a, (mod_line_len)
                cp 10
                jr nc, mo_over
                ld e, a
                ld d, 0
                ld hl, tr_chunk
                add hl, de
                pop af
                ld (hl), a
                ld hl, mod_line_len
                inc (hl)
                ret
mo_over:
                pop af
                ld a, 1
                ld (mod_line_over), a
                ret
mo_line:
                ld a, (mod_line_len)
                or a
                jr z, mo_line_clr
                ld a, (mod_phase)
                cp MOD_WAIT_OK
                jr nz, mo_lc
                ld a, (mod_line_len)
                cp 2
                jr nz, mo_line_clr
                ld a, (tr_chunk)
                cp 'O'
                jr nz, mo_line_clr
                ld a, (tr_chunk + 1)
                cp 'K'
                jr nz, mo_line_clr
                ld a, MOD_COMMAND
                ld (mod_phase), a
                jr mo_line_clr
mo_lc:
                call mo_class
mo_line_clr:
                xor a
                ld (mod_line_len), a
                ld (mod_line_over), a
                ret

mo_class:
                ld a, (mod_line_len)
                cp 7
                jr c, mo_cl_f
                ld hl, mod_conn
                ld b, 7
                ld de, tr_chunk
mo_cl_c:
                ld a, (de)
                cp (hl)
                jr nz, mo_cl_f
                inc hl
                inc de
                djnz mo_cl_c
                ld a, MOD_ONLINE
                ld (mod_phase), a
                ret
mo_cl_f:
                ld hl, mod_nc
                call mo_exact
                ret c
                ld hl, mod_na
                call mo_exact
                ret c
                ld hl, mod_err
                jp mo_exact

mo_exact:
                push hl
                pop de
                push hl
                ld b, 0
mo_ex_loop:
                ld a, (de)
                or a
                jr z, mo_ex_done
                push af
                push de
                ld a, b
                ld hl, mod_line_len
                cp (hl)
                pop de
                pop af
                jr nc, mo_ex_no
                push af
                push bc
                ld c, b
                ld b, 0
                ld hl, tr_chunk
                add hl, bc
                ld a, (hl)
                ld d, a
                pop bc
                pop af
                cp d
                jr nz, mo_ex_no
                inc de
                inc b
                jr mo_ex_loop
mo_ex_done:
                ld a, b
                ld hl, mod_line_len
                cp (hl)
                jr nz, mo_ex_no
                pop hl
                ld (mod_failmsg), hl
                call mod_close
                ld a, MOD_FAILED
                ld (mod_phase), a
                scf
                ret
mo_ex_no:
                pop hl
                or a
                ret

mod_read:
                ld a, b
                or c
                jr nz, mr_have
                xor a
                ret
mr_have:
                ld a, (mod_pending)
                cp MODP_EOF
                jp z, mr_eof
                cp MODP_ERR
                jp z, mr_perr
                push hl
                push bc
                ld a, c
                ld (mr_lim), a
                ld (mr_dest), hl
                xor a
                ld (mr_got), a
mr_loop:
                ld hl, 0
                call mo_poll1
                jr c, mr_pollbad
                ld a, (mod_pollfd + 2)
                and POLLNVAL | POLLERR
                jr nz, mr_pollbad
                ld a, (mod_pollfd + 2)
                and POLLIN | POLLHUP
                jr z, mr_done
                call mod_fd_de
                ld hl, (mr_dest)
                ld ix, 1
                ld c, SYS_READ
                rst 08h
                jr c, mr_rderr
                ld a, h
                or l
                jr z, mr_hang
                ld hl, (mr_dest)
                inc hl
                ld (mr_dest), hl
                ld hl, mr_got
                inc (hl)
                ld a, (hl)
                ld hl, mr_lim
                cp (hl)
                jr c, mr_loop
                jr mr_done
mr_hang:
                ld a, (mr_got)
                or a
                jr nz, mr_lateof
                pop bc
                pop hl
                xor a
                ld b, a
                ld c, a
                scf
                ret
mr_lateof:
                ld a, MODP_EOF
                ld (mod_pending), a
                jr mr_done
mr_rderr:
                cp EAGAIN
                jr z, mr_done
                jr mr_pollbad
mr_pollbad:
                ld a, (mr_got)
                or a
                jr nz, mr_lerr
                pop bc
                pop hl
                xor a
                ld b, a
                ld c, a
                scf
                ret
mr_lerr:
                ld a, MODP_ERR
                ld (mod_pending), a
                ld a, EIO
                ld (mod_pending_err), a
mr_done:
                ld a, (mr_got)
                pop bc
                pop hl
                ld c, a
                ld b, 0
                or a
                ret
mr_eof:
                xor a
                ld b, a
                ld c, a
                scf
                ret
mr_perr:
                ld a, (mod_pending_err)
                push af
                xor a
                ld b, a
                ld c, a
                pop af
                scf
                ret

mr_dest:        dw 0
mr_got:         db 0
mr_lim:         db 0

mod_write:
                push bc
                push hl
mw_loop:
                ld a, b
                or c
                jr z, mw_eol
                ld a, (hl)
                inc hl
                push hl
                push bc
                ld b, 1
                call mo_wchr
                pop bc
                pop hl
                jp c, mw_fail
                dec bc
                jr mw_loop
mw_eol:
                ld a, 0Dh
                call mo_wchr
                jp c, mw_fail
                ld a, 0Ah
                call mo_wchr
                pop hl
                pop bc
                or a
                ret
mw_fail:
                pop hl
                pop bc
                scf
                ret

mod_boot_read:
                xor a
                ld b, a
                ld c, a
                or a
                ret

mod_kick:
                xor a
                ret

mod_close:
                ld a, (tr_rfd)
                cp 0FFh
                ret z
                ld e, a
                ld d, 0
                ld c, SYS_CLOSE
                rst 08h
                ld a, 0FFh
                ld (tr_rfd), a
                ret

tr_run:
                ld a, (tr_kind)
                cp TR_KIND_MODEM
                jp z, live_loop
tr_replay_run:
                call net_pump
                jr nz, tr_replay_run
tr_replay_key:
                call key_read
                call key
                jr nc, tr_replay_key
                jr tr_replay_run

live_loop:
                call out_flush
                ld a, (phase)
                cp PHASE_DEAD
                jr nz, ll_two
                ld c, SYS_POLL
                ld de, live_pfd_con
                ld b, 1
                ld hl, POLL_FOREVER
                rst 08h
                jr ll_poll
ll_two:
                ld a, (tr_rfd)
                ld (live_pfd_ser), a
                ld c, SYS_POLL
                ld de, live_pfd_con
                ld b, 2
                ld hl, POLL_FOREVER
                rst 08h
ll_poll:
                jp c, ll_dead
                ld a, (live_pfd_ser + 2)
                and POLLIN | POLLHUP | POLLERR | POLLNVAL
                call nz, ll_ser
                ld a, (live_pfd_con + 2)
                and POLLIN
                call nz, ll_con
                jr live_loop
ll_ser:
ll_pump:
                call net_pump
                jr nz, ll_pump
                ret
ll_con:
                ld c, SYS_READ
                ld de, 0
                ld hl, key_byte
                ld ix, 1
                rst 08h
                ret c
                ld a, h
                or l
                ret z
                ld a, (key_byte)
                jp key
ll_dead:
                ld a, PHASE_DEAD
                ld (phase), a
                xor a
                call win_show
                jr live_loop

mod_ser_path:   db "/dev/ser0", 0
mod_ate:        db "ATE0V1", 0Dh
mod_ate_len:    equ $ - mod_ate
mod_atdt:       db "ATDT", 0
mod_conn:       db "CONNECT"
mod_nc:         db "NO CARRIER", 0
mod_na:         db "NO ANSWER", 0
mod_err:        db "ERROR", 0
mod_nomodem:    db "no modem", 0
byte_buf:       db 0
mod_failmsg:    dw 0
