W_NAME          equ 0
W_HEAD          equ 24
W_COUNT         equ 25
W_VIEW          equ 26
W_ACT           equ 27
W_ROWS          equ 28
W_SIZE          equ 32

; A = window 0..2. HL = header.
whdr_ptr:
                rrca
                rrca
                rrca
                ld l, a
                ld h, high whdr
                ret

; A = n, C = row. HL = row address.
row_addr:
                ld b, a
                add a, a
                add a, a
                add a, a
                sub b
                ld b, a
                ld a, c
                and 3
                rrca
                rrca
                ld l, a
                ld a, c
                srl a
                srl a
                add a, b
                add a, high win_ring
                ld h, a
                ret

win_for:
                ld (wf_at), hl
                ld a, (hl)
                cp '#'
                jr z, wf_chan
                cp '&'
                jr z, wf_chan
                cp '+'
                jr z, wf_chan
                cp '!'
                jr z, wf_chan
                xor a
                ret
wf_chan:
                ld c, 1
wf_try:
                ld a, c
                call whdr_ptr
                ld a, (hl)
                or a
                jr z, wf_next
                push hl
                pop de
                ld hl, (wf_at)
                push bc
                call name_eq
                pop bc
                jr c, wf_next
                ld a, c
                ret
wf_next:
                inc c
                ld a, c
                cp 3
                jr c, wf_try
                xor a
                ret

win_claim:
                push hl
                ld c, 1
wc_try:
                ld a, c
                call whdr_ptr
                push hl
                pop de
                pop hl
                push hl
                push de
                ld a, (de)
                or a
                jr z, wc_free
                push bc
                call name_eq
                pop bc
                jr nz, wc_next
                pop de
                pop hl
                pop hl
                ld a, c
                or a
                ret
wc_next:
                pop de
                pop hl
                inc c
                ld a, c
                cp 3
                jr c, wc_try
                pop hl
                scf
                ret
wc_free:
                pop de
                pop hl
                push hl
                push de
                ld a, c
                push af
                ld bc, 23
                ldir
                pop af
                pop de
                pop hl
                pop hl
                or a
                ret

win_release:
                push hl
                ld b, 1
wr_try:
                ld a, b
                call whdr_ptr
                push hl
                pop de
                pop hl
                push hl
                push de
                ld a, (de)
                or a
                jr z, wr_next
                call name_eq
                jr nz, wr_next
                pop de
                pop hl
                push bc
                call win_clear_hdr
                pop bc
                ld a, (cur_win)
                cp b
                jr nz, wr_out
                xor a
                call win_show
wr_out:
                xor a
                ret
wr_next:
                pop de
                pop hl
                inc b
                ld a, b
                cp 3
                jr c, wr_try
                ret

win_clear_hdr:
                push af
                ld a, b
                call whdr_ptr
                ld bc, W_SIZE
                xor a
                ld (hl), a
                inc hl
                dec bc
                jr wr_clr
wr_clr:
                ldir
                pop af
                ret

win_query:
                push de
                ld a, 0
                call whdr_ptr
                pop de
                ld bc, 23
                ldir
                ld a, 0
                ld (hl), a
                ret

; A = window
win_show:
                ld (cur_win), a
                call whdr_ptr
                push hl
                ld de, W_VIEW
                add hl, de
                xor a
                ld (hl), a
                pop hl
                push hl
                ld de, W_ACT
                add hl, de
                xor a
                ld (hl), a
                pop hl
                ld hl, esc2j
                call out_str
                call paint_status
                ld b, 0
ws_row:
                ld a, b
                cp 14
                jr nc, ws_done
                push bc
                call ws_draw_row
                call out_flush
                pop bc
                inc b
                jr ws_row
ws_done:
                call paint_input
                jp out_flush

ws_draw_row:
                ld a, (cur_win)
                call whdr_ptr
                ld de, W_HEAD
                add hl, de
                ld a, (hl)
                push af
                ld a, (cur_win)
                call whdr_ptr
                ld de, W_COUNT
                add hl, de
                ld a, (hl)
                ld d, a
                inc hl
                ld a, (hl)
                ld e, a
                pop af
                ld c, a
                ld a, e
                add a, b
                cp d
                ret nc
                ld a, c
                sub d
                jr nc, ws_hc
                add a, W_ROWS
ws_hc:
                add a, e
                add a, b
ws_mod:
                cp W_ROWS
                jr c, ws_slot
                sub W_ROWS
                jr ws_mod
