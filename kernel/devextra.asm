; Extra devices. Lives between the fixed jumps at EXT_OPEN and the syscall block.

DR_READ             equ 4
DR_WRITE            equ 6
DR_REVENTS          equ 12

ext_open:
                ld hl, (io_path)
                ld de, dev_pfx
                call pfx
                scf
                ret nz
                ld de, dev_tab
eo_tab:
                ld a, (de)
                or a
                scf
                ret z
                push hl
eo_cmp:
                ld a, (de)
                or a
                jr z, eo_hit
                cp (hl)
                jr nz, eo_skip
                inc hl
                inc de
                jr eo_cmp
eo_hit:
                ld a, (hl)
                or a
                jr nz, eo_skip
                inc de
                ld a, (de)
                ld b, a
                pop hl
                ld a, (open_flags)
                and O_CREATE | O_TRUNC | O_APPEND | O_EXCL
                jp nz, DEV_V_EINVAL
                ld a, b
                cp 1
                jp z, open_null
                cp 7
                jp z, open_prn
                cp 6
                jp z, open_fd
                jp open_con
eo_skip:
                pop hl
eo_adv:
                ld a, (de)
                inc de
                or a
                jr nz, eo_adv
                inc de
                jr eo_tab

open_null:
                ld a, KIND_NULL
                ld hl, 0
                jp open_stamp
open_prn:
                ld a, KIND_PRN
                ld hl, 0
                jp open_stamp
open_fd:
                inc hl
                inc hl
                ld a, (hl)
                sub '0'
                ld l, a
                ld h, 0
                ld a, KIND_FD0
                add a, l
                jp open_stamp
open_con:
                cp 3
                jr z, oc_0
                cp 4
                jr z, oc_1
                cp 5
                jr z, oc_tty
                ld hl, TASK + TASK_FD
                ld a, (hl)
                call ofile_of
                inc hl
                inc hl
                ld l, (hl)
                ld h, 0
                jr oc_kind
oc_0:
                ld hl, 0
                jr oc_kind
oc_1:
                ld hl, 1
                jr oc_kind
oc_tty:
                ld a, (CON_ACTIVE)
                ld l, a
                ld h, 0
oc_kind:
                ld a, KIND_CON
open_stamp:
                ld (open_kind), a
                ld (open_ino), hl
                call fd_alloc
                jp c, DEV_V_ERR
                jp DEV_V_OK

ext_go:
                ld c, a
                ld a, e
                cp DR_READ
                jr z, eg_read
                cp DR_WRITE
                jr z, eg_write
                cp DR_REVENTS
                jr z, eg_rev
                ld hl, 0
                jp DEV_V_OK
eg_rev:
                ld a, c
                cp KIND_NULL - KIND_DEV
                jr z, eg_out
                cp KIND_PRN - KIND_DEV
                jr z, eg_prn_rev
                ld a, POLLIN | POLLOUT
                ret
eg_out:
                ld a, POLLOUT
                ret
eg_prn_rev:
                in a, (PORT_PRINTER)
                and PRN_BUSY
                ld a, 0
                ret nz
                ld a, POLLOUT
                ret
eg_read:
                ld a, c
                cp KIND_NULL - KIND_DEV
                jr z, eg_z
                cp KIND_CON - KIND_DEV
                jr z, eg_con_r
                cp KIND_PRN - KIND_DEV
                jr z, eg_prn_r
                cp KIND_FD0 - KIND_DEV
                jp c, DEV_V_EINVAL
                cp KIND_FD3 - KIND_DEV + 1
                jp nc, DEV_V_EINVAL
                ld a, FDC_CMD_READ
                jp fd_xfer
eg_write:
                ld a, c
                cp KIND_NULL - KIND_DEV
                jr z, eg_wr0
                cp KIND_CON - KIND_DEV
                jr z, eg_con_w
                cp KIND_PRN - KIND_DEV
                jr z, eg_prn_w
                cp KIND_FD0 - KIND_DEV
                jp c, DEV_V_EINVAL
                cp KIND_FD3 - KIND_DEV + 1
                jp nc, DEV_V_EINVAL
                ld a, FDC_CMD_WRITE
                jp fd_xfer
eg_z:
                ld hl, 0
                jp DEV_V_OK
eg_wr0:
                ld hl, (io_len)
                jp DEV_V_OK
eg_con_r:
                call frame_ofile
                jp c, DEV_V_ERR
                jp read_con
eg_con_w:
                call frame_ofile
                jp c, DEV_V_ERR
                jp write_con
eg_prn_r:
                in a, (PORT_PRINTER)
                and PRN_BUSY
                ld a, 0
                jr nz, prn_byte
                ld a, 0FFh
prn_byte:
                ld hl, (io_buf)
                ld (hl), a
                ld hl, 1
                jp DEV_V_OK
eg_prn_w:
                ld hl, (io_buf)
                ld bc, (io_len)
pw_loop:
                ld a, b
                or c
                jr z, pw_done
