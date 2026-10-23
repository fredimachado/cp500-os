PHASE_NEW       equ 0
PHASE_TRY0      equ 1
PHASE_TRY1      equ 2
PHASE_TRY2      equ 3
PHASE_TRY3      equ 4
PHASE_LIVE      equ 5
PHASE_DEAD      equ 6

LA_FILL         equ 0
LA_SKIP         equ 1

net_start:
                push hl
                ld de, me
                ld b, 31
ns_copy:
                ld a, (hl)
                or a
                jr z, ns_end
                ld (de), a
                inc hl
                inc de
                djnz ns_copy
ns_end:
                xor a
                ld (de), a
                pop hl
                ld hl, autojoin
                xor a
                ld (hl), a
                push ix
                pop de
                ld a, d
                or e
                jr z, ns_noch
                ex de, hl
                ld de, autojoin
                ld bc, 23
                ldir
                xor a
                ld (de), a
ns_noch:
                ld hl, whdr
                ld de, whdr + 1
                ld bc, 95
                xor a
                ld (hl), a
                ldir
                ld a, PHASE_TRY0
                ld (phase), a
                ld a, (rl_state)
                cp RL_READY
                jr z, ns_done
                xor a
                ld (rl_state), a
ns_done:
                ret

net_register:
                ld hl, w_nick_me
                call wire
                ld hl, w_user
                jp wire

; NZ consumed, Z idle/closed.
net_pump:
                ld a, (phase)
                cp PHASE_DEAD
                jp z, np_z
                xor a
                ld (np_hit), a
                ld a, (rl_state)
                cp RL_BOOT
                jr nz, np_have
                ld bc, (rl_len)
                ld a, b
                or c
                jr z, np_have
                ld hl, rl_buf
                ld a, (hl)
                cp ':'
                jr z, np_boot_ok
                ; Drop one Hayes line; do not wipe IRC that shared the read.
                call np_drop_line
                jr c, np_fill
                jp net_pump
np_boot_ok:
                ld a, RL_READY
                ld (rl_state), a
np_have:
                ld bc, (rl_len)
                ld a, b
                or c
                jr z, np_fill
                call np_parse
                ld a, (np_hit)
                or a
                ret nz
np_fill:
                ld hl, 512
                ld bc, (rl_len)
                or a
                sbc hl, bc
                ld b, h
                ld c, l
                ld a, b
                or c
                jr z, np_z
                ld hl, (rl_len)
                ld de, rl_buf
                add hl, de
                call tr_read
                jr c, np_eof
                ld a, b
                or c
                jr z, np_z
                ld hl, (rl_len)
                add hl, bc
                ld (rl_len), hl
                jp np_have
np_eof:
                ld a, PHASE_DEAD
                ld (phase), a
                ld a, 0
                ld hl, f_disc
                call say
                jr np_z
np_z:
                xor a
                ret

; Remove first CR/LF-terminated line from rl_buf; keep any bytes after it.
; Carry set: no CR/LF yet - caller should read more.
np_drop_line:
                ld hl, rl_buf
                ld bc, (rl_len)
ndl_scan:
                ld a, b
                or c
                scf
                ret z
                ld a, (hl)
                cp 0Ah
                jr z, ndl_cut
                cp 0Dh
                jr z, ndl_cut
                inc hl
                dec bc
                jr ndl_scan
ndl_cut:
                inc hl
                dec bc
                ld a, b
                or c
                jr z, ndl_clear
                ld a, (hl)
                cp 0Ah
                jr nz, ndl_move
                inc hl
                dec bc
                ld a, b
                or c
                jr z, ndl_clear
ndl_move:
                push bc
                ld de, rl_buf
                ldir
                pop bc
                ld (rl_len), bc
                or a
                ret
ndl_clear:
                xor a
                ld hl, rl_len
                ld (hl), a
                inc hl
                ld (hl), a
                or a
                ret

np_parse:
                ld hl, rl_buf
                ld bc, (rl_len)
                ld a, b
                or c
                jp nz, np_scan
                xor a
                ld (np_hit), a
                ret
np_scan:
                ld a, b
                or c
                ret z
                ld a, (hl)
                cp 0Ah
                jr z, np_cut
                cp 0Dh
                jr z, np_cut
                inc hl
                dec bc
                jr np_scan
                ret
np_cut:
                push bc
                push hl
                ld a, (hl)
                dec hl
                ld a, (hl)
                cp 0Dh
                jr nz, np_term
                dec hl
