; ps: one row per task slot in use, from SYS_TASKINFO. Init is shown as "init".

                include "cp500.inc"

                org ORIGIN

                ld hl, hdr_text
                call puts
                call cr
                xor a
                ld (next_id), a
ps_loop:
                ld a, (next_id)
                ld e, a
                ld d, 0
                ld hl, rec
                ld c, SYS_TASKINFO
                rst 08h
                jp c, fail
                ld a, (rec + TI_STATE)
                or a
                call nz, row
                ld a, (next_id)
                inc a
                ld (next_id), a
                cp TASK_SLOTS
                jr c, ps_loop
                jp exit0

; One row for the record in rec. Columns: ID(0-1) ST(3) WAIT(6-10) PPID(12-15)
; MEM(17-20) CON(23) NAME(26).
row:
                ld a, (next_id)
                ld l, a
                ld h, 0
                ld b, 2
                call put_dec_w
                call sp1
                ld a, (rec + TI_STATE)
                ld e, a
                ld d, 0
                ld hl, st_tab
                add hl, de
                ld a, (hl)
                call putc
                ld b, 2
                call spaces
                call row_wait
                call sp1
                ld a, (rec + TI_PARENT)
                cp 0FFh
                jr z, row_ppid_dash
                ld l, a
                ld h, 0
                ld b, 4
                call put_dec_w
                jr row_mem
row_ppid_dash:
                call dash4
row_mem:
                call sp1
                ld a, (rec + TI_PAGES)
                or a
                jr z, row_mem_dash
                ld h, a
                ld l, 0                 ; pages * 256
                ld b, 4
                call put_dec_w
                jr row_con
row_mem_dash:
                call dash4
row_con:
                ld b, 2
                call spaces
                ld a, (rec + TI_CON)
                cp 0FFh
                jr nz, row_con_num
                ld a, '-'
                jr row_con_put
row_con_num:
                add a, '1'              ; console index 0 or 1 shows as 1 or 2
row_con_put:
                call putc
                ld b, 2
                call spaces
                ld a, (next_id)
                or a
                jr nz, row_name
                ld hl, init_name
                jr row_put_name
row_name:
                ld hl, rec + TI_NAME
row_put_name:
                call puts
                jp cr

; WAIT column, five characters. Only a blocked task has a channel to show.
row_wait:
                ld a, (rec + TI_STATE)
                cp TS_BLOCKED
                ld a, (rec + TI_CHAN)
                jr z, rw_chan
                xor a                   ; not blocked: "-"
rw_chan:
                cp CH_PIPE
                jr nc, rw_pipe
                cp 6
                jr c, rw_tab
                xor a
rw_tab:
                ld e, a
                ld d, 0
                ld h, d
                ld l, e
                add hl, hl              ; * 2
                add hl, hl              ; * 4
                add hl, de              ; * 5
                ld de, w_tab
                add hl, de
                jp put5
rw_pipe:
                sub CH_PIPE
                push af
                ld hl, w_pipe
                call puts
                pop af
                add a, '0'
                jp putc

; B spaces.
spaces:
                ld a, ' '
                push bc
                call putc
                pop bc
                djnz spaces
                ret

sp1:
                ld a, ' '
                jp putc

; "   -", a column with no value.
dash4:
                ld b, 3
                call spaces
                ld a, '-'
                jp putc

; HL = five characters, no terminator.
put5:
                ld b, 5
p5:
                ld a, (hl)
                push bc
                push hl
                call putc
                pop hl
                pop bc
                inc hl
                djnz p5
                ret

hdr_text:       db "ID ST WAIT  PPID  MEM CON NAME", 0
st_tab:         db "?RBDZ"              ; index is the TS_* state
w_tab:          db "-    ", "key  ", "tick ", "child", "ser  ", "sleep"
w_pipe:         db "pipe", 0
init_name:      db "init", 0
next_id:        db 0
rec:            ds TI_SIZE, 0

                include "num.inc"
                include "run.inc"
