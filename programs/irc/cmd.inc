KB_GROUND       equ 0
KB_ESC          equ 1
KB_CSI          equ 2

; A = key. C = line submitted.
key:
                ld (key_ch), a
                ld hl, kb_state
                ld b, (hl)
                ld a, b
                cp KB_GROUND
                jr nz, key_esc
                ld a, (key_ch)
                cp 1Bh
                jr z, key_toesc
                cp 0Dh
                jr z, key_submit
                cp 0Ah
                jr z, key_submit
                cp 08h
                jr z, key_rubout
                cp 20h
                jr c, key_done
                jp k_insert
key_toesc:
                ld hl, kb_state
                ld a, KB_ESC
                ld (hl), a
key_done:
                or a
                ret
key_esc:
                ld a, b
                cp KB_ESC
                jr nz, key_csi
                ld a, (key_ch)
                cp '['
                jr z, key_tocsi
                ld hl, kb_state
                ld a, KB_GROUND
                ld (hl), a
                or a
                ret
key_csi:
                ld hl, kb_state
                ld a, KB_GROUND
                ld (hl), a
                ld e, a
                ld hl, csi_tab
                call csi_find
                jp (hl)
key_tocsi:
                ld a, KB_CSI
                ld (hl), a
                or a
                ret

csi_find:
                push hl
csi_f:
                ld a, (hl)
                or a
                jr z, csi_miss
                cp e
                jr z, csi_hit
                inc hl
                inc hl
                inc hl
                jr csi_f
csi_hit:
                inc hl
                ld a, (hl)
                inc hl
                ld h, (hl)
                ld l, a
                ret
csi_miss:
                pop hl
                or a
                ret

key_submit:
                call submit
                scf
                ret

key_rubout:
                ld a, (inp_len)
                or a
                ret z
                dec a
                ld (inp_len), a
                call paint_input
                jp out_flush

k_insert:
                ld a, (inp_len)
                cp 255
                ret nc
                ld c, a
                ld hl, inp_buf
                ld a, c
                add a, l
                ld l, a
                jr nc, ki_s
                inc h
ki_s:
                ld a, (key_ch)
                ld (hl), a
                ld hl, inp_len
                inc (hl)
                ld a, (inp_len)
                cp 64
                jr nc, ki_repaint
                call out_byte
                jp out_flush
ki_repaint:
                call paint_input
                jp out_flush

submit:
                ld hl, inp_buf
                ld a, (inp_len)
                ld b, a
                ld c, 0
                add hl, bc
                ld (hl), 0
                ld a, (inp_len)
                or a
                jr z, sub_empty
                ld a, (inp_view)
                or a
                call nz, win_show_cur
                ld hl, inp_buf
                ld a, (hl)
                cp '/'
                jr nz, sub_plain
                inc hl
                ex de, hl
                push de
                call skip_word_de
                ex de, hl
                ld (fmt_arg), hl
                pop hl
                ld b, (hl)
                push bc
                push hl
                ld c, 4
                ld hl, cmd_tab
                pop de
                ex de, hl
                call lookup
                jr c, sub_unk
                push hl
                pop de
                pop hl
                pop bc
                ld (hl), b
                ex de, hl
                call sub_reset
                jp (hl)
sub_unk:
                pop hl
                pop bc
                ld (hl), b
                call sub_reset
                ld a, 0
                ld hl, f_err
                jp say
sub_plain:
                ld hl, inp_buf
                ld (fmt_arg), hl
                call sub_reset
                jp c_say
sub_reset:
                xor a
                ld (inp_len), a
                ret
sub_empty:
                call sub_reset
                call paint_input
                call out_flush
                jp sub_kick
sub_kick:
                call tr_kick
se_pump:
                call net_pump
                jr nz, se_pump
                ret

win_show_cur:
                ld a, (cur_win)
                jp win_show

skip_word_de:
                ld a, (de)
                or a
                ret z
                cp ' '
                ret z
                inc de
                jr skip_word_de

