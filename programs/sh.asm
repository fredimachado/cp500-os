; /bin/sh. Linked at ORIGIN and packed by mkreloc. The line buffer is bss.

                include "cp500.inc"

                org ORIGIN

shell:
                ld c, SYS_WAIT
                ld de, 0FEh
                rst 08h
                jr nc, shell
                ld c, SYS_WRITE
                ld de, 1
                ld hl, prompt_seq
                ld ix, prompt_end - prompt_seq
                rst 08h
                ld iy, line
                xor a
                ld (cur_pos), a
                ld (esc_state), a
                ld hl, line
                ld bc, 128
shell_clr:
                ld (hl), a
                inc hl
                dec bc
                ld a, b
                or c
                jr nz, shell_clr
                ld a, 0FFh
                ld (hist_pos), a

read_loop:
                dec sp
                ld hl, 0
                add hl, sp
                push hl
                ld c, SYS_READ
                ld de, 0
                ld ix, 1
                rst 08h
                pop hl
                ld a, (hl)
                inc sp
                cp 0Dh
                jr z, got_line
                call edit_key
                jp read_loop

got_line:
                xor a
                ld (iy + 0), a
                ld a, 0Dh
                call write_byte
                ld a, (line)
                or a
                jp z, shell
                call hist_save
                ld a, (line)
                cp '>'
                jr nz, try_query
                ld a, (line + 1)
                cp ' '
                jr nz, run_path
                ld hl, line
                call strip_redir
                jp c, show_err
                jp shell

try_query:
                ld a, (line)
                cp '?'
                jr nz, run_path
                ld a, (line + 1)
                cp ' '
                jr nz, run_path
                ld hl, line
                call strip_redir
                jp c, show_err
                ld hl, line + 2
                ld a, (map_redir + 1)
                cp 1
                ld ix, 0
                jr z, try_query_go
                ld ix, map_redir
try_query_go:
                call spawn_line
                jp c, show_err
                ld hl, ok_text
                call write_str
                jp shell

run_path:
                ld hl, line
find_bar:
                ld a, (hl)
                or a
                jr z, run_one
                cp '!'
                jr z, run_pipe
                inc hl
                jr find_bar
run_one:
                ld hl, line
                call strip_redir
                jp c, show_err
                ld hl, line
                ld a, (map_redir + 1)
                cp 1
                ld ix, 0
                jr z, run_one_go
                ld ix, map_redir
run_one_go:
                call spawn_line
                jp c, show_err
                call fg_wait
                push af
                call fg_sync_clear
                pop af
report:
                or a
                jp z, read_loop
                push af
                ld a, 0Dh
                call write_byte
                pop af
                push af
                ld hl, exit_text
                call write_str
                pop af
                call write_dec
                ld a, 0Dh
                call write_byte
                jp read_loop

; "a ! b": the keyboard has no | key. a's fd 1 and b's fd 0 are the two pipe ends.
; The shell closes its copies so b sees end of file and a sees no reader.
run_pipe:
                ld (hl), 0
                inc hl
                ld (rhs), hl
                ld c, SYS_PIPE
                ld de, pfd
                rst 08h
                jp c, show_err
                ld hl, (pfd)
                ld a, l
                ld (map_b), a
                ld a, h
                ld (map_a + 1), a
                ld hl, line
                ld ix, map_a
                call spawn_line
                jr c, pipe_fail_a
                ld (tid_a), hl
                ld hl, (rhs)
                ld ix, map_b
                call spawn_line
                push af
                push hl
                call close_pfd
                pop hl
                pop af
                jr c, pipe_fail_b
                call fg_wait
                push af
                ld hl, (tid_a)
                call fg_wait
                pop af
                call fg_sync_clear
                jp report
pipe_fail_a:
                push af
                call close_pfd
                pop af
                jp show_err
pipe_fail_b:
                push af
                ld hl, (tid_a)
                call fg_wait
                pop af
                jp show_err

close_pfd:
                ld a, (pfd)
                call close_a
                ld a, (pfd + 1)
close_a:
                ld e, a
                ld d, 0
                ld c, SYS_CLOSE
                rst 08h
                ret