ws_slot:
                ld c, a
                push bc
                ld a, (cur_win)
                call row_addr
                pop bc
                push hl
                ld a, b
                call out_at
                pop hl
                ld bc, 64
                jp out_mem

win_cycle:
                ld a, (cur_win)
                inc a
                cp 3
                jr c, wc_go
                xor a
wc_go:
                call win_show
                or a
                ret

win_page:
                ld a, (cur_win)
                call whdr_ptr
                push hl
                ld de, W_VIEW
                add hl, de
                ld a, (hl)
                pop hl
                add a, 14
                push hl
                push af
                ld de, W_VIEW
                add hl, de
                pop af
                ld (hl), a
                pop hl
                ld b, a
                push hl
                ld de, W_COUNT
                add hl, de
                ld a, (hl)
                pop hl
                cp b
                jr nc, wp_ok
                xor a
                push hl
                push af
                ld de, W_VIEW
                add hl, de
                pop af
                ld (hl), a
                pop hl
wp_ok:
                jp win_show

win_clear:
                ld a, (cur_win)
                call whdr_ptr
                xor a
                push hl
                push af
                ld de, W_HEAD
                add hl, de
                pop af
                ld (hl), a
                pop hl
                push hl
                push af
                ld de, W_COUNT
                add hl, de
                pop af
                ld (hl), a
                pop hl
                push hl
                push af
                ld de, W_VIEW
                add hl, de
                pop af
                ld (hl), a
                pop hl
                jp win_show

win_exit:
                ld hl, esc_exit
                call out_str
                jp out_flush

; A = win, HL = format, DE = arg
say:
                ld (say_win), a
                push hl
                xor a
                ld (say_col), a
                ld (say_rows), a
                ld (san_state), a
                ld a, 0FFh
                ld (say_lastsp), a
                ld hl, say_byte
                ld (fmt_sink), hl
                pop hl
                push hl
                ld de, 0
                pop hl
                call fmt_run
                call say_commit
                ld a, (say_win)
                ld b, a
                ld a, (cur_win)
                cp b
                jr nz, say_hidden
                ld a, (cur_win)
                call whdr_ptr
                push hl
                ld de, W_VIEW
                add hl, de
                ld a, (hl)
                pop hl
                or a
                jr nz, say_more
                ld a, (cur_win)
                jp win_show
say_more:
                push hl
                ld de, W_COUNT
                add hl, de
                ld a, (hl)
                pop hl
                ld b, a
                push hl
                ld de, W_VIEW
                add hl, de
                ld a, (hl)
                pop hl
                cp b
                jr c, sm_ok
                ld a, b
sm_ok:
                push hl
                push af
                ld de, W_VIEW
                add hl, de
                pop af
                ld (hl), a
                pop hl
                call paint_status
                call paint_input
                call out_flush
                ret
say_hidden:
                ld a, b
                call whdr_ptr
                ld a, 1
                push hl
                push af
                ld de, W_ACT
                add hl, de
                pop af
                ld (hl), a
                pop hl
                call paint_status
                call paint_input
                call out_flush
                ret

say_byte:
                call san_byte
                ret c
                push af
                ld hl, say_col
                ld a, (hl)
                cp 64
                jr c, sb_room
                pop af
                push af
                call sb_fold
sb_room:
                pop af
                ld b, a
                push bc
                ld a, (say_win)
                call whdr_ptr
                push hl
                call sb_row_slot
                pop hl
                ld a, (say_win)
                call row_addr
                pop bc
                ld a, (say_col)
                ld e, a
                ld d, 0
                add hl, de
                ld a, b
                ld (hl), a
                cp ' '
                jr nz, sb_ns
                ld hl, say_col
                ld a, (hl)
                ld (say_lastsp), a
sb_ns:
                ld hl, say_col
                inc (hl)
                xor a
                ret

sb_row_slot:
                ld de, W_HEAD
                add hl, de
                ld c, (hl)
                ret

sb_put1:
                push af
                ld a, (say_win)
                call whdr_ptr
                push hl
                call sb_row_slot
                pop hl
                ld a, (say_win)
                call row_addr
                ld a, (say_col)
                ld e, a
                ld d, 0
                add hl, de
                pop af
                ld (hl), a
                ld hl, say_col
                inc (hl)
                ret

sb_fold:
                ld hl, say_col
                ld b, (hl)
                ld a, (say_lastsp)
                cp 0FFh
                jr z, sb_fhard
                cp b
                jr nc, sb_fhard
                ld c, a
                ld a, (say_rows)
                or a
                jr z, sb_fsoft
                ld a, c
                cp 2
                jr c, sb_fhard
