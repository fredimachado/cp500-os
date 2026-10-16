; System page jumps. The ROM enters here with interrupts still disabled.

sys_init:
                ld a, 0C3h
                ld (SYS_RST08), a
                ld hl, syscall
                ld (SYS_RST08 + 1), hl
                ld a, 0C9h
                ld (SYS_RST10), a
                ld (SYS_RST18), a
                ld (SYS_RST20), a
                ld (SYS_RST28), a
                ld (SYS_RST30), a
                ld a, 0C3h
                ld (SYS_ISR), a
                ld hl, isr
                ld (SYS_ISR + 1), hl
                ld (SYS_NMI), a
                ld hl, nmi
                ld (SYS_NMI + 1), hl

                ld hl, TICK_COUNT
                ld (hl), 0
                ld de, TICK_COUNT + 1
                ld bc, 4048h - TICK_COUNT
                ldir
                ld hl, KBD_ACCEPTED
                ld (hl), 0
                ld de, KBD_ACCEPTED + 1
                ld bc, BLINK_DIV - KBD_ACCEPTED
                ldir
                ld a, 0FFh
                ld (KBD_REP_ROW), a

                call console_init
                in a, (PORT_TIMER_ACK)
                xor a
                out (PORT_NMI), a
                ld a, IRQ_TIMER
                out (PORT_IRQ), a
                ret

nmi:
                retn

syscall:
                ld (SC_IX), ix
                ld (SC_IY), iy
                ex af, af'
                push af
                exx
                push bc
                push de
                push hl
                exx
                ex af, af'
                ld a, c
                cp SYS_GETCWD + 1
                jr nc, sc_einval
                ld (sc_hl), hl
                ld (sc_de), de
                ld hl, sc_table
                ld e, a
                ld d, 0
                add hl, de
                add hl, de
                ld e, (hl)
                inc hl
                ld d, (hl)
                push de
                ld hl, (sc_hl)
                ld de, (sc_de)
                ret

sc_einval:
                ld a, EINVAL
syscall_err:
                ld hl, 0
                scf
syscall_exit:
                exx
                pop hl
                pop de
                pop bc
                exx
                ex af, af'
                pop af
                ex af, af'
                ld ix, (SC_IX)
                ld iy, (SC_IY)
                ret

syscall_ok:
                xor a
                jr syscall_exit

sc_table:
                dw sys_exit, sys_spawn, sys_wait, sys_getpid
                dw sc_einval, sc_einval, sc_einval, sc_einval
                dw sc_einval, sc_einval, sc_einval, sc_einval
                dw sc_einval, sc_einval, sc_einval, sc_einval
                dw sc_einval, sc_einval, sc_einval, sc_einval
                dw sc_einval, sc_einval, sc_einval, sc_einval
                dw sc_einval, sc_einval, sc_einval, sc_einval
                dw sc_einval, sc_einval, sc_einval, sc_einval
                dw sys_open, sys_close, sys_read, sys_write
                dw sys_seek, sys_stat, sys_fstat, sys_readdir
                dw sys_mkdir, sys_remove, sys_rename, sys_chdir
                dw sys_getcwd
                assert $ - sc_table == 45 * 2

sys_getpid:
                ld a, (TASK + TASK_ID)
                ld l, a
                ld h, 0
                jp syscall_ok

sys_exit:
                ld a, (TASK + TASK_ID)
                cp 2
                jp z, exit_child
                ld a, (CHILD_STATE)
                cp CH_PENDING
                jr nz, exit_halt
                ld hl, CHILD_FD
                call drop_fds
                call free_child
exit_halt:
                di
                halt
                jr exit_halt

exit_child:
                ld a, e
                ld (exit_code), a
                call drop_task_fds
                call free_child
                ld hl, SHELL_SAVE
                ld de, TASK
                ld bc, 16
                ldir
                ld hl, (TASK + TASK_SP)
                ld sp, hl
                ld a, (exit_code)
                ld l, a
                ld h, 2
                xor a
                jp syscall_exit

