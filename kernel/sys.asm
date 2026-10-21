; System page jumps. The ROM enters here with interrupts still disabled.

sys_init:
                ld hl, sys_vectors
                ld de, SYSPAGE
                ld bc, SYS_ISR + 3 - SYSPAGE
                ldir
                ld a, 0C3h
                ld (SYS_NMI), a
                ld hl, nmi
                ld (SYS_NMI + 1), hl

                xor a
                ld hl, TICK_COUNT
                ld bc, 4048h - TICK_COUNT
                call fill
                ld hl, KBD_ACCEPTED
                ld bc, BLINK_DIV - KBD_ACCEPTED
                call fill
                ld hl, CUR
                ld bc, 40FFh - CUR
                call fill
                ld hl, KPAGE
                ld bc, 2FFh
                call fill
                out (PORT_NMI), a
                out (PORT_VIDEO), a
                inc a
                ld (KBUSY), a
                ld (vol_sb), a
                ld (T_STATE), a
                ld (CON_WANT), a
                ld (CON_STATE), a
                ld hl, (SHADOW1 & 0FF00h) | (VIDEO_BASE >> 8)
                ld (CON_PLANE), hl
                ld hl, VIDEO_BASE & 0FF00h
                ld (CON_BOUND), hl
                ld hl, init_rec
                ld de, TASK
                ld bc, 16
                ldir
                ld hl, OFILE
                ld c, 0
init_con:
                ld a, KIND_CON_IN
                call init_ofile
                ld a, KIND_CON_OUT
                call init_ofile
                call init_ofile
                inc c
                bit 1, c
                jr z, init_con
                ld a, 0FFh
                ld (KBD_REP_ROW), a
                ld a, ' '
                ld (CUR_UNDER), a
                ld (CON_BLOCK + 14 + CUR_UNDER - CUR_ROW), a
                ld hl, VIDEO_BASE
                ld bc, VIDEO_SIZE - 1
                call fill
                ld hl, SHADOW1
                ld bc, VIDEO_SIZE - 1
                call fill
                in a, (PORT_TIMER_ACK)
                ld a, IRQ_TIMER
                out (PORT_IRQ), a
                ret

; RST 08h. A switch before KBUSY is set is an ordinary preemption of user code.
syscall:
                push af
                ld a, 1
                ld (KBUSY), a
                push bc
                push de
                push hl
                push ix
                push iy
                ex af, af'
                exx
                push af
                push bc
                push de
                push hl
                exx
                ex af, af'
                ld (SC_FRAME), sp
                push bc
                xor a
                call VB_ENT
                pop bc
                ld a, c
                cp SYS_SYNC
                jp z, sys_sync
                cp SYS_TIME
                jp z, sys_time
                cp SYS_SETTIME
                jp z, sys_settime
                cp SYS_IOCTL + 1
                jr nc, sc_high
                add a, a
                ld hl, sc_table
                add a, l
                ld l, a
                adc a, h
                sub l
                ld h, a
                ld a, (hl)
                inc hl
                ld h, (hl)
                ld l, a
                push hl
                ld hl, F_HL + 2
                add hl, sp
                ld a, (hl)
                inc hl
                ld h, (hl)
                ld l, a
                ret

sc_high:
                rst HOOK_CALL
sc_einval:
                ld a, EINVAL
syscall_err:
                ld hl, 0
                scf
                jr syscall_exit
syscall_ok:
                xor a
; A, carry and HL are the result.
syscall_exit:
                ld ix, (SC_FRAME)
                ld (ix + F_HL), l
                ld (ix + F_HL + 1), h
                push af
                pop hl
                ld (ix + F_AF), l
                ld (ix + F_AF + 1), h
                ld sp, ix
                di
                ld a, (QUANTUM)
                or a
                jp z, sched_save
                ld a, (CUR)
                or a
                jp z, sched_save
                call t_state_a
                ld a, (hl)
                dec a
                jp nz, sched_save
                xor a
                ld (KBUSY), a
                jp frame_return

sc_table:
                dw sys_exit, sys_spawn, sys_wait, sys_getpid
                dw sys_yield, DEV_SLEEP, sys_kill, DEV_UPTIME
                dw sc_einval, sc_einval, sc_einval, sc_einval
                dw sc_einval, sc_einval, sc_einval, sc_einval
                dw DEV_ALLOC, DEV_FREE, DEV_MEMINFO, sc_einval
                dw sc_einval, sc_einval, sc_einval, sc_einval
                dw sc_einval, sc_einval, sc_einval, sc_einval
                dw sc_einval, sc_einval, sc_einval, sc_einval
                dw sys_open, sys_close, sys_read, sys_write
                dw DEV_SEEK, sys_stat, sys_fstat, sys_readdir
                dw sys_mkdir, sys_remove, sys_rename, sys_chdir
                dw sys_getcwd, DEV_DUP2, sys_pipe, sys_ioctl
                assert $ - sc_table == (SYS_IOCTL + 1) * 2