np_term:
                inc hl
                ld (hl), 0
                pop hl
                pop bc
                push hl
                push bc
                ld de, rl_buf
                or a
                sbc hl, de
                ex de, hl
                call line_dispatch
                ld a, 1
                ld (np_hit), a
                pop bc
                pop hl
                inc hl
                dec bc
                ld a, b
                or c
                jr z, np_clear
                ; CRLF: terminator was CR; drop the following LF.
                ld a, (hl)
                cp 0Ah
                jr nz, np_rest
                inc hl
                dec bc
                ld a, b
                or c
                jr z, np_clear
np_rest:
                push bc
                ld de, rl_buf
                ldir
                pop bc
                ld (rl_len), bc
                jp np_parse
np_clear:
                xor a
                ld hl, rl_len
                ld (hl), a
                inc hl
                ld (hl), a
                ret

line_dispatch:
                ld hl, rl_buf
                xor a
                ld (msg_nick), a
                ld a, (hl)
                cp ':'
                jr nz, ld_cmd
                inc hl
                push hl
                ld de, msg_nick
                call ld_copy_b
                pop hl
ld_tags:
                ld a, (hl)
                cp ' '
                jr z, ld_cmd
                inc hl
                jr ld_tags
ld_cmd:
                ld a, (hl)
                cp ' '
                jr nz, ld_cmd_go
                inc hl
                jr ld_cmd
ld_cmd_go:
                ld de, msg_cmd
                call ld_copy
                push hl
                xor a
                ld (msg_n), a
                ld hl, msg_par
                ld (hl), a
                ld de, msg_par + 1
                ld bc, 29
                ldir
                pop hl
ld_par:
                ld a, (hl)
                cp ' '
                jr z, ld_pws
                cp 0
                jr z, ld_go
                cp ':'
                jr z, ld_trail
                call ld_store
                call ld_skip
                jr ld_par
ld_pws:
                inc hl
                ld a, (hl)
                cp ' '
                jr z, ld_pws
                cp 0
                jr z, ld_go
                cp ':'
                jr z, ld_trail
                call ld_store
                call ld_skip
                jr ld_par
ld_trail:
                inc hl
                call ld_store
                call ld_skip
                jp ld_go
ld_go:
                call ld_pull_trail
                ld c, 2
                ld de, srv_tab
                ld hl, msg_cmd
                call lookup
                jr c, ld_numeric
                jp (hl)
ld_numeric:
                ld hl, msg_cmd
                ld a, (hl)
                cp '4'
                jr nz, ld_num3
                inc hl
                ld a, (hl)
                cp '3'
                jr nz, ld_num3
                inc hl
                ld a, (hl)
                cp '3'
                jr nz, ld_num3
                inc hl
                ld a, (hl)
                or a
                jr nz, ld_num3
                jp h_433
ld_num3:
                ld hl, msg_cmd
                ld a, (hl)
                cp '0'
                jr c, ld_drop
                cp '9' + 1
                jr nc, ld_drop
                jp h_numeric
ld_drop:
                ret

ld_word:
                ld a, (hl)
                cp ':'
                jr nz, ld_wcmd
                inc hl
                ld de, msg_nick
                call ld_copy
                ld a, (hl)
                cp '!'
                jr nz, ld_wcmd
                ld a, 0
                ld (hl), a
                inc hl
ld_wcmd:
                ld de, msg_cmd
                call ld_copy
                ret

ld_copy:
                ld a, (hl)
                cp '!'
                jr z, ld_ce
                cp ' '
                jr z, ld_ce
                cp 0
                jr z, ld_ce
                cp 0Ah
                jr z, ld_ce
                cp 0Dh
                jr z, ld_ce
                ld (de), a
                inc hl
                inc de
                jr ld_copy
ld_copy_b:
                ld b, 31
ld_copy_b_l:
                ld a, (hl)
                cp '!'
                jr z, ld_ce_b
                cp ' '
                jr z, ld_ce_b
                cp 0
                jr z, ld_ce_b
                cp 0Ah
                jr z, ld_ce_b
                cp 0Dh
                jr z, ld_ce_b
                ld (de), a
                inc hl
                inc de
                djnz ld_copy_b_l
                xor a
                ld (de), a
                ret
ld_ce_b:
                xor a
                ld (de), a
                ret
ld_ce:
                xor a
                ld (de), a
                ret