sb_fsoft:
                ld (hl), c
                push bc
                call say_commit
                pop bc
                ld a, b
                sub c
                dec a
                ld b, a
                ld a, c
                inc a
                call sb_copy_tail
                xor a
                ld (say_lastsp), a
                ret
sb_fhard:
                call say_commit
                xor a
                ld (say_lastsp), a
                ret

sb_copy_tail:
                or a
                ret z
                push bc
                push af
                ld a, (say_win)
                call whdr_ptr
                ld de, W_HEAD
                add hl, de
                ld a, (hl)
                dec a
                jr nc, sb_ct_r
                ld a, W_ROWS - 1
sb_ct_r:
                ld c, a
                ld a, (say_win)
                call row_addr
                pop af
                ld e, a
                ld d, 0
                add hl, de
                ex de, hl
                pop bc
sb_ct:
                ld a, b
                or a
                ret z
                ld hl, say_col
                ld a, (hl)
                cp 64
                jr c, sb_ct_emit
                call say_commit
                xor a
                ld (say_lastsp), a
sb_ct_emit:
                ld a, (de)
                push bc
                push de
                call sb_put1
                pop de
                pop bc
                inc de
                dec b
                jr sb_ct

say_commit:
                ld a, (say_col)
                or a
                jr z, sc_done
                push af
                ld a, (say_win)
                call whdr_ptr
                call sb_row_slot
                ld a, (say_win)
                call row_addr
                pop af
                cp 64
                jr nc, sc_pad_done
                ld e, a
                ld d, 0
                add hl, de
                ld (hl), 0
                inc hl
                ld a, (say_col)
                ld b, a
                ld a, 64
                sub b
                ld b, a
                cp 64
                jr nc, sc_pad_done
                or b
                jr z, sc_pad_done
sc_pad:
                ld (hl), ' '
                inc hl
                djnz sc_pad
sc_pad_done:
                ld a, (say_win)
                call whdr_ptr
                ld de, W_HEAD
                add hl, de
                ld a, (hl)
                inc a
                cp W_ROWS
                jr c, sc_h
                xor a
sc_h:
                ld (hl), a
                ld a, (say_win)
                call whdr_ptr
                ld de, W_COUNT
                add hl, de
                ld a, (hl)
                cp W_ROWS
                jr nc, sc_cnt_done
                inc (hl)
sc_cnt_done:
                ld hl, say_rows
                inc (hl)
                ld a, (say_win)
                ld b, a
                ld a, (cur_win)
                cp b
                jr nz, sc_done
                ld a, (say_win)
                call whdr_ptr
                push hl
                ld de, W_VIEW
                add hl, de
                ld a, (hl)
                pop hl
                or a
                jr nz, sc_done
                ld b, 0
                call ws_draw_row
                call out_flush
sc_done:
                ld a, (say_rows)
                or a
                jr z, sc_zcol
                call sc_indent
                ret
sc_zcol:
                xor a
                ld (say_col), a
                ret

sc_indent:
                ld a, (say_win)
                call whdr_ptr
                push hl
                call sb_row_slot
                pop hl
                ld a, (say_win)
                call row_addr
                ld a, ' '
                ld (hl), a
                inc hl
                ld (hl), a
                ld a, 2
                ld (say_col), a
                ret

commit_row:
                ld a, (say_win)
                call whdr_ptr
                push hl
                ld de, W_COUNT
                add hl, de
                ld a, (hl)
                pop hl
                or a
                ret z
                dec a
                cp 14
                ret c
                sub 13
                ld b, a
                ld a, (say_win)
                call whdr_ptr
                ld a, b
                ld de, W_VIEW
                add hl, de
                ld (hl), a
                ret

paint_status:
                ld a, 14
                call out_at
                ld hl, esc_k
                call out_str
                ld a, '-'
                call ps_byte
                ld a, '['
                call ps_byte
                ld a, (cur_win)
                inc a
                call ps_digit
                ld a, ']'
                call ps_byte
                ld a, ' '
                call ps_byte
                ld a, (cur_win)
                call whdr_ptr
                ld a, (hl)
                or a
                jr nz, ps_name
                ld a, '-'
                call ps_byte
                jr ps_sep
ps_name:
                push hl
                ld b, 23
ps_n:
                ld a, (hl)
                or a
                jr z, ps_nend
                call ps_byte
                inc hl
                djnz ps_n
ps_nend:
                pop hl
ps_sep:
                ld a, ' '
                call ps_byte
                call ps_byte
                call ps_byte
                ld hl, me
                ld b, 31