; HL = resident routine. It returns carry and A, or a result in HL.
wr_go:
                call wr_go_keep
                jp c, syscall_err
                jp syscall_ok

; Like wr_go, but return to the caller so open can allocate a descriptor.
wr_go_keep:
                ld a, (wr_ready)
                or a
                jr z, wr_keep_down
                jp (hl)
wr_keep_down:
                ld a, EIO
                scf
                ret

sys_sync:
                ld hl, WR_SYNC
                jp wr_go

sys_time:
                ld hl, WR_TIME
                jp wr_go

sys_settime:
                ld hl, WR_SET
                jp wr_go

sys_getpid:
                ld a, (TASK + TASK_ID)
                ld l, a
                ld h, 0
                jp syscall_ok

; HL = fd slot of the running task. Closes it if open.
fd_drop:
                ld a, (hl)
                cp 0FFh
                ret z
                ld (hl), 0FFh
                call ofile_of
; HL = ofile. Drops one reference and frees the ofile with the last.
ofile_release:
                inc hl
                dec (hl)
                dec hl
                ret nz
                ld a, (hl)
                ld (hl), KIND_FREE
                rst HOOK_CLOSE
                sub KIND_PIPE_R
                cp 2
                ret nc
                inc a
                ld b, a
                inc hl
                inc hl
                ld a, (hl)
                jp pipe_end_closed

; Ends the call with 0 when io_len is 0. Keeps HL.
io_empty:
                ld de, (io_len)
                ld a, d
                or e
                ret nz
                ex de, hl
                jp syscall_ok

ofile_of:
                push de
                ld l, a
                ld h, 0
                add hl, hl
                add hl, hl
                add hl, hl
                ld de, OFILE
                add hl, de
                pop de
                ret

map_check:
                ld hl, (spawn_map)
                ld a, h
                or l
                ret z
                ld b, FD_SLOTS
map_check_one:
                ld a, (hl)
                cp 0FFh
                jr z, map_check_next
                cp FD_SLOTS
                jr nc, map_bad
                push hl
                push bc
                ld e, a
                ld d, 0
                ld hl, TASK + TASK_FD
                add hl, de
                ld a, (hl)
                pop bc
                pop hl
                cp 0FFh
                jr z, map_bad
map_check_next:
                inc hl
                djnz map_check_one
                xor a
                ret
map_bad:
                ld a, EBADF
                scf
                ret

; Fills the fd table at spawn_fd from spawn_map, adding a reference per fd.
map_apply:
                ld hl, (spawn_fd)
                ld b, FD_SLOTS
map_clear:
                ld (hl), 0FFh
                inc hl
                djnz map_clear
                ld hl, (spawn_map)
                ld a, h
                or l
                jr z, map_inherit
                ld c, 0
map_each:
                ld a, (hl)
                cp 0FFh
                jr z, map_each_next
                push hl
                push bc
                call map_dup
                pop bc
                pop hl
map_each_next:
                inc hl
                inc c
                ld a, c
                cp FD_SLOTS
                jr c, map_each
                ret
map_inherit:
                ld c, 0
map_inh:
                ld a, c
                push bc
                call map_dup
                pop bc
                inc c
                ld a, c
                cp 3
                jr c, map_inh
                ret

; A = parent fd, C = child slot.
map_dup:
                ld e, a
                ld d, 0
                ld hl, TASK + TASK_FD
                add hl, de
                ld a, (hl)
                ld e, c
                ld hl, (spawn_fd)
                add hl, de
                ld (hl), a
                call ofile_of
                inc hl
                inc (hl)
                ret

sys_close:
                ld a, e
                cp FD_SLOTS
                ld a, EBADF
                jp nc, syscall_err
                ld d, 0
                ld hl, TASK + TASK_FD
                add hl, de
                call fd_drop
                ld hl, 0
                jp syscall_ok

; E = fd. HL = ofile, A = kind.
fd_get:
                ld a, e
                cp FD_SLOTS
                jr nc, fd_bad
                ld d, 0
                ld hl, TASK + TASK_FD
                add hl, de
                ld a, (hl)
                cp 0FFh
                jr z, fd_bad
                call ofile_of
                ld a, (hl)
                or a
                jr z, fd_bad
                ret
fd_bad:
                ld a, EBADF
                scf
                ret

sys_read:
                ld (io_buf), hl
                ld (io_len), ix
                call fd_get
                jp c, syscall_err
                cp KIND_CON_IN
                jp z, read_con
                cp KIND_PIPE_R
                jp z, pipe_read
                cp KIND_FILE
                jp z, read_file
                cp KIND_DIR
                jr nz, read_bad
                ld a, EISDIR
                jp syscall_err
