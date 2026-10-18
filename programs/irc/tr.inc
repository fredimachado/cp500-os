; Transport: replay fds, 256-byte chunk, pause without seek, blocked write.

TR_BOL          equ 0
TR_MID          equ 1
TR_DOT          equ 2
TR_DOTCR        equ 3
TR_HELD         equ 4
TR_READY        equ 5
TR_CLOSED       equ 6

RL_BOOT         equ 0
RL_READY        equ 1

tr_open:
                ld a, d
                or e
                jr nz, tr_replay
                ld a, ENODEV
                scf
                ret
tr_replay_path: dw 0

tr_replay:
                ld (tr_replay_path), hl
                push de
                push hl
                pop de
                ld c, SYS_OPEN
                ld b, O_READ
                rst 08h
                jp c, tr_open_in_fail
                ld a, l
                ld (tr_rfd), a
                pop de
                ld c, SYS_OPEN
                ld b, O_WRITE | O_CREATE | O_TRUNC
                rst 08h
                jp c, tr_open_out_fail
                ld a, l
                ld (tr_wfd), a
                xor a
                ld (tr_wlen), a
                ld (tr_state), a
                ld (tr_pos), a
                ld (tr_len), a
                or a
                ret
tr_open_in_fail:
                pop de
                scf
                ret
tr_open_out_fail:
                scf
                ret

; Plain SYS_READ up to 128 bytes into rl_buf (before tr_read pause machine).
tr_boot_read:
                ld bc, (rl_len)
                ld a, b
                or c
                ret nz
                ld a, (tr_rfd)
                ld e, a
                ld d, 0
                ld hl, tr_chunk
                ld ix, 128
                ld c, SYS_READ
                rst 08h
                ret c
                ld a, h
                or l
                ret z
                ld (rl_len), hl
                ld a, l
                ld (tr_len), a
                push hl
                ld hl, tr_chunk
                ld de, rl_buf
                pop bc
                ldir
                xor a
                ld (tr_pos), a
                ld (tr_state), a
                or a
                ret

; HL dest, BC max. Out BC bytes, C=EOF when carry.
tr_read:
                ld a, (tr_state)
                cp TR_CLOSED
                jp z, tr_eof
                cp TR_HELD
                jr nz, tr_notheld
                xor a
                ld b, a
                ld c, a
                or a
                ret
tr_notheld:
                ld a, (tr_state)
                cp TR_READY
                jr nz, tr_work
tr_resume:
                ld a, TR_BOL
                ld (tr_state), a
tr_work:
                call tr_ensure
                ret c
                ld a, (tr_len)
                or a
                jp z, tr_zero
tr_drain:
                ld a, b
                or a
                jr nz, tr_cap255
                ld a, c
                cp 255
                jr c, tr_setrem
tr_cap255:
                ld bc, 255
tr_setrem:
                ld (tr_out), hl
                ld (tr_rem), bc
                xor a
                ld (tr_got), a
tr_refill:
                call tr_ensure
                ret c
                ld a, (tr_len)
                or a
                jr z, tr_nodata
                call tr_pump
                ld a, (tr_got)
                or a
                jr nz, tr_retbc
                ld a, (tr_state)
                cp TR_CLOSED
                jp z, tr_eof
                cp TR_HELD
                jr z, tr_ret0
                ld a, (tr_pos)
                ld b, a
                ld a, (tr_len)
                cp b
                jr c, tr_ret0
                jr z, tr_at_chunk_end
                jp tr_refill
tr_at_chunk_end:
                ld a, (tr_rem)
                or a
                ld b, a
                ld a, (tr_rem + 1)
                or b
                jr z, tr_ret0
                jp tr_refill
tr_nodata:
                ld a, (tr_got)
                or a
                jr nz, tr_retbc
                jr tr_ret0
tr_retbc:
                ld b, 0
                ld c, a
tr_ret:
                or a
                ret
tr_ret0:
                xor a
                ld b, a
                ld c, a
                or a
                ret
tr_zero:
                xor a
                ld b, a
                ld c, a
                or a
                ret
tr_eof:
                scf
                xor a
                ld b, a
                ld c, a
                ret

tr_ensure:
                push hl
                ld a, (tr_len)
                ld b, a
                ld a, (tr_pos)
                cp b
                jr c, tr_ensure_ok
tr_ensure_read:
                ld c, SYS_READ
                ld a, (tr_rfd)
                ld e, a
                ld d, 0
                ld hl, tr_chunk
                ld ix, 255
                rst 08h
                jr c, tr_ensure_out
                ld a, l
                or a
                jr nz, tr_setlen
                ld a, h
                or a
                jr z, tr_setlen
                ld a, 255
