; Format interpreter, sanitizer, name and table lookup.

F_NICK          equ 01h
F_PAR           equ 02h
F_LAST          equ 03h
F_REST          equ 04h
F_ME            equ 05h
F_WIN           equ 06h
F_ARG           equ 07h
F_ARG1          equ 08h
F_ARGR          equ 09h
F_ARG1W         equ 0Ah
F_CTCP          equ 0Bh
F_CMD           equ 0Ch

SAN_GROUND      equ 0
SAN_LEAD        equ 1
SAN_SKIP        equ 2
SAN_COLOR       equ 3

fmt_run:
                ld (fmt_arg), de
fr_loop:
                ld a, (hl)
                inc hl
                or a
                ret z
                cp 20h
                jr nc, fr_lit
                push hl
                call fr_dir
                pop hl
                jr fr_loop
fr_lit:
                call fmt_emit_a
                jr fr_loop

fr_dir:
                dec hl
                ld a, (hl)
                inc hl
                cp F_NICK
                jp z, fr_nick
                cp F_PAR
                jp z, fr_par
                cp F_LAST
                jp z, fr_last
                cp F_REST
                jp z, fr_rest
                cp F_ME
                jp z, fr_me
                cp F_WIN
                jp z, fr_win
                cp F_ARG
                jp z, fr_arg
                cp F_ARG1
                jp z, fr_arg1
                cp F_ARGR
                jp z, fr_argr
                cp F_ARG1W
                jp z, fr_arg1w
                cp F_CTCP
                jp z, fr_ctcp
                cp F_CMD
                jp z, fr_cmd
                ret

fr_nick:        ld hl, msg_nick
                jp fr_str
fr_me:          ld hl, me
                jp fr_str
fr_win:
                ld a, (cur_win)
                call whdr_ptr
                ld de, W_NAME
                add hl, de
                jp fr_str
fr_arg:         ld hl, (fmt_arg)
                jp fr_str
; First argument word only (until space). fr_str would emit the rest
; of the line and produced "PRIVMSG bob secret :secret".
fr_arg1:
                ld hl, (fmt_arg)
                call skip_ws
fr_word:
                ld a, (hl)
                or a
                ret z
                cp ' '
                ret z
                push hl
                call fmt_emit_a
                pop hl
                inc hl
                jr fr_word
fr_argr:
                ld hl, (fmt_arg)
                call skip_ws
                call skip_word
                call skip_ws
                jp fr_str
fr_arg1w:
                ld hl, (fmt_arg)
                call skip_ws
                ld a, (hl)
                or a
                jr nz, fr_word
                ld a, (cur_win)
                call whdr_ptr
                ld de, W_NAME
                add hl, de
                jp fr_str
fr_ctcp:
                ld a, 01h
                jp fmt_emit_a
fr_cmd:         ld hl, msg_cmd
                jp fr_str
fr_par:
                ld a, (hl)
                inc hl
                call msg_param
                ret nc
                ld h, d
                ld l, e
                jp fr_str
fr_last:
                ld a, (msg_n)
                dec a
                call msg_param
                ret nc
                ld h, d
                ld l, e
                jp fr_str
fr_str:
                ld a, (hl)
                or a
                ret z
                push hl
                call fmt_emit_a
                pop hl
                inc hl
                jr fr_str
fr_rest:
                ld a, (hl)
                inc hl
                ld b, a
fr_rs:
                ld a, (msg_n)
                cp b
                ret c
                push bc
                ld a, b
                call msg_param
                pop bc
                ret nc
                push bc
                ld h, d
                ld l, e
                push hl
                call fr_str
                pop hl
                pop bc
                inc b
                ld a, (msg_n)
                cp b
                ret c
                ld a, ' '
                call fmt_emit_a
                jr fr_rs

msg_param:
                cp 15
                ret nc
                ld e, a
                ld d, 0
                ld hl, msg_par
                add hl, de
                add hl, de
                ld e, (hl)
                inc hl
                ld d, (hl)
                ld a, e
                or d
                ret z
                scf
                ret

skip_ws:
                ld a, (hl)
                cp ' '
                ret nz
                inc hl
                jr skip_ws

skip_word:
                ld a, (hl)
                or a
                ret z
                cp ' '
                ret z
                inc hl
                jr skip_word

call_hl:
                jp (hl)

fmt_emit_a:
                push hl
                ld hl, (fmt_sink)
                call call_hl
                pop hl
                ret