read_bad:
                rst HOOK_CALL
                ld a, EBADF
                jp syscall_err

; Fills all io_len bytes. Interrupts stay off from the empty test to the block.
read_con:
                inc hl
                inc hl
                ld b, (hl)
                call io_empty
                ld hl, 0
                ld (io_got), hl
                di
                ld a, (CON_ACTIVE)
                cp b
                jr nz, read_round
read_store:
                ld a, b
                add a, a
                add a, CON_FG & 0FFh
                ld l, a
                ld h, CON_FG >> 8
                ld a, (hl)
                or a
                jr z, read_store_get
                ld e, a
                ld a, (CUR)
                cp e
                jr nz, read_round
read_store_get:
                call kbd_get
                jr nc, read_round
                ld hl, (io_buf)
                ld (hl), a
                inc hl
                ld (io_buf), hl
                ld hl, (io_got)
                inc hl
                ld (io_got), hl
                ld hl, (io_len)
                dec hl
                ld (io_len), hl
                ld a, h
                or l
                jr nz, read_store
read_round:
                ld a, CH_KEY

; A = channel. io_got bytes moved this round and io_len are left. With bytes
; left, the frame's HL and IX advance past this round, T_ARG keeps the total,
; and the call blocks. Otherwise HL = the total and the caller's IX is restored.
io_round:
                push af
                ld a, (CUR)
                add a, a
                add a, T_ARG & 0FFh
                ld l, a
                ld h, T_ARG >> 8
                ld e, (hl)
                inc l
                ld d, (hl)
                push hl
                ld hl, (io_got)
                add hl, de
                ex de, hl
                pop hl
                ld ix, (SC_FRAME)
                ld a, (io_len)
                ld b, a
                ld a, (io_len + 1)
                or b
                jr z, io_done
                ld (hl), d
                dec l
                ld (hl), e
                ld de, (io_got)
                ld l, (ix + F_HL)
                ld h, (ix + F_HL + 1)
                add hl, de
                ld (ix + F_HL), l
                ld (ix + F_HL + 1), h
                ld l, (ix + F_IX)
                ld h, (ix + F_IX + 1)
                or a
                sbc hl, de
                ld (ix + F_IX), l
                ld (ix + F_IX + 1), h
                pop af
                jp block_retry
io_done:
                ld (hl), a
                dec l
                ld (hl), a
                pop af
                ex de, hl
                ld (ix + F_IX), l
                ld (ix + F_IX + 1), h
                jp syscall_ok

read_file:
                call take_inode
                jp c, syscall_err
                ld hl, (io_buf)
                ld ix, (io_len)
                ld de, (io_pos)
                call c5fs_read
                jp c, syscall_err
                push hl
                ld b, h
                ld c, l
                ld hl, (io_pos)
                call add32
                pop hl
                jp syscall_ok

sys_write:
                ld (io_buf), hl
                ld (io_len), ix
                call fd_get
                jp c, syscall_err
                cp KIND_CON_OUT
                jr z, write_con
                cp KIND_PIPE_W
                jp z, pipe_write
                cp KIND_FILE
                jr z, write_file
                cp KIND_DIR
                jr z, write_dir
                rst HOOK_CALL
                ld a, EBADF
                jp syscall_err
write_dir:
                ld a, EISDIR
                jp syscall_err
write_file:
                ld (ofile_ptr), hl
                ld hl, WR_WRITE
                jp wr_go
write_con:
                inc hl
                inc hl
                ld e, (hl)
                ld hl, (io_buf)
                ld bc, (io_len)
write_loop:
                ld a, b
                or c
                jr z, write_done
                ld a, (hl)
                inc hl
                push hl
                push bc
                push de
                ld d, e
                call console_putc
                pop de
                pop bc
                pop hl
                dec bc
                jr write_loop
write_done:
                ld hl, (io_len)
                jp syscall_ok

; DE = console fd, HL = request, IX = argument. HL = the previous value.
sys_ioctl:
                push hl
                call fd_get
                pop bc
                jp c, syscall_err
                rst HOOK_CALL
                dec a
                cp KIND_CON_OUT
                jp nc, sc_einval
                inc hl
                inc hl
                ld a, (hl)
                add a, CON_FG & 0FFh
                ld l, a
                ld h, CON_FG >> 8
                push ix
                pop de
                ld a, c
                cp 5
                jp nc, SC_HIST
                ld a, b
                or d
                jp nz, sc_einval
                dec c
                jr z, ioctl_fg
                dec c
                jp nz, sc_einval
                jr ioctl_mode