; HL = command text, IX = fd map. HL = task id, or carry and A = error.
spawn_line:
                call build_argv
                ret c
                call bind_path
                ld c, SYS_SPAWN
                ld hl, argv_blk
                rst 08h
                ret

; HL = task id. Makes it the console's foreground task, so BREAK ends it, and
; waits for it. A = its exit code. The kernel clears the foreground at exit.
fg_wait:
                push hl
                pop ix
                ld de, 1
                ld c, SYS_IOCTL
                ld hl, IOCTL_SETFG
                rst 08h
                push ix
                pop de
                ld c, SYS_WAIT
                rst 08h
                push hl
                ld c, SYS_GETPID
                rst 08h
                push hl
                pop ix
                ld de, 1
                ld c, SYS_IOCTL
                ld hl, IOCTL_SETFG
                rst 08h
                pop hl
                ld a, l
                or a
                ret

silent_mkdir:   db "/bin/mkdir", 0
silent_cp:      db "/bin/cp", 0
silent_mv:      db "/bin/mv", 0
silent_rm:      db "/bin/rm", 0
silent_ls:      db "/bin/ls", 0
silent_cat:     db "/bin/cat", 0

cmd_prefix:
                ld a, (de)
                or a
                ret z
                cp (hl)
                jr nz, cmd_pf_no
                inc de
                inc hl
                jr cmd_prefix
cmd_pf_no:
                or a
                ret

fg_sync_clear:
                xor a
                ld (esc_state), a
                ld (cur_pos), a
                ld (line), a
                ld iy, line
                call redraw_line
                ret

show_err:
                ld c, a
                push bc
                ld a, 0Dh
                call write_byte
                pop bc
                ld hl, err_table
err_find:
                ld a, (hl)
                or a
                jr z, err_other
                cp c
                jr z, err_hit
                inc hl
                inc hl
                inc hl
                jr err_find
err_hit:
                inc hl
                ld e, (hl)
                inc hl
                ld d, (hl)
                ex de, hl
                call write_str
                jr err_cr
err_other:
                ld hl, err_text
                call write_str
err_cr:
                ld a, 0Dh
                call write_byte
                jp shell

write_str:
                ld a, (hl)
                or a
                ret z
                push hl
                call write_byte
                pop hl
                inc hl
                jr write_str

write_dec:
                ld c, a
                xor a
                ld (line), a
                ld d, 100
                call dec_digit
                ld d, 10
                call dec_digit
                ld a, 1
                ld (line), a
                ld d, 1
dec_digit:
                ld e, 0
dec_sub:
                ld a, c
                cp d
                jr c, dec_out
                sub d
                ld c, a
                inc e
                jr dec_sub
dec_out:
                ld a, (line)
                or e
                ret z
                ld a, 1
                ld (line), a
                push bc
                ld a, e
                add a, '0'
                call write_byte
                pop bc
                ret

write_byte:
                ld (out_ch), a
                ld c, SYS_WRITE
                ld de, 1
                ld hl, out_ch
                ld ix, 1
                rst 08h
                ret

prompt_seq:
                db 0Dh, "sh>", 0Dh
prompt_end:
out_ch:         db 0
cr_byte:        db 0Dh

bin_lit:        db "/bin/"
bin_dir:        db "/bin", 0
map_a:          db 0, 0, 2, 0FFh, 0FFh, 0FFh, 0FFh, 0FFh
map_b:          db 0, 1, 2, 0FFh, 0FFh, 0FFh, 0FFh, 0FFh
map_redir:      db 0, 1, 2, 0FFh, 0FFh, 0FFh, 0FFh, 0FFh
pfd:            dw 0
tid_a:          dw 0
rhs:            dw 0
ok_text:        db "ok", 0Dh, 0
exit_text:      db "exit ", 0
err_text:       db "ERR", 0

