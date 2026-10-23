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

MOD_OK_TICKS     equ 90                 ; 3 s for the modem to answer ATE0V1
MOD_DIAL_TICKS   equ 1800               ; 60 s of silence while dialling

; HL = host:port. Opens /dev/ser0, resets the modem, dials and waits for the
; result code. Carry on failure: A = error, HL = message or 0.
mod_open:
                ld a, TR_KIND_MODEM
                ld (tr_kind), a
                ld a, 0FFh
                ld (tr_rfd), a
                ld (tr_wfd), a
                ld (mod_host), hl
                xor a
                ld (mod_line_len), a
                ld (mod_pending), a
                ld (mod_pending_err), a
                ld c, SYS_OPEN
                ld de, mod_ser_path
                ; Kernel rejects open flags 0C0h (incl. 40h nonblock).
                ld b, O_READ | O_WRITE
                rst 08h
                jp c, mo_fail
                ld a, l
                ld (tr_rfd), a
                ld (live_pfd_ser), a
                xor a
                ld (live_pfd_con), a
                ld a, POLLIN
                ld (live_pfd_con + 1), a
                ld (live_pfd_ser + 1), a
                ld a, MOD_WAIT_OK
                ld (mod_phase), a
                ld hl, mod_nomodem
                ld (mod_failmsg), hl
                ld hl, mod_ate
                ld ix, mod_ate_len
                call mod_fd_de
                ld c, SYS_WRITE
                rst 08h
                jp c, mo_fail
                ld hl, MOD_OK_TICKS
                call mo_wait
                jp c, mo_fail
                ; One write: ATDT + host + CR into tr_chunk, then SYS_WRITE.
                ld de, tr_chunk
                ld hl, mod_atdt
mo_atdt_cp:
                ld a, (hl)
                or a
                jr z, mo_host_cp
                ld (de), a
                inc hl
                inc de
                jr mo_atdt_cp
mo_host_cp:
                ld hl, (mod_host)
                ld b, 64
mo_host_cp1:
                ld a, (hl)
                or a
                jr z, mo_dial_cr
                ld (de), a
                inc hl
                inc de
                djnz mo_host_cp1
mo_dial_cr:
                ld a, 0Dh
                ld (de), a
                inc de
                ld hl, tr_chunk
                ex de, hl
                or a
                sbc hl, de
                push de
                push hl
                pop ix
                pop hl
                ld a, MOD_WAIT_CONNECT
                ld (mod_phase), a
                ld hl, mod_na
                ld (mod_failmsg), hl
                ld hl, tr_chunk
                call mod_fd_de
                ld c, SYS_WRITE
                rst 08h
                jr c, mo_fail
                ld hl, MOD_DIAL_TICKS
                call mo_wait
                jr c, mo_fail
                ; Online: hold RTS/CTS and treat a DCD drop as hangup.
                call mod_fd_de
                ld hl, SER_GETCFG
                ld ix, tr_chunk
                ld c, SYS_IOCTL
                rst 08h
                jr c, mo_iofail
                ld a, (tr_chunk + CFG_FLAGS)
                or CFG_F_RTSCTS | CFG_F_DCD
                ld (tr_chunk + CFG_FLAGS), a
                call mod_fd_de
                ld ix, tr_chunk
                ld hl, SER_SETCFG
                ld c, SYS_IOCTL
                rst 08h
                ret nc
mo_iofail:
                ld hl, 0
mo_fail:
                push af
                push hl
                call mod_close
                pop hl
                pop af
                scf
                ret

; HL = ticks to wait for each byte. Feeds result-code bytes to mo_feed until
; mod_phase leaves its wait state. Carry: A = error, HL = message or 0.
mo_wait:
                ld (mo_ptmo), hl
mwt_next:
                ld hl, (mo_ptmo)
                call mo_poll1
                ret c
                ld a, h
                or l
                jr z, mwt_fail
                call mo_read1
                ret c
                ld a, h
                or l
                jr z, mwt_next
                ld a, (byte_buf)
                call mo_feed
                ld a, (mod_phase)
                cp MOD_FAILED
                jr z, mwt_fail
                cp MOD_WAIT_OK
                jr z, mwt_next
                cp MOD_WAIT_CONNECT
                jr z, mwt_next
                or a
                ret
mwt_fail:
                ld hl, (mod_failmsg)
                ld a, EIO
                scf
                ret

mo_poll1:
                ld (mo_ptmo + 2), hl
                ld a, (tr_rfd)
                ld (live_pfd_ser), a
                ld a, POLLIN
                ld (live_pfd_ser + 1), a
                xor a
                ld (live_pfd_ser + 2), a
                ld hl, (mo_ptmo + 2)
                ld c, SYS_POLL
                ld de, live_pfd_ser
                ld b, 1
                rst 08h
                ret
mo_ptmo:        dw 0, 0

mo_read1:
                ld a, (live_pfd_ser + 2)
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

; A = byte of a result code. Collects up to 10 characters per line in tr_chunk.
mo_feed:
                cp 0Dh
                jr z, mo_line
                cp 0Ah
                jr z, mo_line
                ld c, a
                ld a, (mod_line_len)
                cp 10
                ret nc
                ld e, a
                ld d, 0
                ld hl, tr_chunk
                add hl, de
                ld (hl), c
                ld hl, mod_line_len
                inc (hl)
                ret