ioctl_fg:
                ld a, e
                cp TASK_SLOTS
                jp nc, sc_einval
                push hl
                call t_state_a
                ld a, (hl)
                pop hl
                dec a
                cp TS_DYING
                jp nc, sc_einval
ioctl_set:
                ld a, (hl)
                ld (hl), e
                ld l, a
                ld h, 0
                jp syscall_ok
ioctl_mode:
                inc l
                inc l
                ld a, e
                and ~CON_RAW
                jp nz, sc_einval
                jr ioctl_set

sys_seek:
seek_file:
                call take_inode
                jp c, syscall_err
                ld a, (seek_whence)
                or a
                jr z, seek_set
                dec a
                jr z, seek_cur
                dec a
                jr z, seek_end
                jp sc_einval
seek_set:
                ld hl, seek_base
                ld b, 4
seek_zero:
                ld (hl), 0
                inc hl
                djnz seek_zero
                jr seek_add
seek_cur:
                ld hl, (io_pos)
                ld de, seek_base
                ld bc, 4
                ldir
                jr seek_add
seek_end:
                ld hl, seek_base
                ld b, 4
seek_end_z:
                ld (hl), 0
                inc hl
                djnz seek_end_z
                ld a, (INO_BUF + INO_SIZE)
                ld (seek_base), a
                ld a, (INO_BUF + INO_SIZE + 1)
                ld (seek_base + 1), a
                ld a, (INO_BUF + INO_SIZE + 2)
                ld (seek_base + 2), a
seek_add:
                ld hl, (io_buf)
                ld de, seek_base
                ld b, 4
                or a
seek_byte:
                ld a, (de)
                adc a, (hl)
                ld (de), a
                inc hl
                inc de
                djnz seek_byte
                ld a, (seek_base + 3)
                bit 7, a
                jr z, seek_store
                jp sc_einval
seek_store:
                ld hl, seek_base
                ld de, (io_pos)
                ld bc, 4
                ldir
                ld hl, seek_base
                ld de, (io_buf)
                ld bc, 4
                ldir
                ld hl, 0
                jp syscall_ok

; HL = ofile from fd_get. Loads its inode and points io_pos at POS.
take_inode:
                rst HOOK_INODE
                ld de, OF_INO
                add hl, de
                ld c, (hl)
                inc hl
                ld b, (hl)
                inc hl
                ld (io_pos), hl
                jp c5fs_inode

sys_stat:
                ld (io_buf), hl
                call c5fs_walk
                jp c, syscall_err
                ld b, h
                ld c, l
                ld hl, (io_buf)
                call c5fs_stat
                jp syscall_ok

sys_fstat:
                ld (io_buf), hl
                call fd_get
                jp c, syscall_err
                cp KIND_FILE
                jr z, fstat_go
                cp KIND_DIR
                jr z, fstat_go
                jp sc_einval
fstat_go:
                call take_inode
                jp c, syscall_err
                ld hl, (io_buf)
                call c5fs_stat
                jp syscall_ok

sys_readdir:
                ld (io_buf), hl
                call fd_get
                jp c, syscall_err
                cp KIND_DIR
                jr z, readdir_go
                ld a, ENOTDIR
                jp syscall_err
readdir_go:
                call take_inode
                jp c, syscall_err
                ld hl, (io_pos)
                ld e, (hl)
                inc hl
                ld d, (hl)
                ld hl, (io_buf)
                call c5fs_readdir
                jp c, syscall_err
                push hl
                ld a, h
                or l
                jr z, readdir_done
                ld hl, (io_pos)
                ld (hl), e
                inc hl
                ld (hl), d
                inc hl
                xor a
                ld (hl), a
                inc hl
                ld (hl), a
readdir_done:
                pop hl
                jp syscall_ok

sys_mkdir:
                ld (io_path), de
                call c5fs_walk
                jr nc, mkdir_have
                cp ENOENT
                jp nz, syscall_err
                ld a, b
                cp 1
                jr nz, mkdir_miss
                ld hl, WR_MKDIR
                jp wr_go
mkdir_miss:
                ld a, ENOENT
                jp syscall_err
mkdir_have:
                ld a, EEXIST
                jp syscall_err

sys_remove:
                ld (io_path), de
                call c5fs_syntax
                jp c, syscall_err
                call path_is_root
                jr nz, remove_walk
                ld a, EBUSY
                jp syscall_err
remove_walk:
                ld de, (io_path)
                call c5fs_walk
                jp c, syscall_err
                ld (wr_child), hl
                ld hl, WR_REMOVE
                jp wr_go

path_is_root:
                ld hl, (io_path)
path_slash:
                ld a, (hl)
                cp '/'
                jr nz, path_end
                inc hl
                jr path_slash
path_end:
                or a
                ret