err_table:
                db ENOENT
                dw e_enoent
                db EEXIST
                dw e_eexist
                db ENOMEM
                dw e_enomem
                db EBADF
                dw e_ebadf
                db EINVAL
                dw e_einval
                db EIO
                dw e_eio
                db ENOTDIR
                dw e_enotdir
                db EISDIR
                dw e_eisdir
                db ENOEXEC
                dw e_enoexec
                db EMFILE
                dw e_emfile
                db ECHILD
                dw e_echild
                db EROFS
                dw e_erofs
                db EBUSY
                dw e_ebusy
                db 0

e_enoent:       db "ENOENT", 0
e_eexist:       db "EEXIST", 0
e_enomem:       db "ENOMEM", 0
e_ebadf:        db "EBADF", 0
e_einval:       db "EINVAL", 0
e_eio:          db "EIO", 0
e_enotdir:      db "ENOTDIR", 0
e_eisdir:       db "EISDIR", 0
e_enoexec:      db "ENOEXEC", 0
e_emfile:       db "EMFILE", 0
e_echild:       db "ECHILD", 0
e_erofs:        db "EROFS", 0
e_ebusy:        db "EBUSY", 0

; HL = text.
build_argv:
                push ix
                push iy
                ld c, 126
                ld de, argv_blk + 2
                ld b, 0
ba_tok:
                ld a, (hl)
                or a
                jr z, ba_done
                cp ' '
                jr nz, ba_word
                inc hl
                jr ba_tok
ba_word:
                inc b
                ld a, b
                cp 9
                jr nc, ba_inval
ba_ch:
                ld a, (hl)
                or a
                jr z, ba_end
                cp ' '
                jr z, ba_end
                ld a, c
                or a
                jr z, ba_inval
                dec c
                ld a, (hl)
                ld (de), a
                inc hl
                inc de
                jr ba_ch
ba_end:
                ld a, c
                or a
                jr z, ba_inval
                dec c
                xor a
                ld (de), a
                inc de
                jr ba_tok
ba_done:
                ld a, b
                or a
                jr z, ba_inval
                ld (argv_blk), a
                xor a
                ld (argv_blk + 1), a
                pop iy
                pop ix
                ret
ba_inval:
                pop iy
                pop ix
                ld a, EINVAL
                scf
                ret

; DE = spawn path. Preserves IX, IY and argv_blk.
bind_path:
                push ix
                push iy
                ld hl, argv_blk + 2
                ld b, 0
bp_scan:
                ld a, (hl)
                or a
                jr z, bp_bin
                cp '/'
                jr z, bp_path
                inc b
                ld a, b
                cp NAME_MAX + 1
                jr z, bp_path
                inc hl
                jr bp_scan
bp_bin:
                ld hl, bin_lit
                ld de, path_buf
                ld bc, 5
                ldir
                ld hl, argv_blk + 2
                ld de, path_buf + 5
bp_copy:
                ld a, (hl)
                ld (de), a
                or a
                jr z, bp_ret_buf
                inc hl
                inc de
                jr bp_copy
bp_ret_buf:
                ld de, path_buf
                pop iy
                pop ix
                or a
                ret
bp_path:
                ld de, argv_blk + 2
                pop iy
                pop ix
                or a
                ret

; A = key byte.
edit_key:
                cp 08h
                jp z, edit_bs
                cp 09h
                jp z, edit_tab
                cp 1Bh
                jp z, edit_esc
                ld b, a
                ld a, (esc_state)
                or a
                jp nz, edit_csi
                ld a, b
                cp 20h
                ret c
                ld a, (cur_pos)
                cp 127
                ret nc
                ld (iy + 0), b
                inc iy
                xor a
                ld (iy + 0), a
                ld a, (cur_pos)
                inc a
                ld (cur_pos), a
                ld a, b
                call write_byte
                ld a, 0FFh
                ld (hist_pos), a
                ret
edit_esc:
                ld a, 1
                ld (esc_state), a
                ret
edit_csi:
                ld a, (esc_state)
                cp 2
                jr z, edit_final
                ld a, b
                cp '['
                jr nz, edit_esc_done
                ld a, 2
                ld (esc_state), a
                ret
edit_final:
                ld a, b
                cp 'A'
                jp z, hist_up
                cp 'B'
                jp z, hist_dn
                push af
                ld a, 1Bh
                call write_byte
                ld a, '['
                call write_byte
                pop af
                call write_byte