ps_me:
                ld a, (hl)
                or a
                jr z, ps_act
                call ps_byte
                inc hl
                djnz ps_me
ps_act:
                call ps_act_list
                ld a, ' '
                call ps_byte
                call ps_byte
                ld a, (phase)
                cp PHASE_DEAD
                jr z, ps_offword
                ld a, 'o'
                call ps_byte
                ld a, 'n'
                call ps_byte
                ld a, 'l'
                call ps_byte
                ld a, 'i'
                call ps_byte
                ld a, 'n'
                call ps_byte
                ld a, 'e'
                call ps_byte
                jr ps_view
ps_offword:
                ld hl, ps_off
                call ps_str
ps_view:
                ld a, (cur_win)
                call whdr_ptr
                push hl
                ld de, W_VIEW
                add hl, de
                ld a, (hl)
                pop hl
                or a
                jr z, ps_done
                ld hl, ps_more
                call ps_str
ps_done:
                ret

ps_str:
                ld a, (hl)
                or a
                ret z
                call ps_byte
                inc hl
                jr ps_str

ps_act_list:
                ld b, 0
                ld c, 0
pa_chk:
                ld a, b
                cp 3
                ret nc
                push bc
                ld a, b
                call whdr_ptr
                push hl
                ld de, W_ACT
                add hl, de
                ld a, (hl)
                pop hl
                ld e, a
                pop bc
                ld a, e
                or a
                jr z, pa_adv
                ld a, c
                or a
                jr nz, pa_com
                ld a, ' '
                call ps_byte
                call ps_byte
                call ps_byte
                call ps_byte
                ld a, 'a'
                call ps_byte
                ld a, 'c'
                call ps_byte
                ld a, 't'
                call ps_byte
                ld a, ':'
                call ps_byte
                jr pa_num
pa_com:
                ld a, ','
                call ps_byte
pa_num:
                ld a, b
                call ps_digit
                ld c, 1
pa_adv:
                inc b
                jr pa_chk

ps_digit:
                add a, '0'
                call ps_byte
                ret

ps_byte:
                push hl
                push bc
                call out_byte
                pop bc
                pop hl
                ret

paint_input:
                ld a, 15
                call out_at
                ld hl, esc_k
                call out_str
                ld a, '>'
                call out_byte
                ld a, ' '
                call out_byte
                ld hl, inp_buf
                ld a, (inp_len)
                ld b, a
                ld a, 61
                cp b
                jr nc, pi_all
                sub 61
                ld c, a
                add hl, bc
                ld b, 61
pi_all:
                ld a, b
                or a
                ret z
                ld c, a
                call out_mem
                ret

key_read:
                call out_flush
                ld c, SYS_READ
                ld de, 0
                ld hl, key_byte
                ld ix, 1
                rst 08h
                ld a, (key_byte)
                or a
                ret

out_byte:
                ld hl, (out_ptr)
                ld de, out_buf + 512
                or a
                sbc hl, de
                call z, out_flush
                ld hl, (out_ptr)
                ld (hl), a
                inc hl
                ld (out_ptr), hl
                ret
out_str:
                ld a, (hl)
                or a
                ret z
                push hl
                call out_byte
                pop hl
                inc hl
                jr out_str
out_str0:
                ld a, (hl)
                or a
                ret z
                push hl
                call out_byte
                pop hl
                inc hl
                jr out_str0
out_at:
                push af
                ld a, 1Bh
                call out_byte
                ld a, '['
                call out_byte
                pop af
                inc a
                call out_dec
                ld a, 'H'
                jp out_byte
out_dec:
                cp 10
                jr c, od1
                push af
                ld a, '1'
                call out_byte
                pop af
                sub 10
od1:
                add a, '0'
                jp out_byte
out_mem:
                ld a, (hl)
                push hl
                call out_byte
                pop hl
                inc hl
                dec bc
                ld a, b
                or c
                jr nz, out_mem
                ret
out_flush:
                ld hl, (out_ptr)
                ld de, out_buf
                or a
                sbc hl, de
                ld a, h
                or l
                ret z
                ld c, l
                ld b, h
                push bc
                ld c, SYS_WRITE
                ld de, 1
                ld hl, out_buf
                pop ix
                rst 08h
                ld hl, out_buf
                ld (out_ptr), hl
                ret

esc2j:          db 1Bh, "[2J", 0
esc_k:          db 1Bh, "[K", 0
esc_exit:       db 1Bh, "[2J", 1Bh, "[H", 0
ps_on:          db "online", 0
ps_off:         db "offline", 0
ps_more:        db " more", 0