sys_rename:
                ld (ren_old), de
                ld (ren_new), hl
                call c5fs_syntax
                jp c, syscall_err
                ld de, (ren_new)
                call c5fs_syntax
                jp c, syscall_err
                ld hl, WR_RENAME
                jp wr_go

sys_chdir:
                call c5fs_walk
                jp c, syscall_err
                ld a, (INO_BUF + INO_TYPE)
                and 0Fh
                cp INO_KIND_DIR
                jr z, chdir_ok
                ld a, ENOTDIR
                jp syscall_err
chdir_ok:
                ld (TASK + TASK_CWD), hl
                ld hl, 0
                jp syscall_ok

sys_getcwd:
                ld (cwd_buf), de
                ld (cwd_size), hl
                ld hl, (TASK + TASK_CWD)
                call cwd_is_root
                jr nz, cwd_deep
                jp cwd_store_root
cwd_deep:
                ld hl, 0
                ld (cwd_need), hl
                ld hl, (TASK + TASK_CWD)
cwd_count:
                call cwd_is_root
                jr z, cwd_counted
                call cwd_step
                jp c, syscall_err
                push hl
                ld hl, (cwd_need)
                ld b, 0
                add hl, bc
                inc hl
                ld (cwd_need), hl
                ld a, h
                or a
                jr nz, cwd_bad
                ld a, l
                cp PATH_MAX + 1
                jr nc, cwd_bad
                pop hl
                jr cwd_count
cwd_bad:
                pop hl
                ld a, EIO
                jp syscall_err
cwd_counted:
                ld hl, (cwd_need)
                inc hl
                ld de, (cwd_size)
                ld a, d
                cp h
                jr c, cwd_small
                jr nz, cwd_fit
                ld a, e
                cp l
                jr nc, cwd_fit
cwd_small:
                jp sc_einval
cwd_fit:
                ld hl, (cwd_buf)
                ld de, (cwd_need)
                add hl, de
                ld (hl), 0
                ld (cwd_pos), hl
                ld hl, (TASK + TASK_CWD)
cwd_place_loop:
                call cwd_is_root
                jr z, cwd_placed
                call cwd_step
                jp c, syscall_err
                push hl
                call cwd_place
                pop hl
                jr cwd_place_loop
cwd_placed:
                ld hl, 0
                jp syscall_ok

cwd_store_root:
                ld hl, (cwd_size)
                ld a, h
                or a
                jr nz, cwd_root_write
                ld a, l
                cp 2
                jr nc, cwd_root_write
                jp sc_einval
cwd_root_write:
                ld hl, (cwd_buf)
                ld (hl), '/'
                inc hl
                ld (hl), 0
                ld hl, 0
                jp syscall_ok

; HL = inode. Z when it is inode 1.
cwd_is_root:
                ld a, h
                or a
                ret nz
                ld a, l
                cp 1
                ret

; HL = child. Returns HL = parent, C = name length, name at cwd_ent+2.
cwd_step:
                ld (cwd_ino), hl
                ld b, h
                ld c, l
                call c5fs_inode
                ret c
                ld de, 0
                ld hl, cwd_ent
                call c5fs_readdir
                ret c
                ld a, h
                or l
                jr z, cwd_eio
                ld hl, (cwd_ent)
                ld (cwd_parent), hl
                ld b, h
                ld c, l
                call c5fs_inode
                ret c
                ld de, 0
cwd_find:
                ld hl, cwd_ent
                call c5fs_readdir
                ret c
                ld a, h
                or l
                jr z, cwd_eio
                push de
                ld hl, (cwd_ent)
                ld de, (cwd_ino)
                or a
                sbc hl, de
                pop de
                jr nz, cwd_find
                ld hl, cwd_ent + 2
                ld b, 30
                ld c, 0
cwd_nlen:
                ld a, (hl)
                or a
                jr z, cwd_nlen_done
                inc c
                inc hl
                djnz cwd_nlen
cwd_nlen_done:
                ld hl, (cwd_parent)
                xor a
                ret
cwd_eio:
                ld a, EIO
                scf
                ret

; C = name length. Name bytes are at cwd_ent+2.
cwd_place:
                ld hl, (cwd_pos)
                ld b, 0
                or a
                sbc hl, bc
                ld (cwd_pos), hl
                ex de, hl
                ld hl, cwd_ent + 2
                ldir
                ld hl, (cwd_pos)
                dec hl
                ld (hl), '/'
                ld (cwd_pos), hl
                ret

sys_open:
                ld (io_path), de
                ld a, b
                ld (open_flags), a
                and 0C0h
                jr z, open_known
                jp sc_einval
open_known:
                ld a, (open_flags)
                and 3Fh
                jr nz, open_excl
                jp sc_einval