edit_esc_done:
                xor a
                ld (esc_state), a
                ret
edit_bs:
                ld a, (cur_pos)
                or a
                ret z
                dec a
                ld (cur_pos), a
                dec iy
                xor a
                ld (iy + 0), a
                ld a, 08h
                call write_byte
                ld a, 0FFh
                ld (hist_pos), a
                ret
edit_tab:
                call complete_word
                ld hl, line
                ld a, (cur_pos)
                ld c, a
                ld b, 0
                add hl, bc
                xor a
                ld (hl), a
                ret

hist_up:
                xor a
                ld (esc_state), a
                ld a, (hist_pos)
                cp 0FFh
                jr z, hu_zero
                cp HIST_LINES - 1
                ret nc
                inc a
                jr hu_set
hu_zero:
                xor a
hu_set:
                ld (hist_pos), a
                call hist_fetch
                ret
hist_dn:
                xor a
                ld (esc_state), a
                ld a, (hist_pos)
                cp 0FFh
                ret z
                dec a
                ld (hist_pos), a
                cp 0FFh
                jr z, hist_clear
                call hist_fetch
                ret
hist_clear:
                xor a
                ld (cur_pos), a
                ld (line), a
                ld iy, line
                call redraw_line
                ret
hist_fetch:
                ld a, (hist_pos)
                ld (argv_blk), a
                ld c, SYS_IOCTL
                ld de, 1
                ld hl, CON_GETHIST
                ld ix, argv_blk
                rst 08h
                ld hl, argv_blk + 127
                ld (hl), 0
                ld hl, argv_blk + 1
                ld de, line
hf_copy:
                ld a, (hl)
                ld (de), a
                or a
                jr z, hf_done
                inc hl
                inc de
                jr hf_copy
hf_done:
                call redraw_line
                ret
hist_save:
                ld hl, line
                ld a, (hl)
                or a
                ret z
                xor a
                ld (argv_blk), a
                ld c, SYS_IOCTL
                ld de, 1
                ld hl, CON_GETHIST
                ld ix, argv_blk
                rst 08h
                ld hl, argv_blk + 127
                ld (hl), 0
                ld hl, argv_blk + 1
                ld de, line
                call hist_same
                ret z
                ld ix, line
                ld c, SYS_IOCTL
                ld de, 1
                ld hl, CON_PUTHIST
                rst 08h
hs_clear:
                ld hl, argv_blk
                ld b, 128
                xor a
hs_cl:
                ld (hl), a
                inc hl
                djnz hs_cl
                ret
hist_same:
                ld a, (de)
                cp (hl)
                ret nz
                or a
                ret z
                inc de
                inc hl
                jr hist_same
redraw_line:
                ld c, SYS_WRITE
                ld de, 1
                ld hl, redraw_seq
                ld ix, redraw_seq_end - redraw_seq
                rst 08h
                ld a, (cur_pos)
                ld b, a
                ld hl, line
                or a
                jr z, rl_done
rl_out:
                ld a, (hl)
                push hl
                call write_byte
                pop hl
                inc hl
                djnz rl_out
rl_done:
                xor a
                ld (hl), a
                ld hl, line
                ld e, a
                ld d, 0
                add hl, de
                push hl
                pop iy
                ret
redraw_seq:     db 0Dh, "sh>", 0
redraw_seq_end:

; HL = line, IX = map. Strips trailing " > path", opens outfile.
strip_redir:
                ld hl, map_redir + 1
                ld a, 1
                ld (hl), a
                ld hl, line
                ld a, (hl)
                cp '>'
                jr nz, sr_skip
                inc hl
                ld a, (hl)
                cp ' '
                jr nz, sr_skip
                inc hl
                ld d, h
                ld e, l
                ld b, O_WRITE | O_CREATE | O_TRUNC
                ld c, SYS_OPEN
                rst 08h
                ret c
                ld e, a
                ld d, 0
                ld c, SYS_CLOSE
                rst 08h
                ld hl, line
                xor a
                ld (hl), a
                jp sr_none
sr_skip:
                ld hl, line