tr_setlen:
                ld (tr_len), a
                xor a
                ld (tr_pos), a
tr_ensure_ok:
                pop hl
                or a
                ret
tr_ensure_out:
                pop hl
                scf
                ret

tr_pump:
tp_loop:
                ld a, (tr_state)
                cp TR_DOT
                jr nz, tp_pos
                ld a, (tr_pos)
                ld b, a
                ld a, (tr_len)
                cp b
                jr c, tp_pos
                jr z, tp_pos
                ld hl, tr_chunk
                ld a, b
                add a, l
                ld l, a
                jr nc, tp_rd_ix
                inc h
tp_rd_ix:
                ld a, (hl)
                cp '.'
                jr z, tp_slurp_ret
                cp 0Dh
                jr z, tp_slurp_ret
                cp 0Ah
                jr z, tp_slurp_ret
                ld a, TR_BOL
                ld (tr_state), a
                jp tp_pos
tp_slurp_ret:
                call tp_slurp_pause
                ret
tp_pos:
                ld a, (tr_pos)
                ld b, a
                ld a, (tr_len)
                cp b
                ret z
                ld hl, tr_chunk
                ld a, b
                add a, l
                ld l, a
                jr nc, tp_ix
                inc h
tp_ix:
                ld a, (hl)
                ld c, a
                inc b
                ld a, b
                ld (tr_pos), a
                ld a, (tr_state)
                cp TR_BOL
                jr nz, tp_mid
                ld a, c
                cp '.'
                jr nz, tp_emit
                call tp_slurp_pause
                ret
tp_mid:
                cp TR_MID
                jr nz, tp_any
                ld a, c
                cp 0Dh
                jr z, tp_loop
                jp tp_emit
tp_any:
                ld a, TR_MID
                ld (tr_state), a
tp_emit:
                ld a, (tr_state)
                cp TR_BOL
                jr nz, tp_em2
                ld a, TR_MID
                ld (tr_state), a
tp_em2:
                ld hl, (tr_out)
                ld a, c
                ld (hl), a
                inc hl
                ld (tr_out), hl
                cp 0Ah
                jr nz, tp_got
                ld a, TR_BOL
                ld (tr_state), a
tp_got:
                ld hl, tr_got
                inc (hl)
                ld hl, tr_rem
                ld bc, (hl)
                dec bc
                ld (hl), bc
                ld a, b
                or c
                jp nz, tp_loop
                call tp_pause_if_bol
tp_done:
                ret

; Output buffer full: still finish a pending "." pause line.
tp_pause_if_bol:
                ld a, (tr_state)
                cp TR_DOT
                jr z, tp_pib_slurp
                cp TR_BOL
                ret nz
                ld a, (tr_pos)
                ld b, a
                ld a, (tr_len)
                cp b
                ret c
                ret z
                ld hl, tr_chunk
                ld a, b
                add a, l
                ld l, a
                jr nc, tp_pib_ix
                inc h
tp_pib_ix:
                ld a, (hl)
                cp '.'
                ret nz
                ld hl, tr_pos
                inc (hl)
tp_pib_slurp:
                call tp_slurp_pause
                ld a, (tr_state)
                cp TR_HELD
                ret z
                jp tp_loop

; tr_pos on '.'; skip through line end, TR_HELD, tr_pos at next line.
tp_slurp_pause:
                push bc
                push hl
tps_loop:
                ld a, (tr_pos)
                ld b, a
                ld a, (tr_len)
                cp b
                jr c, tps_part
                jr z, tps_part
                ld hl, tr_chunk
                ld a, b
                add a, l
                ld l, a
                jr nc, tps_ix
                inc h
tps_ix:
                ld a, (hl)
                cp 0Ah
                jr z, tps_nl
                ld hl, tr_pos
                inc (hl)
                jr tps_loop
tps_nl:
                ld hl, tr_pos
                inc (hl)
                ld a, TR_BOL
                ld (tr_state), a
                ld a, TR_HELD
                ld (tr_state), a
                pop hl
                pop bc
                ret
tps_part:
                ld a, TR_DOT
                ld (tr_state), a
                pop hl
                pop bc
                ret

; HL bytes, BC count without CR LF.
tr_write:
tw_loop:
                ld a, b
                or c
                jr z, tw_eol
                ld a, (hl)
                inc hl
                push af
                call tr_wbyte
                pop af
                ret c
                dec bc
                ld a, b
                or c
                jr nz, tw_loop
                jr tw_eol
tw_eol:
                ld a, 0Dh
                call tr_wbyte
                ret c
                ld a, 0Ah
                jp tr_wbyte
tw_fail:
                scf
                ret