open_excl:
                ld a, (open_flags)
                and O_EXCL
                jr z, open_class
                ld a, (open_flags)
                and O_CREATE
                jr nz, open_class
                jp sc_einval
open_class:
                rst HOOK_CALL
                ld a, (open_flags)
                and O_WRITE | O_CREATE | O_TRUNC | O_APPEND
                jr nz, open_mut
                call c5fs_walk
                jp c, syscall_err
                ld (open_ino), hl
                ld a, (INO_BUF + INO_TYPE)
                and 0Fh
                cp INO_KIND_FILE
                ld c, KIND_FILE
                jr z, open_new
                cp INO_KIND_DIR
                ld c, KIND_DIR
                jr z, open_new
                ld a, EIO
                jp syscall_err
open_mut:
                ld hl, WR_OPEN
                call wr_go_keep
                jp c, syscall_err
                ld a, (open_kind)
                ld c, a
                jp open_new
open_new:
                ld a, c
                ld (open_kind), a
                call fd_alloc
                jp c, syscall_err
                jp syscall_ok

fd_alloc:
                ld b, 0
fd_scan:
                ld hl, TASK + TASK_FD
                ld e, b
                ld d, 0
                add hl, de
                ld a, (hl)
                cp 0FFh
                jr z, of_scan
                inc b
                ld a, b
                cp FD_SLOTS
                jr c, fd_scan
                ld a, EMFILE
                scf
                ret
of_scan:
                ld c, 0
of_next:
                ld a, c
                call ofile_of
                ld a, (hl)
                or a
                jr z, of_fill
                inc c
                ld a, c
                cp OFILE_SLOTS
                jr c, of_next
                ld a, EMFILE
                scf
                ret
of_fill:
                ld a, (open_kind)
                ld (hl), a
                inc hl
                ld (hl), 1
                inc hl
                ld de, (open_ino)
                ld (hl), e
                inc hl
                ld (hl), d
                inc hl
                xor a
                ld (hl), a
                inc hl
                ld (hl), a
                inc hl
                ld (hl), a
                inc hl
                ld (hl), a
                dec hl
                dec hl
                dec hl
                ld a, (open_flags)
                and O_APPEND
                jr z, of_noapp
                ld a, (INO_BUF + INO_SIZE)
                ld (hl), a
                inc hl
                ld a, (INO_BUF + INO_SIZE + 1)
                ld (hl), a
                inc hl
                ld a, (INO_BUF + INO_SIZE + 2)
                ld (hl), a
                inc hl
of_noapp:
                ld a, c
                ld hl, TASK + TASK_FD
                ld e, b
                ld d, 0
                add hl, de
                ld (hl), a
                ld l, b
                ld h, 0
                xor a
                ret

; A = load page, HL = argv. INO_BUF is the file.
; HL = entry, B = page count. child_sp and child_argv are set.
load_c5x:
                ld (ld_page), a
                ld (ld_argv), hl
                ld a, (INO_BUF + INO_SIZE + 2)
                or a
                jr nz, ld_hdr_read
                ld a, (INO_BUF + INO_SIZE + 1)
                or a
                jr nz, ld_hdr_read
                ld a, (INO_BUF + INO_SIZE)
                cp 16
                jp c, ld_exec
ld_hdr_read:
                ld hl, 0
                ld (ld_pos), hl
                ld (ld_pos + 2), hl
                ld hl, ld_hdr
                ld bc, 16
                call ld_exact
                ret c
                ld a, (ld_hdr)
                cp 'C'
                jp nz, ld_exec
                ld a, (ld_hdr + 1)
                cp '5'
                jp nz, ld_exec
                ld a, (ld_hdr + 2)
                cp 'X'
                jp nz, ld_exec
                ld a, (ld_hdr + 3)
                cp 1
                jp nz, ld_exec
                ld hl, ld_hdr + 12
                ld b, 4
ld_res:
                ld a, (hl)
                or a
                jp nz, ld_exec
                inc hl
                djnz ld_res
                call ld_expect
                jp c, ld_exec
                call ld_size_cmp
                jp c, ld_exec
                call ld_fit_arena
                ret c
                ld hl, (ld_hdr + 10)
                ld de, (ld_hdr + 4)
                or a
                sbc hl, de
                jp nc, ld_exec
                call ld_padding
                ret c
                call ld_argv_ok
                ret c
                ld hl, 16
                ld (ld_pos), hl
                ld hl, 0
                ld (ld_pos + 2), hl
                ld a, (ld_page)
                ld h, a
                ld l, 0
                ld bc, (ld_hdr + 4)
                call ld_exact
                ret c
                call ld_reloc
                ret c
                call ld_zero_bss
                call ld_copy_argv
                jp ld_finish