free_child:
                ld a, (CHILD_BASE)
                ld (ARENA_NEXT), a
                xor a
                ld (CHILD_STATE), a
                ret

drop_task_fds:
                ld hl, TASK + TASK_FD
drop_fds:
                ld b, FD_SLOTS
drop_fd:
                ld a, (hl)
                cp 0FFh
                jr z, drop_fd_next
                push hl
                push bc
                call ofile_of
                inc hl
                dec (hl)
                jr nz, drop_fd_keep
                dec hl
                ld (hl), KIND_FREE
drop_fd_keep:
                pop bc
                pop hl
drop_fd_next:
                inc hl
                djnz drop_fd
                ret

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

sys_spawn:
                ld a, (CHILD_STATE)
                or a
                ld a, EBUSY
                jp nz, syscall_err
                ld (spawn_argv), hl
                ld (spawn_map), ix
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
                ld a, (ARENA_NEXT)
                ld hl, (spawn_argv)
                call load_c5x
                jp c, syscall_err
                ld (CHILD_ENTRY), hl
                ld a, (ARENA_NEXT)
                ld (CHILD_BASE), a
                add a, b
                ld (ARENA_NEXT), a
                ld a, b
                ld (CHILD_PAGES), a
                call map_apply
                ld a, CH_PENDING
                ld (CHILD_STATE), a
                ld hl, 2
                jp syscall_ok

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

map_apply:
                ld hl, CHILD_FD
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
                ld hl, CHILD_FD
                add hl, de
                ld (hl), a
                call ofile_of
                inc hl
                inc (hl)
                ret

sys_wait:
                ld a, (CHILD_STATE)
                cp CH_PENDING
                jr z, wait_id
                ld a, ECHILD
                jp syscall_err
wait_id:
                ld a, e
                cp 0FFh
                jr z, wait_go
                cp 2
                jr z, wait_go
                ld a, ECHILD
                jp syscall_err
wait_go:
                ld hl, TASK
                ld de, SHELL_SAVE
                ld bc, 16
                ldir
                ld hl, 0
                add hl, sp
                ld (SHELL_SAVE + TASK_SP), hl
                ld a, 2
                ld (TASK + TASK_ID), a
                ld a, (CHILD_BASE)
                ld (TASK + TASK_BASE), a
                ld a, (CHILD_PAGES)
                ld (TASK + TASK_PAGES), a
                xor a
                ld (TASK + TASK_SP), a
                ld (TASK + TASK_SP + 1), a
                ld (TASK + TASK_VOL), a
                ld hl, CHILD_FD
                ld de, TASK + TASK_FD
                ld bc, FD_SLOTS
                ldir
                ld hl, 1
                ld (TASK + TASK_CWD), hl
                ld a, CH_RUNNING
                ld (CHILD_STATE), a
                ld sp, (child_sp)
                ld hl, (CHILD_ENTRY)
                push hl
                ld hl, (child_argv)
                xor a
                ld bc, 0
                ld de, 0
                ld ix, 0
                ld iy, 0
                ei
                ret

sys_close:
                ld a, e
                cp FD_SLOTS
                jr c, close_slot
                ld a, EBADF
                jp syscall_err
close_slot:
                ld d, 0
                ld hl, TASK + TASK_FD
                add hl, de
                ld a, (hl)
                cp 0FFh
                jr z, close_ok
                ld (hl), 0FFh
                call ofile_of
                inc hl
                dec (hl)
                jr nz, close_ok
                dec hl
                ld (hl), KIND_FREE
close_ok:
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
                or a
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
                cp KIND_FILE
                jp z, read_file
                cp KIND_DIR
                jr nz, read_bad
                ld a, EISDIR
                jp syscall_err
read_bad:
                ld a, EBADF
                jp syscall_err

read_con:
                ld hl, (io_len)
                ld a, h
                or l
                jp z, syscall_ok
                ld hl, 0
                ld (io_got), hl