ld_zterm:
                ld a, (hl)
                cp '!'
                jr z, ld_z
                cp 0
                ret z
                inc hl
                jr ld_zterm
ld_z:
                ld a, 0
                ld (hl), a
                ret

ld_skip:
                ld a, (hl)
                cp ' '
                ret z
                cp 0
                ret z
                inc hl
                jr ld_skip

ld_pull_trail:
                ld hl, rl_buf
                ld bc, 0
lpt_scan:
                ld a, (hl)
                or a
                jr z, lpt_done
                cp ' '
                jr nz, lpt_adv
                push hl
                inc hl
                ld a, (hl)
                cp ':'
                pop hl
                jr nz, lpt_adv
                push hl
                inc hl
                inc hl
                ld b, h
                ld c, l
                pop hl
lpt_adv:
                inc hl
                jr lpt_scan
lpt_done:
                ld a, b
                or c
                ret z
                ld a, (msg_n)
                cp 1
                ret nz
                ld h, b
                ld l, c
                call ld_store
                call ld_skip
                ret

ld_store:
                ld a, (msg_n)
                cp 15
                ret nc
                push hl
                ld e, a
                ld d, 0
                ld hl, msg_par
                add hl, de
                add hl, de
                pop de
                ld (hl), e
                inc hl
                ld (hl), d
                ld a, (msg_n)
                inc a
                ld (msg_n), a
                ld h, d
                ld l, e
                ret

np_hit:         db 0

net_quit:
                ld hl, w_quit
                call wire
                jp tr_close