sr_fwd:
                ld a, (hl)
                or a
                jr z, sr_last
                inc hl
                jr sr_fwd
sr_last:
                dec hl
sr_scan:
                ld a, h
                cp line >> 8
                jr c, sr_none
                jr nz, sr_byte
                ld a, l
                cp line & 0FFh
                jr c, sr_none
sr_byte:
                ld a, (hl)
                or a
                jr z, sr_none
                cp '>'
                jr z, sr_hit
                dec hl
                jr sr_scan
sr_hit:
                dec hl
                ld a, (hl)
                cp ' '
                jr nz, sr_scan
                inc hl
                ld (hl), 0
                inc hl
                inc hl
                ld d, h
                ld e, l
                ld b, O_WRITE | O_CREATE | O_TRUNC
                ld c, SYS_OPEN
                rst 08h
                ret c
                ld a, l
                ld (map_redir + 1), a
                xor a
                ret
sr_none:
                xor a
                ret

; Tab completion for the last word.
complete_word:
                push iy
                ld hl, line
                ld a, (cur_pos)
                or a
                jp z, cw_noword
                ld c, a
                ld b, 0
                add hl, bc
                dec hl
                ld de, line
cw_skip:
                ld a, (hl)
                cp ' '
                jr z, cw_atsp
                ld a, h
                cp d
                jr nz, cw_back
                ld a, l
                cp e
                jp z, cw_word0
cw_back:
                dec hl
                jr cw_skip
cw_word0:
                ld hl, line
                jp cw_word
cw_atsp:
                inc hl
                ld a, (hl)
                or a
                jp z, cw_noword
cw_word:
                push hl
                pop de
                ld (cw_ptr), de
                ld a, (de)
                cp '/'
                jr z, cw_abs
                ld de, bin_dir
                jr cw_open_fd
cw_abs:
                ex de, hl
                ld (cw_ptr), hl
                ld bc, hl
                ld hl, line
                ld de, path_buf
cwd_cp:
                ld a, h
                cp b
                jr nz, cwd_byte
                ld a, l
                cp c
                jr z, cwd_end
cwd_byte:
                ld a, (hl)
                ld (de), a
                inc hl
                inc de
                jr cwd_cp
cwd_end:
                ld a, '/'
                ld (de), a
                inc de
                xor a
                ld (de), a
                ld de, path_buf
cw_open_fd:
                ld c, SYS_OPEN
                ld b, O_READ
                rst 08h
                jr nc, cw_open_ok
                pop iy
                ret
cw_open_ok:
                ld a, l
                ld (comp_fd), a
                ld hl, argv_blk
                ld b, 128
                xor a
cw_clr:
                ld (hl), a
                inc hl
                djnz cw_clr
                xor a
                ld (comp_n), a
                ld b, 64
cw_rd:
                ld a, (comp_n)
                cp 8
                jr nc, cw_finish
                djnz cw_rd_scan
                jr cw_finish
cw_rd_scan:
                push bc
                ld c, SYS_READDIR
                ld a, (comp_fd)
                ld e, a
                ld d, 0
                ld hl, path_buf
                rst 08h
                jr c, cw_close_bc
                ld a, h
                or l
                jr z, cw_finish_bc
                ld hl, path_buf + 2
                call cw_match
                pop bc
                jr cw_rd
cw_finish_bc:
                pop bc
                jr cw_finish
cw_close_bc:
                pop bc
                jr cw_close
cw_finish:
                ld a, (comp_n)
                cp 1
                jr nz, cw_list
                call cw_insert
                jr cw_close
cw_list:
                or a
                jr z, cw_close
                call cw_relist
                call redraw_line
                jr cw_close
cw_relist:
                push iy
                ld a, (comp_fd)
                ld e, a
                ld d, 0
                ld c, SYS_CLOSE
                rst 08h
                ld de, bin_dir
                ld c, SYS_OPEN
                ld b, O_READ
                rst 08h
                jr c, cw_relist_done
                ld a, l
                ld (comp_fd), a
                ld de, argv_blk
                ld a, 0Dh
                ld (de), a
                inc de
                ld b, 64