mo_line:
                ld a, (mod_line_len)
                or a
                ret z
                ld a, (mod_phase)
                cp MOD_WAIT_OK
                jr nz, mo_lc
                ld hl, mod_ok
                call mo_exact
                jr nz, mo_line_clr
                ld a, MOD_COMMAND
                ld (mod_phase), a
                jr mo_line_clr
mo_lc:
                call mo_class
mo_line_clr:
                xor a
                ld (mod_line_len), a
                ret

; Dial result: CONNECT[ rate] goes online, a failure code ends the dial.
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
                ld hl, mod_fails
mo_cl_next:
                ld e, (hl)
                inc hl
                ld d, (hl)
                inc hl
                ld a, d
                or e
                ret z
                push hl
                ex de, hl
                push hl
                call mo_exact
                pop hl
                pop de
                ex de, hl
                jr nz, mo_cl_next
                ld (mod_failmsg), de
                ld a, MOD_FAILED
                ld (mod_phase), a
                ret

; HL = NUL-terminated code. Z when the collected line is exactly that code.
mo_exact:
                ld de, tr_chunk
                ld a, (mod_line_len)
                ld b, a
mo_ex_loop:
                ld a, (hl)
                or a
                jr z, mo_ex_end
                ld a, b
                or a
                jr z, mo_ex_no
                ld a, (de)
                cp (hl)
                ret nz
                inc hl
                inc de
                dec b
                jr mo_ex_loop
mo_ex_end:
                ld a, b
                or a
                ret
mo_ex_no:
                inc a
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
                ; Cap at 255: mr_lim is one byte. BC=512 (empty rl_buf) used
                ; to set lim=0 and never read - join floods then wedged RX.
                ld a, b
                or a
                ld a, c
                jr z, mr_lim_ok
                ld a, 255
mr_lim_ok:
                ld (mr_lim), a
                ld (mr_dest), hl
                xor a
                ld (mr_got), a
mr_loop:
                ld hl, 0
                call mo_poll1
                jr c, mr_pollbad
                ld a, (live_pfd_ser + 2)
                and POLLNVAL
                jr nz, mr_pollbad
                ; POLLERR = overrun/framing; do not kill the session.
                ld a, (live_pfd_ser + 2)
                and POLLIN | POLLHUP
                jr z, mr_done
                ld a, (mr_lim)
                ld hl, mr_got
                sub (hl)
                jr z, mr_done
                ld e, a
                ld d, 0
                push de
                pop ix
                call mod_fd_de
                ld hl, (mr_dest)
                ld c, SYS_READ
                rst 08h
                jr c, mr_rderr
                ld a, h
                or l
                jr z, mr_empty
                push hl
                ld de, (mr_dest)
                add hl, de
                ld (mr_dest), hl
                pop hl
                ld a, l
                ld hl, mr_got
                add a, (hl)
                ld (hl), a
                ; Short read from ser_read: stop this fill.
                jr mr_done
mr_empty:
                ld a, (live_pfd_ser + 2)
                and POLLHUP
                jr z, mr_done
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
                ; Whole line + CRLF in one SYS_WRITE. Byte-at-a-time wedges after
                ; NICK's CR once Hayes has CONNECT sitting in the RX path.
                push bc
                push hl
                ld de, tr_chunk
                ld a, b
                or c
                jr z, mw_cr
                ldir
mw_cr:
                ld a, 0Dh
                ld (de), a
                inc de
                ld a, 0Ah
                ld (de), a
                inc de
                ld hl, tr_chunk
                ex de, hl
                or a
                sbc hl, de
                push de
                push hl
                pop ix
                pop hl
                call mod_fd_de
                ld c, SYS_WRITE
                rst 08h
                pop hl
                pop bc
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

; Close the serial port; the kernel linger window keeps RTS up and then
; drops DTR so the Hayes bridge hangs up (&D2) without an escape sequence.
mod_close:
                ld a, (tr_rfd)
                cp 0FFh
                ret z
                ld a, (tr_rfd)
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
                ld a, (cur_win)
                call win_show
tr_replay_key:
                call key_read
                call key
                jr nc, tr_replay_key
                jr tr_replay_run

live_loop:
                ; Repaint once per batch of lines rather than once per say.
                ld a, (say_rows)
                or a
                jr z, ll_go
                xor a
                ld (say_rows), a
                ld a, (cur_win)
                call win_show
ll_go:
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
                and POLLNVAL
                jp nz, ll_dead
                ; POLLERR alone is overrun/framing noise - do not pump (mod_read
                ; would spin). Only POLLIN/HUP mean bytes or hangup.
                ld a, (live_pfd_ser + 2)
                and POLLIN | POLLHUP
                call nz, ll_ser
                ld a, (live_pfd_con + 2)
                and POLLIN
                call nz, ll_con
                jp live_loop
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
                call ui_refresh
                jp live_loop

mod_ser_path:   db "/dev/ser0", 0
mod_ate:        db "ATE0V1", 0Dh
mod_ate_len:    equ $ - mod_ate
mod_ok:         db "OK", 0
mod_atdt:       db "ATDT", 0
mod_conn:       db "CONNECT"
mod_nc:         db "NO CARRIER", 0
mod_na:         db "NO ANSWER", 0
mod_busy:       db "BUSY", 0
mod_err:        db "ERROR", 0
mod_fails:      dw mod_nc, mod_na, mod_busy, mod_err, 0
mod_nomodem:    db "no modem", 0
byte_buf:       db 0
mod_failmsg:    dw 0
