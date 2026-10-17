; Tasks are slots 0-7 with one state byte each. Task 0 is init and the idle loop.
; A blocked call keeps no kernel state: its frame points back at its own RST 08h
; and waking it runs the call again, so io_buf, INO_BUF and the loader globals
; are never held across a sleep.

; Interrupts off, SP at CUR's full frame.
sched_save:
                ld (TASK + TASK_SP), sp
                ld a, (CUR)
                call t_live
                ex de, hl
                ld hl, TASK
                ld bc, 16
                ldir
; Interrupts off. CUR is saved, or dead and never resumed.
sched_pick:
                ld a, 1
                ld (KBUSY), a
                call pick
                ld (CUR), a
                call t_live
                ld de, TASK
                ld bc, 16
                ldir
                ld a, QUANTUM_TICKS
                ld (QUANTUM), a
                ld sp, (TASK + TASK_SP)
                call t_state
                ld a, (hl)
                cp TS_DYING
                ld e, EXIT_KILLED
                jp z, task_exit
                xor a
                ld (KBUSY), a
frame_return:
                exx
                ex af, af'
                pop hl
                pop de
                pop bc
                pop af
                ex af, af'
                exx
                pop iy
                pop ix
                pop hl
                pop de
                pop bc
                pop af
                ei
                ret

; A = next slot to run. Task 0 runs when nothing else can or a console wants a shell.
pick:
                ld a, (CON_WANT)
                or a
                ld a, 0
                ret nz
                ld a, (CUR)
                ld b, TASK_SLOTS
pick_next:
                inc a
                and TASK_SLOTS - 1
                jr z, pick_skip
                ld c, a
                call t_state_a
                ld a, c
                bit 0, (hl)
                ret nz
pick_skip:
                djnz pick_next
                xor a
                ret

; A = slot. HL = its live record.
t_live:
                add a, a
                add a, a
                add a, a
                add a, a
                add a, T_LIVE & 0FFh
                ld l, a
                ld h, T_LIVE >> 8
                ret

; HL = T_STATE[CUR], or T_STATE[A] from t_state_a.
t_state:
                ld a, (CUR)
t_state_a:
                add a, T_STATE & 0FFh
                ld l, a
                ld h, T_STATE >> 8
                ret

; A = channel. Called from a call handler; never returns. The call reruns when woken.
block_retry:
                di
                ld hl, (SC_FRAME)
                ld sp, hl
                ld de, F_PC
                add hl, de
                ld e, (hl)
                inc hl
                ld d, (hl)
                dec de
                ld (hl), d
                dec hl
                ld (hl), e
                ld c, a
                call t_state
                ld a, l
                add a, T_CHAN - T_STATE
                ld l, a
                ld (hl), c
                sub T_CHAN - T_STATE
                ld l, a
                ld a, (hl)
                cp TS_READY
                jp nz, sched_save
                ld (hl), TS_BLOCKED
                jp sched_save

; Main-line wakes must not race an ISR kill_mark on the same state byte.
wake_di:
                di
                call wake
                ei
                ret

; A = channel, kept. Every task blocked on it becomes ready and retries.
wake:
                ld c, a
                ld hl, T_CHAN
                ld b, TASK_SLOTS
wake_one:
                ld a, (hl)
                cp c
                jr nz, wake_next
                ld a, l
                sub T_CHAN - T_STATE
                ld l, a
                ld a, (hl)
                cp TS_BLOCKED
                jr nz, wake_back
                ld (hl), TS_READY
wake_back:
                ld a, l
                add a, T_CHAN - T_STATE
                ld l, a
wake_next:
                inc l
                djnz wake_one
                ld a, c
                ret

; A = slot. Carry when it is not ready or blocked. Interrupts must be off.
kill_mark:
                call t_state_a
                ld a, (hl)
                dec a
                cp TS_BLOCKED
                ccf
                ret c
                ld (hl), TS_DYING
                ret

