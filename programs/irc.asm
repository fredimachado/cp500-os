; Phase-1 IRC client (replay transport).

                include "cp500.inc"

                org ORIGIN

start:
                ld (argv), hl
                call parse_args
                jp c, fail
                push bc
                push ix
                call tr_open
                pop de
                pop bc
                jp c, open_fail
                push bc
                ld hl, out_buf
                ld (out_ptr), hl
                pop bc
                ; tr_open clobbers IX (syscall byte counts); the channel came back in DE.
                push de
                pop ix
                ld hl, bc
                call net_start
                call tr_boot_read
                ld a, (tr_kind)
                cp TR_KIND_MODEM
                jr nz, start_pump
                ; mod_open already read through CONNECT and the server speaks only
                ; after NICK/USER, so there is nothing to pump yet.
                ld a, RL_READY
                ld (rl_state), a
                jr start_reg
start_pump:
                call net_pump
start_reg:
                call net_register
                ; Paint after NICK/USER so "online" means the session is in
                ; live_loop next - not still blocked in register TX (kbd ring
                ; is only 32 bytes; typing during that write drops keys).
                xor a
                call win_show
                jp tr_run

open_fail:
                ld c, a
                ld a, h
                or l
                ld a, c
                jp z, fail
                push af
                push hl
                call puts
                call cr
                pop hl
                pop af
                jp fail

parse_args:
                ld a, 1
                call arg_ptr
                ld a, EINVAL
                ret c
                ld a, (hl)
                cp '-'
                jr nz, pa_live
                inc hl
                ld a, (hl)
                cp 'r'
                jr nz, pa_bad
                ld a, 2
                call arg_ptr
                ret c
                push hl
                ld a, 3
                call arg_ptr
                ret c
                ld (pa_out), hl
                ld a, 4
                call arg_ptr
                ret c
                ld (pa_nick), hl
                ld ix, 0
                pop hl
                ld bc, (pa_nick)
                ld de, (pa_out)
                or a
                ret
pa_live:
                ld (pa_nick), hl
                ld a, 2
                call arg_ptr
                ret c
                push hl
                ld a, 3
                call arg_ptr
                ld ix, 0
                jr c, pa_lx
                ld ix, hl
                ld a, 4
                call arg_ptr
                ld a, EINVAL
                ret nc
pa_lx:
                pop hl
                ld bc, (pa_nick)
                ld de, 0
                or a
                ret
pa_bad:
                ld a, EINVAL
                scf
                ret

pa_out:         dw 0
pa_nick:        dw 0

                include "irc/tr.inc"
                include "irc/mod.inc"
                include "irc/proto.inc"
                include "irc/cmd.inc"
                include "irc/win.inc"
                include "irc/text.inc"
                include "run.inc"

image_end:
                assert image_end - start <= 8192

bss             equ start + ((image_end - start + 255) & 0FF00h)
win_ring        equ bss + 0000h
rl_buf          equ bss + 1500h
sl_buf          equ bss + 1700h
out_buf         equ bss + 1900h
tr_wblk         equ bss + 1B00h
tr_chunk        equ bss + 1C00h
inp_buf         equ bss + 1D00h
misc            equ bss + 1E00h
msg_nick        equ bss + 1F00h
bss_end         equ bss + 1F20h

                assert bss_end - bss <= IRC_BSS

whdr            equ misc + 00h
msg_cmd         equ misc + 62h
msg_par         equ misc + 72h
msg_n           equ misc + 0EDh
wf_at           equ misc + 0EEh
mod_phase       equ misc + 0EFh
mod_line_len    equ misc + 0F0h
mod_pending     equ misc + 0F2h
mod_pending_err equ misc + 0F3h
tr_kind         equ misc + 0F4h
live_pfd_con    equ misc + 0F5h
live_pfd_ser    equ misc + 0F8h
mod_host        equ misc + 0FBh
me              equ misc + 90h
autojoin        equ misc + 0B0h
phase           equ misc + 0C8h
rl_state        equ misc + 0C9h
rl_len          equ misc + 0CAh
tr_rfd          equ misc + 0CCh
tr_wfd          equ misc + 0CDh
tr_wlen         equ misc + 0CEh
tr_state        equ misc + 0CFh
tr_pos          equ misc + 0D0h
tr_len          equ misc + 0D1h
tr_out          equ misc + 0D2h
tr_rem          equ misc + 0D4h
tr_got          equ misc + 0D6h
tr_close_err    equ misc + 0D7h
out_ptr         equ misc + 0D8h
cur_win         equ misc + 0DAh
kb_state        equ misc + 0DBh
fmt_arg         equ misc + 0DCh
fmt_sink        equ misc + 0DEh
san_state       equ misc + 0E0h
san_aux         equ misc + 0E1h
say_win         equ misc + 0E2h
say_col         equ misc + 0E3h
say_rows        equ misc + 0E4h
inp_len         equ misc + 0E5h
inp_view        equ misc + 0E6h
key_ch          equ misc + 0E7h
say_lastsp      equ misc + 0E8h
sl_ptr          equ misc + 0E9h
key_byte        equ misc + 0EAh
wire_fmt        equ misc + 0EBh