c_wire:
                jp wire

c_say:
                ld a, (cur_win)
                call whdr_ptr
                ld a, (hl)
                or a
                jr z, cs_notarg
                ld a, (cur_win)
                ld hl, w_privmsg
                call wire
                ld a, (cur_win)
                ld hl, f_own
                jp say
cs_notarg:
                ld a, 0
                ld hl, f_notarg
                jp say

c_msg:
                ld hl, w_msg
                call wire
                ld a, 0
                ld hl, f_sent
                jp say

c_query:
                call win_query
                xor a
                jp win_show

c_me:
                ld a, (cur_win)
                call whdr_ptr
                ld a, (hl)
                or a
                jr z, cs_notarg
                ld hl, w_action
                call wire
                ld a, (cur_win)
                ld hl, f_ownact
                jp say

c_join:
                ld c, 1
cj_try:
                ld a, c
                call whdr_ptr
                ld a, (hl)
                or a
                jr z, cj_ok
                inc c
                ld a, c
                cp 3
                jr c, cj_try
                ld a, 0
                call win_show
                call sub_reset
                ld hl, f_joinfull
                call say
                jp sub_kick
cj_ok:
                push hl
                ld hl, (fmt_arg)
                ld de, hl
                call skip_ws_de
                ex de, hl
                pop de
                push de
cj_copy:
                ld a, (hl)
                or a
                jr z, cj_copy_done
                cp ' '
                jr z, cj_copy_done
                cp 0Dh
                jr z, cj_copy_done
                cp 0Ah
                jr z, cj_copy_done
                ld (de), a
                inc hl
                inc de
                jr cj_copy
cj_copy_done:
                ld a, 0
                ld (de), a
                pop hl
cj_wire:
                ld hl, w_join
                jp wire

c_quit:
                ld hl, (fmt_arg)
                ld de, hl
                ld a, (de)
                or a
                jr nz, cq_msg
                ld hl, quit_def
cq_msg:
                ld hl, w_quit
                call wire
                call tr_close
                call win_exit
                jp exit0

c_win:
                ld de, (fmt_arg)
                call skip_ws_de
                ld a, (de)
                cp '0'
                jr c, cw_bad
                cp '3'
                jr nc, cw_bad
                sub '0'
                jp win_show
cw_bad:
                or a
                ret

c_clear:
                jp win_clear

c_help:
                ld a, 0
                ld hl, f_help
                jp say

skip_ws_de:
                ld a, (de)
                cp ' '
                ret nz
                inc de
                jr skip_ws_de

csi_tab:
                db 'D', 0
                dw key_rubout
                db 'B', 0
                dw win_cycle
                db 'C', 0
                dw win_page
                db 0

cmd_tab:
                db "JOIN", 0
                dw c_join, 0
                db "PART", 0
                dw c_wire, w_part
                db "MSG", 0
                dw c_msg, 0
                db "QUERY", 0
                dw c_query, 0
                db "ME", 0
                dw c_me, 0
                db "NICK", 0
                dw c_wire, w_nick
                db "NAMES", 0
                dw c_wire, w_names
                db "WHOIS", 0
                dw c_wire, w_whois
                db "QUOTE", 0
                dw c_wire, w_quote
                db "WIN", 0
                dw c_win, 0
                db "CLEAR", 0
                dw c_clear, 0
                db "HELP", 0
                dw c_help, 0
                db "QUIT", 0
                dw c_quit, 0
                db 0

f_err:          db "*** unknown command", 0
f_notarg:       db "*** no target", 0
f_own:          db "<", F_ME, "> ", F_ARG, 0
f_ownact:       db "* ", F_ME, " ", F_ARG, 0
f_sent:         db "-> *", F_ARG1, "* ", F_ARGR, 0
f_joinfull:     db "*** no free channel window", 0
f_help:         db "/join /part /msg /query /me /nick /names /whois /quote /win /clear /help /quit", 0
quit_def:       db "c5nix on a CP-500", 0