read_wait:
                call kbd_get
                jr c, read_store
                ei
                halt
                jr read_wait
read_store:
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
                jr z, read_done
                call kbd_get
                jr c, read_store
                jr read_wait
read_done:
                ld hl, (io_got)
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
                ld de, (io_pos)
                ld a, (de)
                add a, l
                ld (de), a
                inc de
                ld a, (de)
                adc a, h
                ld (de), a
                inc de
                ld a, (de)
                adc a, 0
                ld (de), a
                inc de
                ld a, (de)
                adc a, 0
                ld (de), a
                pop hl
                jp syscall_ok

sys_write:
                ld (io_buf), hl
                ld (io_len), ix
                call fd_get
                jp c, syscall_err
                cp KIND_CON_OUT
                jr z, write_con
                cp KIND_FILE
                jr z, write_ro
                cp KIND_DIR
                jr z, write_ro
                ld a, EBADF
                jp syscall_err
write_ro:
                ld a, EROFS
                jp syscall_err
write_con:
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
                call console_putc
                pop bc
                pop hl
                dec bc
                jr write_loop
write_done:
                ld hl, (io_len)
                jp syscall_ok

sys_seek:
                ld (io_buf), hl
                ld a, b
                ld (seek_whence), a
                call fd_get
                jp c, syscall_err
                cp KIND_FILE
                jr z, seek_file
                ld a, EINVAL
                jp syscall_err
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
                ld a, EINVAL
                jp syscall_err
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
                ld a, EINVAL
                jp syscall_err
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
                ld a, EINVAL
                jp syscall_err
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
                call c5fs_walk
                jr nc, mkdir_have
                cp ENOENT
                jp nz, syscall_err
                ld a, b
                cp 1
                jr nz, mkdir_miss
                ld a, EROFS
                jp syscall_err
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
                ld a, EROFS
                jp syscall_err

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
                ld de, (ren_old)
                call c5fs_walk
                jp c, syscall_err
                ld de, (ren_new)
                call c5fs_parent
                jp c, syscall_err
                ld a, EROFS
                jp syscall_err

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
                ld a, EINVAL
                jp syscall_err
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
                ld a, EINVAL
                jp syscall_err
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
                ld a, b
                ld (open_flags), a
                and 0C0h
                jr z, open_known
                ld a, EINVAL
                jp syscall_err
open_known:
                ld a, (open_flags)
                and 3Fh
                jr nz, open_excl
                ld a, EINVAL
                jp syscall_err
open_excl:
                ld a, (open_flags)
                and O_EXCL
                jr z, open_class
                ld a, (open_flags)
                and O_CREATE
                jr nz, open_class
                ld a, EINVAL
                jp syscall_err
open_class:
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
                call c5fs_walk
                jr nc, open_have
                cp ENOENT
                jp nz, syscall_err
                ld a, b
                cp 1
                jr nz, open_enoent
                ld a, (open_flags)
                and O_CREATE
                jr z, open_enoent
                ld a, EROFS
                jp syscall_err
open_enoent:
                ld a, ENOENT
                jp syscall_err
open_have:
                ld a, (open_flags)
                and O_CREATE | O_EXCL
                cp O_CREATE | O_EXCL
                jr nz, open_rofs
                ld a, EEXIST
                jp syscall_err
open_rofs:
                ld a, (INO_BUF + INO_TYPE)
                and 0Fh
                cp INO_KIND_DIR
                jr nz, open_file_ro
                ld a, EISDIR
                jp syscall_err
open_file_ro:
                ld a, EROFS
                jp syscall_err
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
                jp c, ld_exec
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

; Carry set when image + bss + stack + 192 exceeds the arena.
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
                or a
                scf
                ret nz
                ld de, ARENA_BYTES
                or a
                sbc hl, de
                jr c, ld_fit_ok
                ret z
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
                jr z, ld_exact_adv
                ld a, EIO
                scf
                ret
ld_exact_adv:
                ld hl, ld_pos
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
                ld a, h
                or l
                jr nz, ld_pages_up
                ld b, 0
                jr ld_entry