ld_exec:
                ld a, ENOEXEC
                scf
                ret

; Stores the expected file length, 16 + image + ceil(image / 8).
ld_expect:
                ld hl, (ld_hdr + 4)
                ld de, 7
                add hl, de
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                ld (ld_bbytes), hl
                ld de, 16
                add hl, de
                ld a, 0
                adc a, 0
                ld c, a
                ld de, (ld_hdr + 4)
                add hl, de
                ld a, c
                adc a, 0
                ld (ld_expect_b), a
                ld (ld_expect_w), hl
                xor a
                ret

; Carry set unless the file length equals the expected C5X length.
ld_size_cmp:
                ld hl, INO_BUF + INO_SIZE
                ld a, (ld_expect_w)
                cp (hl)
                jr nz, ld_size_no
                inc hl
                ld a, (ld_expect_w + 1)
                cp (hl)
                jr nz, ld_size_no
                inc hl
                ld a, (ld_expect_b)
                cp (hl)
                jr nz, ld_size_no
                xor a
                ret
ld_size_no:
                scf
                ret

; Carry and ENOMEM when image + bss + stack + 192 exceeds the run from ld_page
; to RUN_END. Checked before the image read, which would overwrite the next task.
ld_fit_arena:
                ld hl, (ld_hdr + 4)
                ld de, (ld_hdr + 6)
                add hl, de
                ld a, 0
                adc a, 0
                ld c, a
                ld de, (ld_hdr + 8)
                add hl, de
                ld a, c
                adc a, 0
                ld c, a
                ld de, KERNEL_RESERVE
                add hl, de
                ld a, c
                adc a, 0
                jr nz, ld_fit_no
                ld a, (ld_page)
                ld e, a
                ld a, (RUN_END)
                sub e
                ld d, a
                ld e, 0
                sbc hl, de
                jr z, ld_fit_ok
                jr c, ld_fit_ok
ld_fit_no:
                ld a, ENOMEM
                scf
                ret
ld_fit_ok:
                xor a
                ret

ld_padding:
                ld a, (ld_hdr + 4)
                and 7
                ret z
                ld b, a
                ld a, 0FFh
ld_pmask:
                add a, a
                djnz ld_pmask
                ld (ld_mask), a
                ld hl, (ld_expect_w)
                ld a, (ld_expect_b)
                ld de, 1
                or a
                sbc hl, de
                sbc a, 0
                ld (ld_pos), hl
                ld (ld_pos + 2), a
                xor a
                ld (ld_pos + 3), a
                ld hl, ld_byte
                ld bc, 1
                call ld_exact
                ret c
                ld a, (ld_mask)
                ld b, a
                ld a, (ld_byte)
                and b
                ret z
                ld a, ENOEXEC
                scf
                ret

ld_argv_ok:
                ld hl, (ld_argv)
                ld a, (hl)
                cp 9
                jr nc, ld_argv_inval
                ld c, a
                inc hl
                ld a, (hl)
                cp 9
                jr nc, ld_argv_inval
                add a, c
                jr c, ld_argv_inval
                ld b, a
                inc hl
                ld e, 2
ld_argv_str:
                ld a, b
                or a
                jr z, ld_argv_len
                dec b
ld_argv_ch:
                ld a, e
                cp ARGV_MAX
                jr nc, ld_argv_inval
                ld a, (hl)
                inc hl
                inc e
                or a
                jr nz, ld_argv_ch
                jr ld_argv_str
ld_argv_len:
                ld a, e
                ld (ld_argn), a
                ld e, a
                ld d, 0
                ld hl, (ld_hdr + 8)
                or a
                sbc hl, de
                jr nc, ld_argv_fit
                ld a, ENOMEM
                scf
                ret
ld_argv_fit:
                xor a
                ret
ld_argv_inval:
                ld a, EINVAL
                scf
                ret

; HL = destination, BC = exact length. ld_pos is the file offset.
ld_exact:
                push bc
                pop ix
                push bc
                ld de, ld_pos
                call c5fs_read
                pop bc
                ret c
                or a
                sbc hl, bc
                jr z, ld_pos_add
                ld a, EIO
                scf
                ret

ld_reloc:
                ld hl, 0
                ld (ld_index), hl
ld_reloc_loop:
                ld hl, (ld_bbytes)
                ld a, h
                or l
                ret z
                ld a, (ld_pos)
                ld (ld_byte), a
                ld a, (ld_pos + 1)
                ld e, a
                ld a, (ld_pos + 2)
                ld d, a
                call fs_map
                ret c
                ld hl, BLK_BUF
                call floppy_read
                ret c
                ld a, (ld_byte)
                ld e, a
                ld d, 0
                ld hl, 256
                or a
                sbc hl, de
                ld de, (ld_bbytes)
                push hl
                or a
                sbc hl, de
                pop hl
                jr c, ld_reloc_n
                ld h, d
                ld l, e
