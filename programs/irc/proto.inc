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
                ld (hl), a
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
                jr nz, np_z
                call np_first_line
                ld a, (np_hit)
                or a
                ret nz
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

np_first_line:
                ld hl, rl_buf
                ld bc, (rl_len)
nfl_scan:
                ld a, b
                or c
                ret z
                ld a, (hl)
                cp 0Ah
                jr z, nfl_cut
                cp 0Dh
                jr z, nfl_cut
                inc hl
                dec bc
                jr nfl_scan
nfl_cut:
                ld (hl), 0
                push hl
                inc hl
                ld a, (hl)
                cp 0Ah
                jr nz, nfl_off
                inc hl
nfl_off:
                ld de, rl_buf
                or a
                sbc hl, de
                ld a, l
                ld (tr_pos), a
                pop hl
                push hl
                call line_dispatch
                pop hl
                xor a
                ld (tr_state), a
                xor a
                ld hl, rl_len
                ld (hl), a
                inc hl
                ld (hl), a
                ld a, 1
                ld (np_hit), a
                ld a, RL_READY
                ld (rl_state), a
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
                push hl
                ld hl, wire_byte
                ld (fmt_sink), hl
                pop hl
                push hl
                ld hl, sl_buf
                ld (sl_ptr), hl
                pop hl
                call fmt_run
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

wire_byte:
                cp 20h
                jr nc, wb_ok
                cp 7Fh
                jr z, wb_q
                ld a, '?'
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
f_action:       db "* ", F_NICK, " ", F_LAST, 0
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
                call hj_channel
                call win_for
                push af
                or a
                jr z, hp_fmt
                call win_show
hp_fmt:
                pop af
                ld hl, f_chanmsg
                or a
                jr nz, hp_go
                ld hl, f_privmsg
hp_go:
                jp say

h_notice:
                ld a, 0
                ld hl, f_notice
                jp say

h_join:
                ld hl, (msg_par)
                ld e, (hl)
                inc hl
                ld d, (hl)
                push de
                ld hl, de
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
                pop hl
                call name_is_me
                jr nz, hj_other
                call hj_channel
                call win_claim
                jr c, hj_other
                call win_show
hj_other:
                call hj_channel
                call win_for
                push af
                or a
                jr z, ho_say
                call win_show
ho_say:
                pop af
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
                ld hl, (msg_par)
                call name_is_me
                jr nz, hp_other
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
                ld hl, (msg_par)
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
                jr z, h1_done
                push hl
                ld hl, w_join
                call wire
                pop hl
                ld (hl), 0
h1_done:
                ld a, 0
                call win_show
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
                ld a, 0
                call win_show
                ret
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
                ld c, 2
                ld hl, ctcp_tab
                ex de, hl
                call lookup
                jr c, ctcp_plain
                jp (hl)
ctcp_plain:
                xor a
                ret

t_action:
                ld hl, (msg_par)
                call win_for
                ld hl, f_action
                jp say

t_version:
                ld hl, w_version
                jp wire

t_ping:
                ld hl, w_ctcp_ping
                jp wire

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
                ld bc, 31
                ldir
                ld (hl), a
                ret

ctcp_cmd:       ds 16, 0
ctcp_ptr:       dw 0