ld_pages_up:
                ld de, 255
                add hl, de
                ld b, h
ld_entry:
                ld a, (ld_page)
                add a, b
                jr nc, ld_entry_ok
                or a
                jr z, ld_entry_ok
                ld a, ENOMEM
                scf
                ret
ld_entry_ok:
                ld a, (ld_page)
                ld h, a
                ld l, 0
                ld de, (ld_hdr + 10)
                add hl, de
                xor a
                ret

become_shell:
                ld de, shell_path
                call c5fs_walk
                jr c, shell_halt
                ld a, (INO_BUF + INO_TYPE)
                and 0Fh
                cp INO_KIND_FILE
                jr nz, shell_halt
                ld a, ARENA_FIRST
                ld hl, empty_argv
                call load_c5x
                jr c, shell_halt
                ld (CHILD_ENTRY), hl
                ld a, 1
                ld (TASK + TASK_ID), a
                ld a, ARENA_FIRST
                ld (TASK + TASK_BASE), a
                ld a, b
                ld (TASK + TASK_PAGES), a
                add a, ARENA_FIRST
                ld (ARENA_NEXT), a
                xor a
                ld (TASK + TASK_SP), a
                ld (TASK + TASK_SP + 1), a
                ld (TASK + TASK_VOL), a
                ld (CHILD_STATE), a
                ld hl, 1
                ld (TASK + TASK_CWD), hl
                ld hl, shell_fds
                ld de, TASK + TASK_FD
                ld bc, FD_SLOTS
                ldir
                ld hl, CHILD_FD
                ld b, FD_SLOTS
shell_fd:
                ld (hl), 0FFh
                inc hl
                djnz shell_fd
                call shell_ofiles
                ld sp, (child_sp)
                ld hl, (CHILD_ENTRY)
                push hl
                ld hl, (child_argv)
                xor a
                ld bc, 0
                ld de, 0
                ld ix, 0
                ld iy, 0
                ei
                ret
shell_halt:
                di
                halt
                jr shell_halt

shell_ofiles:
                ld hl, OFILE
                ld de, OFILE + 1
                ld bc, OFILE_SLOTS * OF_STRIDE - 1
                ld (hl), 0
                ldir
                ld hl, OFILE
                ld (hl), KIND_CON_IN
                inc hl
                ld (hl), 1
                ld hl, OFILE + OF_STRIDE
                ld (hl), KIND_CON_OUT
                inc hl
                ld (hl), 1
                ld hl, OFILE + 2 * OF_STRIDE
                ld (hl), KIND_CON_OUT
                inc hl
                ld (hl), 1
                ret

shell_path:     db "/bin/sh", 0
empty_argv:     db 0, 0
shell_fds:      db 0, 1, 2, 0FFh, 0FFh, 0FFh, 0FFh, 0FFh

exit_code:      db 0
sc_hl:          dw 0
sc_de:          dw 0
spawn_argv:     dw 0
spawn_map:      dw 0
io_buf:         dw 0
io_len:         dw 0
io_got:         dw 0
io_pos:         dw 0
io_path:        dw 0
ren_old:        dw 0
ren_new:        dw 0
open_flags:     db 0
open_kind:      db 0
open_ino:       dw 0
seek_whence:    db 0
seek_base:      ds 4, 0
cwd_buf:        dw 0
cwd_size:       dw 0
cwd_need:       dw 0
cwd_pos:        dw 0
cwd_ino:        dw 0
cwd_parent:     dw 0
cwd_ent:        ds 32, 0
child_sp:       dw 0
child_argv:     dw 0
ld_page:        db 0
ld_argv:        dw 0
ld_argn:        db 0
ld_pos:         ds 4, 0
ld_hdr:         ds 16, 0
ld_bbytes:      dw 0
ld_expect_w:    dw 0
ld_expect_b:    db 0
ld_mask:        db 0
ld_byte:        db 0
ld_index:       dw 0
ld_bptr:        dw 0