wire:
                push de
                ld de, (fmt_arg)
                push hl
                ld hl, wire_byte
                ld (fmt_sink), hl
                ld hl, sl_buf
                ld (sl_ptr), hl
                pop hl
                call fmt_run
                ; NUL-terminate: ws_len used to walk into the previous line
                ; left in sl_buf (USER's " 0 * :CP-500" after a short JOIN).
                ld hl, (sl_ptr)
                ld (hl), 0
                pop de
                ld hl, sl_buf
                ld de, sl_buf
                ld bc, 0
ws_len:
                ld a, (de)
                or a
                jr z, ws_go
                inc bc
                inc de
                ld a, b
                cp 1
                jr nc, ws_go
                ld a, c
                cp 510 & 0FFh
                jr c, ws_len
ws_go:
                ld hl, sl_buf
                call tr_write
                ret nc
                ld a, 0
                ld hl, f_wfail
                call say
                scf
                ret

; Control bytes and DEL go out as '?', except 01h (the CTCP delimiter).
wire_byte:
                cp 01h
                jr z, wb_ok
                cp 20h
                jr c, wb_q
                cp 7Fh
                jr z, wb_q
wb_ok:
                ld hl, sl_ptr
                ld e, (hl)
                inc hl
                ld d, (hl)
                ld (de), a
                inc de
                ld (sl_ptr), de
                xor a
                ret
wb_q:
                ld a, '?'
                jr wb_ok

w_nick_me:      db "NICK ", F_ME, 0
w_user:         db "USER ", F_ME, " 0 * :CP-500", 0
w_nick:         db "NICK ", F_ARG1, 0
w_pong:         db "PONG :", F_LAST, 0
w_privmsg:      db "PRIVMSG ", F_WIN, " :", F_ARG, 0
w_msg:          db "PRIVMSG ", F_ARG1, " :", F_ARGR, 0
w_action:       db "PRIVMSG ", F_WIN, " :", F_CTCP, "ACTION ", F_ARG, F_CTCP, 0
w_version:      db "NOTICE ", F_NICK, " :", F_CTCP, "VERSION CP500-IRC 0.1 / CP-500 Z80", F_CTCP, 0
w_ctcp_ping:    db "NOTICE ", F_NICK, " :", F_CTCP, "PING ", F_ARG, F_CTCP, 0
w_join:         db "JOIN ", F_ARG1, 0
w_part:         db "PART ", F_ARG1W, 0
w_names:        db "NAMES ", F_ARG1W, 0
w_whois:        db "WHOIS ", F_ARG1, 0
w_quote:        db F_ARG, 0
w_quit:         db "QUIT :", F_ARG, 0

f_chanmsg:      db "<", F_NICK, "> ", F_LAST, 0
f_privmsg:      db "*", F_NICK, "* ", F_LAST, 0
f_notice:       db "-", F_NICK, "- ", F_LAST, 0
f_action:       db "* ", F_NICK, " ", F_ARG, 0
f_join:         db "*** ", F_NICK, " joined ", F_PAR, 0, 0
f_part:         db "*** ", F_NICK, " left", 0
f_kick:         db "*** ", F_NICK, " was kicked", 0
f_quit:         db "*** ", F_NICK, " quit (", F_LAST, ")", 0
f_nick:         db "*** ", F_NICK, " is now ", F_LAST, 0
f_topic:        db "*** Topic: ", F_LAST, 0
f_users:        db "*** Users: ", F_LAST, 0
f_mode:         db "*** mode change", 0
f_disc:         db "*** Disconnected", 0
f_wfail:        db "*** write failed", 0
f_ctcp:         db "*** CTCP ", F_ARG, " from ", F_NICK, 0
f_numeric:      db F_CMD, " ", F_LAST, 0

srv_tab:
                db "PING", 0
                dw h_ping
                db "PRIVMSG", 0
                dw h_privmsg
                db "NOTICE", 0
                dw h_notice
                db "JOIN", 0
                dw h_join
                db "PART", 0
                dw h_part
                db "KICK", 0
                dw h_kick
                db "QUIT", 0
                dw h_quit
                db "NICK", 0
                dw h_nick
                db "TOPIC", 0
                dw h_topic
                db "MODE", 0
                dw h_mode
                db "ERROR", 0
                dw h_error
                db "001", 0
                dw h_001
                db "433", 0
                dw h_433
                db "332", 0
                dw h_332
                db "353", 0
                dw h_353
                db 0

h_ping:
                ld hl, w_pong
                jp wire

h_privmsg:
                call ctcp_split
                or a
                ret nz
                call hj_channel
                call win_for
                or a
                jr nz, hp_chan
                ld hl, (msg_par)
                ld a, (hl)
                cp '#'
                jr z, hp_c0
                cp '&'
                jr z, hp_c0
                cp '+'
                jr z, hp_c0
                cp '!'
                jr z, hp_c0
                ld a, (cur_win)
                cp 0
                jr nz, hp_pm0
                ld a, 2
                push af
                ld a, 0
                ld hl, f_privmsg
                call say
                pop af
                jr hp_pm
hp_pm0:
                ld a, 0
hp_pm:
                ld hl, f_privmsg
                jp say
hp_c0:
                ld a, 0
                ld hl, f_chanmsg
                jp say
hp_chan:
                ld hl, f_chanmsg
                jp say

h_notice:
                ld a, 0
                ld hl, f_notice
                jp say

h_join:
                ld hl, (msg_par)
hj_z:
                ld a, (hl)
                or a
                jr z, hj_me
                cp ' '
                jr z, hj_zterm
                inc hl
                jr hj_z
hj_zterm:
                ld (hl), 0
hj_me:
                ld hl, msg_nick
                call name_is_me
                jr nz, hj_other
                call hj_channel
                call win_claim
                jr c, hj_other
                call win_show
hj_other:
                call hj_channel
                call win_for
                ld hl, f_join
                jp say

hj_channel:
                ld b, 0
hj_ch:
                ld a, (msg_n)
                cp b
                jr z, hj_ch0
                jr c, hj_ch0
                ld a, b
                call msg_param
                jr nc, hj_cnext
                ld h, d
                ld l, e
                ld a, (hl)
                cp '#'
                jr z, hj_ch_ret
                cp '&'
                jr z, hj_ch_ret
                cp '+'
                jr z, hj_ch_ret
                cp '!'
                jr z, hj_ch_ret
hj_cnext:
                inc b
                jr hj_ch
hj_ch0:
                ld hl, (msg_par)
                ret
hj_ch_ret:
                push hl
hj_chz:
                ld a, (hl)
                or a
                jr z, hj_chz_done
                cp ' '
                jr z, hj_chzterm
                cp 0Dh
                jr z, hj_chzterm
                cp 0Ah
                jr z, hj_chzterm
                inc hl
                jr hj_chz
hj_chzterm:
                ld (hl), 0
hj_chz_done:
                pop hl
                ret

h_part:
                ld hl, msg_nick
                call name_is_me
                jr nz, hp_other
                ld hl, (msg_par)
                call win_release
                ld a, 0
                ld hl, f_part
                jp say
hp_other:
                ld hl, (msg_par)
                call win_for
                ld hl, f_part
                jp say

h_kick:
                ld hl, (msg_par + 2)
                call name_is_me
                jr nz, hk_other
                ld hl, (msg_par)
                call win_release
                ld a, 0
                ld hl, f_kick
                jp say
hk_other:
                ld hl, (msg_par)
                call win_for
                ld hl, f_kick
                jp say

h_quit:
                ld a, 0
                ld hl, f_quit
                jp say

h_nick:
                ld hl, msg_nick
                call name_is_me
                jr nz, hn_show
                ld hl, (msg_par)
                ld de, me
                call copy_nick
hn_show:
                ld a, 0
                ld hl, f_nick
                jp say

h_topic:
                ld hl, (msg_par)
                call win_for
                ld hl, f_topic
                jp say

h_mode:
                ld hl, (msg_par)
                call win_for
                ld hl, f_mode
                jp say

h_error:
                ld a, PHASE_DEAD
                ld (phase), a
                ld a, 0
                ld hl, f_numeric
                call say
                ret

h_001:
                ld a, PHASE_LIVE
                ld (phase), a
                ld a, 0
                ld hl, f_numeric
                call say
                ld hl, autojoin
                ld a, (hl)
                or a
                ret z
                push hl
                ld (fmt_arg), hl
                ld hl, w_join
                call wire
                pop hl
                ld (hl), 0
                ret

h_433:
                ld a, (phase)
                cp PHASE_TRY0
                jr c, h43_say
                cp PHASE_TRY3
                jr nc, h43_say
                ld hl, me
                call append_us
                ld a, (phase)
                inc a
                ld (phase), a
                ld a, 0
                ld hl, f_numeric
                call say
                ld hl, w_nick_me
                call wire
                jp paint_status
h43_say:
                ld a, 0
                ld hl, f_numeric
                jp say
h4_show:
                ld a, 0
                ld hl, f_numeric
                jp say

h_332:
                ld hl, (msg_par)
                call win_for
                ld hl, f_topic
                jp say

h_353:
                ld hl, (msg_par + 2)
                call win_for
                ld hl, f_users
                jp say

h_numeric:
                ld a, 0
                ld hl, f_numeric
                jp say

ctcp_tab:
                db "ACTION", 0
                dw t_action
                db "VERSION", 0
                dw t_version
                db "PING", 0
                dw t_ping
                db 0

ctcp_split:
                ld hl, (msg_par + 2)
                ld a, (hl)
                cp 01h
                jr nz, ctcp_plain
                inc hl
                ld (ctcp_ptr), hl
                call ctcp_word
                ; HL = ctcp_cmd. Note on the server window, then look up a handler.
                push hl
                call ctcp_note
                pop hl
                ld c, 2
                ld de, ctcp_tab
                call lookup
                jr c, ctcp_plain
                ld bc, ctcp_done
                push bc
                jp (hl)
ctcp_done:
                ld a, 1
                ret
ctcp_plain:
                xor a
                ret

; HL = ctcp command name (e.g. VERSION). Prints on window 0.
ctcp_note:
                ld (fmt_arg), hl
                xor a
                ld hl, f_ctcp
                jp say

t_action:
                ld hl, (ctcp_ptr)
                ld (fmt_arg), hl
                ld hl, (msg_par)
                call win_for
                ld hl, f_action
                call say
                ret

t_version:
                ld hl, w_version
                call wire
                ret

t_ping:
                ld hl, (ctcp_ptr)
                ld (fmt_arg), hl
                ld hl, w_ctcp_ping
                call wire
                ret

ctcp_word:
                ld hl, (ctcp_ptr)
                ld de, ctcp_cmd
cw:
                ld a, (hl)
                cp 01h
                jr z, cw_end
                cp ' '
                jr z, cw_end
                ld (de), a
                inc hl
                inc de
                jr cw
cw_end:
                ld a, 0
                ld (de), a
                inc hl
                ld (ctcp_ptr), hl
                ld hl, ctcp_cmd
                ret

name_is_me:
                ex de, hl
                ld hl, me
                jp name_eq

append_us:
                ld a, (hl)
                inc hl
                or a
                jr nz, append_us
                dec hl
                ld (hl), '_'
                inc hl
                ld (hl), 0
                ret

copy_nick:
                ld b, 31
cn_loop:
                ld a, (hl)
                or a
                jr z, cn_end
                cp ' '
                jr z, cn_end
                ld (de), a
                inc hl
                inc de
                djnz cn_loop
cn_end:
                xor a
                ld (de), a
                ret

ctcp_cmd:       ds 16, 0
ctcp_ptr:       dw 0