; RUN_START and RUN_END bound the largest run of free arena pages. Carry when none.
largest_run:
                ld hl, OWNER
                ld c, ARENA_FIRST
                ld de, 0
                ld b, d
lr_page:
                ld a, (hl)
                or a
                jr z, lr_free
                ld b, 0
                jr lr_next
lr_free:
                inc b
                ld a, d
                cp b
                jr nc, lr_next
                ld d, b
                ld a, c
                sub b
                inc a
                ld e, a
lr_next:
                inc hl
                inc c
                ld a, c
                cp ARENA_LAST + 1
                jr nz, lr_page
                ld a, d
                cp 1
                ret c
                add a, e
                ld d, a
                ld (RUN_START), de
                ret

; A = arena page. HL = its owner byte.
owner_of:
                sub ARENA_FIRST
                ld l, a
                ld h, OWNER >> 8
                ret

; DE = path, HL = argv, IX = fd map, 0 inherits fds 0-2. HL = task id.
sys_spawn:
                ld (spawn_argv), hl
                ld (spawn_map), ix
                ld hl, T_STATE + 1
                ld b, TASK_SLOTS - 1
spawn_slot:
                ld a, (hl)
                or a
                jr z, spawn_free
                inc l
                djnz spawn_slot
                ld a, EAGAIN
                jp syscall_err
spawn_free:
                ld a, l
                sub T_STATE & 0FFh
                ld (spawn_tid), a
                call c5fs_walk
                jp c, syscall_err
                ld a, (INO_BUF + INO_TYPE)
                and 0Fh
                cp INO_KIND_DIR
                jr nz, spawn_file
                ld a, EISDIR
                jp syscall_err
spawn_file:
                cp INO_KIND_FILE
                jr z, spawn_fds
                ld a, EIO
                jp syscall_err
spawn_fds:
                call map_check
                jp c, syscall_err
                call largest_run
                ld a, ENOMEM
                jp c, syscall_err
                ld a, (RUN_START)
                ld hl, (spawn_argv)
                call load_c5x
                jp c, syscall_err
                push hl
                ld a, (spawn_tid)
                call t_live
                push hl
                pop ix
                ld (ix + TASK_PAGES), b
                ld a, (RUN_START)
                ld (ix + TASK_BASE), a
                call owner_of
                ld a, (spawn_tid)
                ld (ix + TASK_ID), a
spawn_own:
                ld (hl), a
                inc l
                djnz spawn_own
                ld (ix + TASK_VOL), b
                ld (ix + TASK_CWD + 1), b
                inc b
                ld (ix + TASK_CWD), b
                push ix
                pop hl
                ld de, TASK_FD
                add hl, de
                ld (spawn_fd), hl
                call map_apply
                ld hl, (child_sp)
                ld b, FRAME_SIZE
spawn_zero:
                dec hl
                ld (hl), 0
                djnz spawn_zero
                ld (ix + TASK_SP), l
                ld (ix + TASK_SP + 1), h
                push hl
                pop iy
                pop hl
                ld (iy + F_PC), l
                ld (iy + F_PC + 1), h
                ld hl, (child_argv)
                ld (iy + F_HL), l
                ld (iy + F_HL + 1), h
                ld a, (spawn_tid)
                ld e, a
                add a, a
                add a, T_ARG & 0FFh
                ld l, a
                ld h, T_ARG >> 8
                xor a
                ld (hl), a
                inc l
                ld (hl), a
                ld a, e
                add a, T_PARENT & 0FFh
                ld l, a
                ld a, (CUR)
                ld (hl), a
                ld a, l
                sub T_PARENT - T_STATE
                ld l, a
                ld (hl), TS_READY
                ld l, e
                ld h, 0
                jp syscall_ok

; E = exit code.
sys_exit:
; E = exit code. Runs on the exiting task's stack and never returns.
task_exit:
                ld a, (CUR)
                dec a
                jr z, exit_halt
                push de
                ld hl, TASK + TASK_FD
                ld b, FD_SLOTS