pw_wait:
                in a, (PORT_PRINTER)
                and PRN_BUSY
                jr nz, pw_wait
                ld a, (hl)
                out (PORT_PRINTER), a
                inc hl
                dec bc
                jr pw_loop
pw_done:
                ld hl, (io_len)
                jp DEV_V_OK

frame_ofile:
                ld ix, (SC_FRAME)
                ld a, (ix + F_DE)
                ld e, a
                call fd_get
                ret

fd_xfer:
                push af
                call frame_ofile
                jp c, fx_bad
                push hl
                ld de, OF_INO
                add hl, de
                ld c, (hl)
                pop hl
                ld de, OF_POS
                add hl, de
                ld e, (hl)
                inc hl
                ld d, (hl)
                ld l, c
                ld h, 0
                ld de, fx_mask
                add hl, de
                ld a, (hl)
                or DISK_MFM
                ld (fr_sel + 1), a
                ld hl, (io_buf)
                pop af
                cp FDC_CMD_WRITE
                jr z, fx_wr
                call floppy_read
                jr fx_stat
fx_wr:
                call floppy_write
fx_stat:
                push af
                ld a, DISK_DRIVE0 | DISK_MFM
                ld (fr_sel + 1), a
                pop af
                jp c, fx_err
                ld hl, 256
                jp DEV_V_OK
fx_bad:
                pop af
                jp DEV_V_ERR
fx_err:
                in a, (FDC_STATUS)
                bit FDC_NOT_READY_BIT, a
                ld a, EIO
                jp z, DEV_V_ERR
                ld a, ENODEV
                jp DEV_V_ERR

fx_mask:        db DISK_DRIVE0, DISK_DRIVE1, DISK_DRIVE2, DISK_DRIVE3

dev_seek:
                ld (io_buf), hl
                ld a, b
                ld (seek_whence), a
                call fd_get
                jp c, syscall_err
                cp KIND_FILE
                jp z, seek_file
                cp KIND_FD0
                jp c, sc_einval
                cp KIND_FD3 + 1
                jp nc, sc_einval
                ld a, (seek_whence)
                or a
                jp nz, sc_einval
                ld de, OF_POS
                add hl, de
                ex de, hl
                ld hl, (io_buf)
                ld bc, 4
                ldir
                ld hl, 0
                jp syscall_ok

dev_boot:
                ld hl, CON_WANT
                ld a, (hl)
                ld (rc_want), a
                ld (hl), 0
                ld a, 1
                ld (RC_BOOT), a
                ei
                ld c, SYS_SPAWN
                ld de, rc_path
                ld hl, rc_argv
                ld ix, 0
                rst 08h
                jr c, boot_back
                ld a, l
boot_spin:
                halt
                add a, T_STATE & 0FFh
                ld l, a
                ld h, T_STATE >> 8
                ld a, (hl)
                or a
                jr z, boot_back
                ld a, l
                sub T_STATE & 0FFh
                jr boot_spin
boot_back:
                ld a, (rc_want)
                ld (CON_WANT), a
                xor a
                ld (RC_BOOT), a
                call tmp_clear
                jp init_task_cont

tmp_clear:
                ld de, tmp_path
                ld c, SYS_MKDIR
                rst 08h
                ld de, tmp_path
                ld b, O_READ
                ld c, SYS_OPEN
                rst 08h
                ret c
                ld a, l
                ld (tmp_fd), a
tc_next:
                ld e, a
                ld d, 0
                ld hl, tmp_ent
                ld c, SYS_READDIR
                rst 08h
                jr c, tc_close
                ld a, h
                or l
                jr z, tc_close
                ld hl, tmp_ent + 2
                ld a, (hl)
                or a
                jr z, tc_more
                cp '.'
                jr nz, tc_del
                inc hl
                ld a, (hl)
                or a
                jr z, tc_more
                cp '.'
                jr nz, tc_del
                inc hl
                ld a, (hl)
                or a
                jr z, tc_more
tc_del:
                ld hl, tmp_ent + 2
                ld de, tmp_full + 5
                ld bc, 30
                ldir
                xor a
                ld (de), a
                ld de, tmp_full
                ld c, SYS_REMOVE
                rst 08h
tc_more:
                ld a, (tmp_fd)
                jr tc_next
tc_close:
                ld a, (tmp_fd)
                ld e, a
                ld d, 0
                ld c, SYS_CLOSE
                rst 08h
                ret

fd_route:
                push de
                ld h, d
                ld l, e
                ld de, fd_pfx
                call pfx
                pop de
                scf
                ret nz
                ld a, (hl)
                cp '1'
                ret c
                cp '4'
                jr c, fdr_dig
                scf
                ret
fdr_dig:
                sub '0'
                ld c, a
                ld b, a
                push hl
                push bc
                call fd_probe
                pop bc
                jp c, DEV_V_ERR
                push bc
                call c5fs_pick
                call nc, c5fs_layout
                pop bc
                jr nc, fdr_on
                call fd_forget
                ld a, EIO
                jp DEV_V_ERR
