; SYS_TASKINFO for /sys/dev: one task record per call, layout TI_* in cp500.inc.

; DE = task id, HL = TI_SIZE-byte record. Ids above 7 are EINVAL, a free slot is
; a zero record. The running task's live record is stale, so its fields come
; from TASK and the others from t_live.
n_taskinfo:
                ld ix, (SC_FRAME)
                ld a, (ix + F_DE)
                cp TASK_SLOTS
                jp nc, dev_err_einval
                ld c, a
                ld b, 0
                ld e, (ix + F_HL)
                ld d, (ix + F_HL + 1)
                ld hl, T_STATE
                add hl, bc
                ld a, (hl)
                or a
                jr z, ti_free
                ld (de), a
                inc de
                ld hl, T_PARENT
                add hl, bc
                ld a, (hl)
                ld (de), a
                inc de
                ld hl, T_CHAN
                add hl, bc
                ld a, (hl)
                ld (de), a
                inc de
                ld hl, TASK
                ld a, (CUR)
                cp c
                jr z, ti_rec
                ld a, c
                call t_live
ti_rec:
                push hl
                pop iy
                ld a, (iy + TASK_BASE)
                ld (de), a
                inc de
                ld a, (iy + TASK_PAGES)
                ld (de), a
                inc de
; Console: the ino of fd 0 when that is an input console, else 0FFh.
                ld a, (iy + TASK_FD)
                cp 0FFh
                jr z, ti_nocon
                call ofile_of
                ld a, (hl)
                cp KIND_CON_IN
                jr nz, ti_nocon
                inc hl
                inc hl
                ld a, (hl)
                jr ti_con
ti_nocon:
                ld a, 0FFh
ti_con:
                ld (de), a
                inc de
                xor a
                ld (de), a
                inc de
                ld (de), a
                inc de
; Name from TASK_NAMES. Slot 0 has none: the mask zeroes it.
                ld a, c
                add a, a
                add a, a
                add a, a
                add a, TASK_NAMES & 0FFh
                ld l, a
                ld h, TASK_NAMES >> 8
                ld a, c
                neg
                sbc a, a
                ld c, a
                ld b, TASK_NAME_LEN
ti_name:
                ld a, (hl)
                and c
                ld (de), a
                inc hl
                inc de
                djnz ti_name
                jp dev_ok_z
ti_free:
                ld b, TI_SIZE
                xor a
ti_zero:
                ld (de), a
                inc de
                djnz ti_zero
                jp dev_ok_z
