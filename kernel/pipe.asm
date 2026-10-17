; Pipes are slots 0-3 of state, page, head, tail. Head equal to tail is empty,
; so one page holds 255 bytes. An end is open while its ofile exists.

; DE = 2 bytes, filled with the read fd and the write fd.
sys_pipe:
                ld (io_buf), de
                ld hl, PIPE
                ld c, 0
pipe_find:
                ld a, (hl)
                or a
                jr z, pipe_got
                ld a, l
                add a, 4
                ld l, a
                inc c
                ld a, c
                cp NPIPE
                jr c, pipe_find
                ld a, EMFILE
                jp syscall_err
pipe_got:
                push hl
                push bc
                call largest_run
                pop bc
                pop hl
                ld a, ENOMEM
                jp c, syscall_err
                ld (hl), PIPE_R_OPEN | PIPE_W_OPEN
                inc l
                ld a, (RUN_END)
                dec a
                ld (hl), a
                inc l
                ld (hl), 0
                inc l
                ld (hl), 0
                call owner_of
                ld (hl), 0FFh
                ld a, c
                ld (open_ino), a
                xor a
                ld (open_ino + 1), a
                ld (open_flags), a
                ld a, KIND_PIPE_R
                ld (open_kind), a
                call fd_alloc
                jr c, pipe_undo
                push hl
                ld a, KIND_PIPE_W
                ld (open_kind), a
                call fd_alloc
                pop de
                jr c, pipe_undo_r
                ld a, l
                ld hl, (io_buf)
                ld (hl), e
                inc hl
                ld (hl), a
                ld hl, 0
                jp syscall_ok
pipe_undo_r:
                push af
                ld d, 0
                ld hl, TASK + TASK_FD
                add hl, de
                call fd_drop
                pop af
pipe_undo:
                push af
                ld a, (open_ino)
                ld b, PIPE_R_OPEN | PIPE_W_OPEN
                call pipe_end_closed
                pop af
                jp syscall_err

; HL = ofile. Returns what is buffered, up to io_len, or 0 once no writer is left.
pipe_read:
                call io_empty
                call pipe_of
                push hl
                inc l
                ld d, (hl)
                inc l
                ld e, (hl)
                inc l
                ld a, (hl)
                sub e
                pop hl
                jr nz, pipe_some
                ld a, c
                add a, CH_PIPE
                bit 1, (hl)
                jp nz, block_retry
                ld hl, 0
                jp syscall_ok
pipe_some:
                call pipe_count
                push hl
                push bc
                ld hl, (io_buf)
pipe_out:
                ld a, (de)
                ld (hl), a
                inc hl
                inc e
                djnz pipe_out
                pop bc
                pop hl
                inc l
                inc l
                ld (hl), e
                ld l, b
                ld h, 0
                push hl
                ld a, c
                add a, CH_PIPE
                call wake_di
                pop hl
                jp syscall_ok

; HL = ofile. Moves all io_len bytes, blocking while the pipe is full. With no
; reader left the task ends with EXIT_KILLED.
pipe_write:
                call io_empty
                call pipe_of
                bit 0, (hl)
                jr nz, pipe_reader
                di
                ld a, (CUR)
                call kill_mark
                ei
                ld a, EIO
                jp syscall_err
pipe_reader:
                push hl
                inc l
                ld d, (hl)
                inc l
                ld a, (hl)
                inc l
                ld e, (hl)
                scf
                sbc a, e
                pop hl
                jr nz, pipe_room
                ld a, c
                add a, CH_PIPE
                jp block_retry
pipe_room:
                call pipe_count
                ld a, b
                ld (io_got), a
                xor a
                ld (io_got + 1), a
                push hl
                push bc
                ld hl, (io_buf)
pipe_in:
                ld a, (hl)
                ld (de), a
                inc hl
                inc e
                djnz pipe_in
                pop bc
                pop hl
                ld a, l
                add a, 3
                ld l, a
                ld (hl), e
                ld hl, (io_len)
                ld de, (io_got)
                or a
                sbc hl, de
                ld (io_len), hl
                ld a, c
                add a, CH_PIPE
                call wake_di
                jp io_round

; A = bytes available, at least 1. B = that, capped at io_len.
pipe_count:
                ld b, a
                ld a, (io_len + 1)
                or a
                ret nz
                ld a, (io_len)
                cp b
                ret nc
                ld b, a
                ret

; HL = ofile. HL = its pipe slot, C = pipe.
pipe_of:
                inc hl
                inc hl
                ld a, (hl)
                ld c, a
; A = pipe. HL = its slot.
pipe_at:
                add a, a
                add a, a
                add a, PIPE & 0FFh
                ld l, a
                ld h, PIPE >> 8
                ret

; A = pipe, B = the ends that closed. The last end frees the page.
pipe_end_closed:
                ld c, a
                call pipe_at
                ld a, b
                cpl
                and (hl)
                ld (hl), a
                jr nz, pipe_wake
                inc l
                ld a, (hl)
                call owner_of
                ld (hl), 0
pipe_wake:
                ld a, c
                add a, CH_PIPE
                jp wake_di