fdr_on:
                ld l, c
                ld h, 0
                ld de, fx_mask
                add hl, de
                ld a, (hl)
                ld e, b
                ld d, 0
                ld hl, FD_DRV
                add hl, de
                ld (hl), a
                pop hl
                inc hl
                ld a, (hl)
                cp '/'
                jr nz, fdr_root
                ex de, hl
                jr fdr_set
fdr_root:
                or a
                ld a, EINVAL
                jp nz, DEV_V_ERR
                ld de, fd_root
fdr_set:
                ld (io_path), de
                xor a
                ret

fd_probe:
                push bc
                ld l, c
                ld h, 0
                ld de, fx_mask
                add hl, de
                ld a, (hl)
                ld e, c
                ld d, 0
                ld hl, FD_DRV
                add hl, de
                ld (hl), a
                ld a, (VOL_SPT)
                ld (geo_save), a
                ld a, (VOL_SIDES)
                ld (geo_save + 1), a
                ld a, c
                call VB_ENT
                ld a, (geo_save)
                ld (VOL_SPT), a
                ld a, (geo_save + 1)
                ld (VOL_SIDES), a
                ld de, 0
                ld hl, BLK_BUF
                call floppy_read
                pop bc
                push af
                ld a, DISK_DRIVE0 | DISK_MFM
                ld (fr_sel + 1), a
                pop af
                ret nc
                call fd_forget
                in a, (FDC_STATUS)
                bit FDC_NOT_READY_BIT, a
                ld a, EIO
                ret z
                ld a, ENODEV
                scf
                ret

; C = drive. Forgets its mount and binds the root volume again.
fd_forget:
                ld l, c
                ld h, 0
                ld de, FD_DRV
                add hl, de
                ld (hl), 0
                xor a
                jp VB_ENT

pfx:
                ld a, (de)
                or a
                ret z
                cp (hl)
                ret nz
                inc hl
                inc de
                jr pfx

; BC = request, DE = IX, HL = CON_FG for this console.
sc_hist:
                ld a, l
                sub CON_FG & 0FFh
                ld (ci_con), a
                ld a, c
                cp 5
                jr z, ci_gethist
                cp 6
                jp nz, sc_einval
                jr ci_puthist
ci_gethist:
                ld a, (de)
                ld b, a
                inc de
                push de
                call ci_hist_ptr
                ld a, b
                call ci_hist_line
                pop de
                jr nc, ci_get_copy
                xor a
                ld (de), a
                jr ci_hist_ok
ci_get_copy:
                ld bc, HIST_LINE - 1
                ldir
ci_hist_ok:
                ld hl, 0
                jp syscall_ok
ci_puthist:
                push de
                call ci_hist_ptr
                pop de
                ex de, hl
                call ci_hist_push
                jr ci_hist_ok
ci_hist_ptr:
                ld a, (ci_con)
                or a
                ld hl, CON_HIST
                ret z
                ld de, HIST_CON_SIZE
                add hl, de
                ret
; HL = meta, A = slot 0 newest. Carry if bad. Out HL = line.
ci_hist_line:
                ld b, a
                ld a, (hl)
                ld c, a
                inc hl
                ld a, b
                cp (hl)
                jr nc, ci_slot_bad
                dec hl
                ld a, c
                dec a
                sub b
                and HIST_LINES - 1
                call ci_line_at
                or a
                ret
ci_slot_bad:
                scf
                ret
; HL = line, DE = meta.
ci_hist_push:
                ld a, (hl)
                or a
                ret z
                push de
                push hl
                pop de
                pop hl
                push hl
                push de
                ld a, (hl)
                call ci_line_at
                ld de, hl
                pop hl
ci_push_cp:
                ld a, (hl)
                ld (de), a
                or a
                jr z, ci_push_done
                inc hl
                inc de
                jr ci_push_cp
ci_push_done:
                pop hl
                ld a, (hl)
                inc a
                and HIST_LINES - 1
                ld (hl), a
                inc hl
                ld a, (hl)
                cp HIST_LINES
                ret z
                inc a
                ld (hl), a
                ret
; DE = meta, A = index. Out HL = line.
ci_line_at:
                ld b, a
                ld de, HIST_META
                add hl, de
                ld de, HIST_LINE
                ld a, b
                or a
ci_lat:
                ret z
                add hl, de
                dec a
                jr ci_lat

ci_con:         db 0

dev_pfx:        db "/dev/", 0
dev_tab:
                db "null", 0, 1
                db "con", 0, 2
                db "con0", 0, 3
                db "con1", 0, 4
                db "tty", 0, 5
                db "fd0", 0, 6
                db "fd1", 0, 6
                db "fd2", 0, 6
                db "fd3", 0, 6
                db "prn", 0, 7
                db 0
fd_pfx:         db "/mnt/fd", 0
fd_root:        db "/", 0
rc_path:        db "/etc/rc", 0
rc_argv:        db 0, 0
rc_want:        db 0
tmp_path:       db "/tmp", 0
tmp_full:       db "/tmp/"
                ds 24, 0
tmp_fd:         db 0
tmp_ent:        ds 16, 0
geo_save:       ds 2, 0