san_byte:
                ld hl, san_state
                ld b, (hl)
                cp 03h
                jp z, san_color
                cp 20h
                jp nc, san_ok
                cp 10h
                jp nc, san_drop
                ld hl, san_state
                ld a, b
                or a
                jp nz, san_utf
san_drop:
                scf
                ret
san_ok:
                ld hl, san_state
                push af
                xor a
                ld (hl), a
                pop af
                or a
                ret
san_utf:
                dec a
                jp nz, san_u2
                cp 0C2h
                jp z, san_ld2
                cp 0C3h
                jp z, san_ld3
                ld hl, san_state
                ld (hl), SAN_SKIP
                ld hl, san_aux
                ld (hl), 1
                ld a, '?'
                xor a
                ret
san_ld2:
                ld hl, san_state
                ld (hl), SAN_LEAD
                ld hl, san_aux
                ld (hl), 0C2h
                scf
                ret
san_ld3:
                ld hl, san_state
                ld (hl), SAN_LEAD
                ld hl, san_aux
                ld (hl), 0C3h
                scf
                ret
san_u2:
                dec a
                jp nz, san_u3
                cp 80h
                jp c, san_rst
                cp 0C0h
                jp nc, san_rst
                ld hl, san_aux
                ld b, (hl)
                ld hl, san_state
                xor a
                ld (hl), a
                ld a, b
                cp 0C3h
                jr nz, san_ok2
                add a, 40h
san_ok2:
                or a
                ret
san_rst:
                ld hl, san_state
                xor a
                ld (hl), a
                jp san_byte
san_u3:
                cp 80h
                jp c, san_rst
                cp 0C0h
                jp nc, san_rst
                ld hl, san_aux
                dec (hl)
                ld a, (hl)
                or a
                jp nz, san_drop
                ld hl, san_state
                xor a
                ld (hl), a
                scf
                ret
san_color:
                ld hl, san_state
                ld (hl), SAN_COLOR
                ld hl, san_aux
                ld (hl), 2
                scf
                ret

lookup:
                push de
lu_row:
                ld a, (de)
                or a
                jp z, lu_miss
                push hl
                push de
lu_cmp:
                ld a, (de)
                or a
                jp z, lu_hit
                push af
                ld a, (hl)
                call fold_char
                ld b, a
                pop af
                call fold_char
                cp b
                jp nz, lu_adv
                inc hl
                inc de
                jr lu_cmp
lu_hit:
                inc de
                ld a, (de)
                ld l, a
                inc de
                ld a, (de)
                ld h, a
                push hl
                ld a, c
                cp 4
                jr c, lu_hit_1
                ; Second payload word (format for c_wire). Not IX: RST 08h
                ; syscalls use IX as the byte count.
                inc de
                ld a, (de)
                ld (wire_fmt), a
                inc de
                ld a, (de)
                ld (wire_fmt + 1), a
lu_hit_1:
                pop hl
                pop de
                pop bc
                pop de
                or a
                ret
lu_adv:
                pop de
                pop hl
lu_skip_name:
                ld a, (de)
                or a
                jr z, lu_skip_pay
                inc de
                jr lu_skip_name
lu_skip_pay:
                inc de
                ld b, c
                or b
                jr z, lu_row
lu_skip_pl:
                inc de
                djnz lu_skip_pl
                jp lu_row
lu_miss:
                pop de
                scf
                ret

name_eq:
                push hl
                push de
neq_loop:
                ld a, (de)
                or a
                jp z, neq_end_de
                push af
                ld a, (hl)
                or a
                jp z, neq_diff_af
                call fold_char
                ld b, a
                pop af
                call fold_char
                cp b
                jp nz, neq_diff
                inc hl
                inc de
                jr neq_loop
neq_end_de:
                ld a, (hl)
                or a
                jp nz, neq_diff
                pop de
                pop hl
                or a
                ret
neq_diff_af:
                pop af
neq_diff:
                pop de
                pop hl
                or a
                scf
                ret

fold_char:
                cp 'A'
                jr c, fold_low
                cp 'Z' + 1
                jr nc, fold_low
                add a, 20h
fold_low:
                cp '{'
                jr nz, fold1
                ld a, '['
                ret
fold1:
                cp '}'
                jr nz, fold2
                ld a, ']'
                ret
fold2:
                cp '|'
                jr nz, fold3
                ld a, '\'
                ret
fold3:
                cp '~'
                jr nz, fold4
                ld a, '^'
fold4:
                ret