exit_fd:
                push hl
                push bc
                call fd_drop
                pop bc
                pop hl
                inc hl
                djnz exit_fd
                ld a, (CUR)
                ld c, a
                ld hl, OWNER
                ld b, ARENA_LAST - ARENA_FIRST + 1
exit_page:
                ld a, (hl)
                cp c
                jr nz, exit_page_next
                ld (hl), 0
exit_page_next:
                inc hl
                djnz exit_page
                ld hl, T_PARENT
                ld b, TASK_SLOTS
exit_orphan:
                ld a, (hl)
                cp c
                jr nz, exit_orphan_next
                ld (hl), 0FFh
                ld a, l
                sub T_PARENT - T_STATE
                ld l, a
                ld a, (hl)
                cp TS_ZOMBIE
                jr nz, exit_orphan_back
                ld (hl), TS_FREE
exit_orphan_back:
                ld a, l
                add a, T_PARENT - T_STATE
                ld l, a
exit_orphan_next:
                inc l
                djnz exit_orphan
                di
                pop de
                ld a, c
                add a, T_PARENT & 0FFh
                ld l, a
                ld b, (hl)
                sub T_PARENT - T_STATE
                ld l, a
                ld (hl), TS_FREE
                ld a, b
                inc a
                jr z, exit_done
                dec a
                jr z, exit_done
                ld (hl), TS_ZOMBIE
                ld a, c
                add a, a
                add a, T_ARG & 0FFh
                ld l, a
                ld (hl), e
                ld a, CH_CHILD
                call wake
exit_done:
                jp sched_pick
exit_halt:
                di
                halt
                jr exit_halt

; E = task id, 0FFh any child, 0FEh one zombie without blocking.
; HL = id << 8 | exit code.
sys_wait:
                ld a, (CUR)
                ld d, a
                ld bc, 1
wait_slot:
                ld a, c
                add a, T_PARENT & 0FFh
                ld l, a
                ld h, T_PARENT >> 8
                ld a, (hl)
                cp d
                jr nz, wait_next
                ld a, e
                cp 0FEh
                jr nc, wait_match
                cp c
                jr nz, wait_next
wait_match:
                ld a, l
                sub T_PARENT - T_STATE
                ld l, a
                ld a, (hl)
                or a
                jr z, wait_next
                cp TS_ZOMBIE
                jr z, wait_reap
                inc b
wait_next:
                inc c
                bit 3, c
                jr z, wait_slot
                ld a, e
                cp 0FEh
                jr z, wait_none
                ld a, b
                or a
                ld a, CH_CHILD
                jp nz, block_retry
wait_none:
                ld a, ECHILD
                jp syscall_err
wait_reap:
                ld (hl), TS_FREE
                ld a, c
                add a, a
                add a, T_ARG & 0FFh
                ld l, a
                ld l, (hl)
                ld h, c
                jp syscall_ok

; E = task id 1-7. The task ends with EXIT_KILLED before it runs user code again.
sys_kill:
                ld a, e
                dec a
                cp TASK_SLOTS - 1
                jp nc, sc_einval
                di
                ld a, e
                call kill_mark
                ei
                jp c, sc_einval
                ld hl, 0
                jp syscall_ok

sys_yield:
                xor a
                ld (QUANTUM), a
                ld h, a
                ld l, a
                jp syscall_ok

; Task 0. Starts a shell for each console that wants one, else idles in HALT.
init_task:
                di
                ld a, (CON_WANT)
                or a
                jr nz, init_spawn
                ei
                halt
                jr init_task
init_spawn:
                xor a
                ld (CON_WANT), a
                ei
                ld c, SYS_SPAWN
                ld de, shell_path
                ld hl, empty_argv
                ld ix, 0
                rst 08h
                jr init_task

shell_path:     db "/bin/sh", 0
empty_argv:     db 0, 0

                kvar spawn_tid, 1
                kvar spawn_fd, 2