tr_wbyte:
                push af
                ld a, (tr_wlen)
                ld e, a
                ld d, high tr_wblk
                pop af
                ld (de), a
                inc e
                jr nz, tr_wstore
                push af
                call tr_flush256
                pop af
                ret c
                xor a
                jr tr_wstore
tr_wstore:
                ld a, e
                ld (tr_wlen), a
                or a
                ret

tr_flush256:
                ld c, SYS_WRITE
                ld a, (tr_wfd)
                ld e, a
                ld d, 0
                ld hl, tr_wblk
                ld ix, 256
                rst 08h
                ret c
                xor a
                ld (tr_wlen), a
                or a
                ret

tr_flush_pending:
                ld a, (tr_wlen)
                or a
                ret z
                ld b, a
                ld hl, tr_wblk
tfp_loop:
                ld a, (hl)
                push hl
                push bc
                call tr_putc
                pop bc
                pop hl
                inc hl
                djnz tfp_loop
                xor a
                ld (tr_wlen), a
                ret

tr_putc:
                ld (ch), a
                ld c, SYS_WRITE
                ld a, (tr_wfd)
                ld e, a
                ld d, 0
                ld hl, ch
                ld ix, 1
                rst 08h
                ret

tr_close:
                ld a, (tr_state)
                cp TR_CLOSED
                ret z
                xor a
                ld (tr_close_err), a
                ld a, (tr_wlen)
                or a
                jr z, tr_close_r
                ld c, a
                ld b, 0
                push bc
                ld c, SYS_WRITE
                ld a, (tr_wfd)
                ld e, a
                ld d, 0
                ld hl, tr_wblk
                pop ix
                rst 08h
                jr nc, tr_close_r
                ld (tr_close_err), a
tr_close_r:
                ld c, SYS_CLOSE
                ld a, (tr_rfd)
                cp 0FFh
                jr z, tr_close_w
                ld e, a
                ld d, 0
                rst 08h
                ld a, 0FFh
                ld (tr_rfd), a
tr_close_w:
                ld c, SYS_CLOSE
                ld a, (tr_wfd)
                cp 0FFh
                jr z, tr_closed
                ld e, a
                ld d, 0
                rst 08h
                jr nc, tr_closed
                ld (tr_close_err), a
tr_closed:
                ld a, 0FFh
                ld (tr_wfd), a
                ld a, TR_CLOSED
                ld (tr_state), a
                ld a, (tr_close_err)
                or a
                ret z
                scf
                ret

; After user submit, leave replay hold and expose unread chunk tail.
tr_kick:
                ld a, (tr_state)
                cp TR_HELD
                jr z, tk_unhold
                cp TR_DOT
                jr z, tk_unhold_dot
                cp TR_DOTCR
                jr z, tk_unhold_dot
                jp tk_fin
tk_unhold:
                ld a, TR_READY
                ld (tr_state), a
                xor a
                ret
tk_unhold_dot:
                call tk_dot_at_pos
                ld a, TR_READY
                ld (tr_state), a
                jr nz, tk_ud_done
                call tk_skip_pause
tk_ud_done:
                xor a
                ret
tk_fin:
                call tk_dot_at_pos
                ret nz
                call tk_skip_pause
                xor a
                ret

tk_dot_at_pos:
                ld a, (tr_pos)
                ld b, a
                ld a, (tr_len)
                cp b
                jr c, tk_bd_eof
                jr z, tk_bd_eof
                ld hl, tr_chunk
                ld a, b
                add a, l
                ld l, a
                jr nc, tk_bd_ix
                inc h
tk_bd_ix:
                ld a, (hl)
                cp '.'
                ret
tk_bd_eof:
                or a
                ret

tk_skip_pause:
                ld a, (tr_pos)
                ld b, a
                ld a, (tr_len)
                cp b
                ret c
                ret z
                ld hl, tr_chunk
                ld a, b
                add a, l
                ld l, a
                jr nc, tk_sp_scan
                inc h
tk_sp_scan:
                ld a, (hl)
                cp '.'
                ret nz
                push bc
                push hl
tk_sp_loop:
                ld a, (tr_pos)
                ld b, a
                ld a, (tr_len)
                cp b
                jr c, tk_sp_out
                jr z, tk_sp_out
                ld hl, tr_chunk
                ld a, b
                add a, l
                ld l, a
                jr nc, tk_sp_ix
                inc h
tk_sp_ix:
                ld a, (hl)
                cp 0Ah
                jr z, tk_sp_nl
                ld hl, tr_pos
                inc (hl)
                jr tk_sp_loop
tk_sp_nl:
                ld hl, tr_pos
                inc (hl)
                ld a, TR_BOL
                ld (tr_state), a
tk_sp_out:
                pop hl
                pop bc
                ret