ld_reloc_n:
                ld b, h
                ld c, l
                ld a, (ld_byte)
                ld hl, BLK_BUF
                add a, l
                ld l, a
                ld a, h
                adc a, 0
                ld h, a
                push bc
                call ld_apply
                pop bc
                call ld_pos_add
                ld hl, (ld_bbytes)
                or a
                sbc hl, bc
                ld (ld_bbytes), hl
                jr ld_reloc_loop

ld_pos_add:
                ld hl, ld_pos
; HL = 32-bit value, BC = addend. A = 0, carry clear.
add32:
                ld a, (hl)
                add a, c
                ld (hl), a
                inc hl
                ld a, (hl)
                adc a, b
                ld (hl), a
                inc hl
                ld a, (hl)
                adc a, 0
                ld (hl), a
                inc hl
                ld a, (hl)
                adc a, 0
                ld (hl), a
                xor a
                ret

; HL = first bitmap byte, BC = count. The bytes stay in BLK_BUF until this returns.
ld_apply:
                ld (ld_bptr), hl
ld_apply_byte:
                ld a, b
                or c
                ret z
                dec bc
                push bc
                ld hl, (ld_bptr)
                ld a, (hl)
                inc hl
                ld (ld_bptr), hl
                ld d, a
                ld e, 1
ld_apply_bit:
                ld hl, (ld_index)
                push de
                ld de, (ld_hdr + 4)
                or a
                sbc hl, de
                pop de
                jr nc, ld_apply_stop
                ld a, d
                and e
                call nz, ld_patch
                ld hl, (ld_index)
                inc hl
                ld (ld_index), hl
                ld a, e
                add a, a
                ld e, a
                jr nz, ld_apply_bit
                pop bc
                jr ld_apply_byte
ld_apply_stop:
                pop bc
                ret

ld_patch:
                push de
                ld hl, (ld_index)
                ld a, (ld_page)
                ld d, a
                ld e, 0
                add hl, de
                add a, (hl)
                ld (hl), a
                pop de
                ret

ld_zero_bss:
                ld a, (ld_page)
                ld h, a
                ld l, 0
                ld de, (ld_hdr + 4)
                add hl, de
                ld bc, (ld_hdr + 6)
                ld a, b
                or c
                jr z, ld_argv_at
                ld (hl), 0
                dec bc
                ld a, b
                or c
                jr z, ld_bss_one
                ld e, l
                ld d, h
                inc de
                ldir
                ld h, d
                ld l, e
                jr ld_argv_at
ld_bss_one:
                inc hl
ld_argv_at:
                ld (child_argv), hl
                ret

ld_copy_argv:
                ld a, (ld_argn)
                ld c, a
                ld b, 0
                ld hl, (ld_argv)
                ld de, (child_argv)
                ldir
                ret

ld_finish:
                ld hl, (child_argv)
                ld de, (ld_hdr + 8)
                add hl, de
                ld de, KERNEL_RESERVE
                add hl, de
                ld (child_sp), hl
                ld hl, (ld_hdr + 4)
                ld de, (ld_hdr + 6)
                add hl, de
                ld de, (ld_hdr + 8)
                add hl, de
                ld de, KERNEL_RESERVE
                add hl, de
                ld de, 255
                add hl, de
                ld b, h
                ld a, (ld_page)
                ld h, a
                ld l, 0
                ld de, (ld_hdr + 10)
                add hl, de
                xor a
                ret

                kvar spawn_argv, 2
                kvar spawn_map, 2
                kvar io_buf, 2
                kvar io_len, 2
                kvar io_got, 2
                kvar io_pos, 2
                kvar io_path, 2
                kvar ren_old, 2
                kvar ren_new, 2
                kvar open_flags, 1
                kvar open_kind, 1
                kvar open_ino, 2
                kvar ofile_ptr, 2
                kvar seek_whence, 1
                kvar seek_base, 4
                kvar cwd_buf, 2
                kvar cwd_size, 2
                kvar cwd_need, 2
                kvar cwd_pos, 2
                kvar cwd_ino, 2
                kvar cwd_parent, 2
                kvar cwd_ent, 32
                kvar child_sp, 2
                kvar child_argv, 2
                kvar ld_page, 1
                kvar ld_argv, 2
                kvar ld_argn, 1
                kvar ld_pos, 4
                kvar ld_hdr, 16
                kvar ld_bbytes, 2
                kvar ld_expect_w, 2
                kvar ld_expect_b, 1
                kvar ld_mask, 1
                kvar ld_byte, 1
                kvar ld_index, 2
                kvar ld_bptr, 2