cr_loop:
                djnz cr_scan
                jr cr_flush
cr_scan:
                push bc
                push de
                ld c, SYS_READDIR
                ld a, (comp_fd)
                ld e, a
                ld d, 0
                ld hl, path_buf
                rst 08h
                jr c, cr_pop_done
                ld a, h
                or l
                jr z, cr_pop_done
                call cw_prefix_ok
                jr nc, cr_noemit
                pop de
                call cw_append_name
                push de
cr_noemit:
                pop de
                pop bc
                jr cr_loop
cr_pop_done:
                pop de
                pop bc
cr_flush:
                ld hl, de
                ld bc, argv_blk
                or a
                sbc hl, bc
                ld a, h
                or l
                jr z, cw_relist_done
                ld c, SYS_WRITE
                ld de, 1
                push hl
                pop ix
                ld hl, argv_blk
                rst 08h
cw_relist_done:
                pop iy
                ret
cw_close:
                ld a, (comp_fd)
                ld e, a
                ld d, 0
                ld c, SYS_CLOSE
                rst 08h
                pop iy
                ret
cw_match:
                call cw_prefix_ok
                ret nc
cm_hit:
                ld a, (comp_n)
                cp 8
                ret nc
                inc a
                ld (comp_n), a
                ret
cm_fail:
                ret
cw_prefix_ok:
                ld hl, (cw_ptr)
                ld d, h
                ld e, l
                push de
                ld hl, path_buf + 2
                pop de
cp_loop:
                ld a, (de)
                or a
                jr z, cp_ok
                cp (hl)
                jr nz, cp_fail
                inc de
                inc hl
                jr cp_loop
cp_fail:
                or a
                ret
cp_ok:
                ld hl, (cw_ptr)
                ld a, (hl)
                or a
                ret z
                scf
                ret
; DE = list buffer end. Appends path_buf+2 name and CR; returns updated DE.
cw_append_name:
                push bc
                ld hl, path_buf + 2
                ld b, 30
can_loop:
                ld a, (hl)
                or a
                jr z, can_cr
                ld (de), a
                inc de
                inc hl
                djnz can_loop
can_cr:
                ld a, 0Dh
                ld (de), a
                inc de
                pop bc
                ret
cw_insert:
                ld hl, path_buf + 2
                ld de, (cw_ptr)
ci_skip:
                ld a, (de)
                cp (hl)
                jr nz, ci_out
                or a
                jr z, ci_out
                inc de
                inc hl
                jr ci_skip
ci_out:
                ld (cw_suff), hl
                push iy
                pop de
                ld hl, (cw_suff)
                ld bc, 0
cw_ins:
                ld a, (hl)
                or a
                jr z, cw_ins_done
                ld (de), a
                inc hl
                inc de
                inc bc
                jr cw_ins
cw_ins_done:
                ld a, (cur_pos)
                add a, c
                ld (cur_pos), a
                push de
                pop iy
                ld hl, (cw_suff)
                push bc
cw_ins_out:
                ld a, (hl)
                or a
                jr z, cw_ins_sl
                push hl
                call write_byte
                pop hl
                inc hl
                dec bc
                ld a, b
                or c
                jr nz, cw_ins_out
cw_ins_sl:
                pop bc
                call cw_stat_dir
                ret
cw_stat_dir:
                ld c, SYS_STAT
                ld de, path_buf + 2
                ld hl, st
                rst 08h
                ret c
                ld a, (st + 2)
                cp INO_KIND_DIR
                ret nz
                ld a, '/'
                ld (de), a
                inc de
                ld (iy + 0), a
                call write_byte
                ret
cw_noword:
                pop iy
                ret

line:
argv_blk        equ line + 128
NAME_MAX        equ 30
path_buf        equ argv_blk + 128
cur_pos         equ path_buf + 32
esc_state       equ cur_pos + 1
hist_pos        equ esc_state + 1
comp_fd         equ hist_pos + 1
cw_ptr          equ comp_fd + 1
comp_n          equ cw_ptr + 2
cw_suff         equ comp_n + 1
st              equ cw_suff + 2
                assert st + 6 - line <= 320
