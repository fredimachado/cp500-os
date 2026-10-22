; Mount table and volume binding for /sys/dev.

VOL_RECS        equ 1 + PT_SLOTS
VOL_ID_SIZE     equ 6
VW_SIZE         equ VOL_SIZE + VOL_ID_SIZE
                assert vol_dirty == vol_sb + 1 && vol_kstart == vol_sb + 2 && vol_kcount == vol_sb + 4
                assert vol_kcount + 2 == clk_base
                assert VW_SIZE == VOL_SIZE + (clk_base - vol_sb)
VOL_WIN         equ KPAGE_DEV
VOL_BASE        equ VOL_WIN + VOL_RECS * VW_SIZE
OF_VOL          equ VOL_BASE + VOL_RECS * 3
                assert OF_VOL == VOL_BASE + VOL_RECS * 3
VOL_CUR         equ OF_VOL + OFILE_SLOTS
VOL_END         equ VOL_CUR + 1
                assert VOL_END <= KPAGE_SNAP && VOL_END == KPAGE_SNAP
                assert (VOL_WIN >> 8) == ((VOL_END - 1) >> 8)
                assert (OFILE & 0FFh) == 0 && OF_STRIDE == 8
VOL_WR_MAX      equ 2048

; A = record. Keeps A. Destroys BC, DE, HL, F.
vol_bind:
                ld hl, VOL_CUR
                cp (hl)
                ret z
                push af
                ld a, (hl)
                call vb_save
                pop af
                push af
                call vb_load
                pop af
                ld (VOL_CUR), a
                ret

vb_save:
                call vb_off
                ex de, hl
                ld hl, VOL
                ld bc, VOL_SIZE
                ldir
                ld hl, vol_sb
                ld bc, VOL_ID_SIZE
                ldir
                ret

vb_load:
                call vb_off
                ld de, VOL
                ld bc, VOL_SIZE
                ldir
                ld de, vol_sb
                ld bc, VOL_ID_SIZE
                ldir
                ret

vb_off:
                ld l, a
                ld h, 0
                add hl, hl
                add hl, hl
                add hl, hl
                add hl, hl
                ld de, VOL_WIN
                add hl, de
                ret

; A = record. HL = VOL_BASE + 3*A. Destroys DE, F.
base_at:
                ld l, a
                ld h, 0
                ld e, a
                ld d, 0
                add hl, hl
                add hl, de
                ld de, VOL_BASE
                add hl, de
                ret

vol_gate:
                push af
                push hl
                ld a, 1
                ld (KBUSY), a
                ld hl, VOL_CUR
                ld a, (hl)
                or a
                jr z, vg_go
                push bc
                push de
                xor a
                call vol_bind
                pop de
                pop bc
vg_go:
                ld a, c
                cp SYS_SPAWN
                jr z, vg_spawn
                cp SYS_KILL
                jr nz, vg_run
                ; Kill guard: init's children (shell, rc) are not killable. Slots 1-7 only.
                ld a, e
                dec a
                cp TASK_SLOTS - 1
                jr nc, vg_run
                add a, (T_STATE + 1) & 0FFh
                ld l, a
                ld h, T_STATE >> 8
                ld a, (hl)
                or a
                jr z, vg_run
                ld a, l
                add a, T_PARENT - T_STATE
                ld l, a
                ld a, (hl)
                or a
                jr nz, vg_run
                ld c, SYS_DENIED
vg_run:
                pop hl
                pop af
                jp syscall

; Names the slot spawn will take, the lowest free one, after the basename of
; the path: up to 7 characters, ending at '.'. Keeps BC, DE, HL.
vg_spawn:
                push bc
                push de
                push hl
                ld hl, T_STATE + 1
                ld b, TASK_SLOTS - 1
vgs_find:
                ld a, (hl)
                or a
                jr z, vgs_name
                inc l
                djnz vgs_find
                jr vgs_out
vgs_name:
                ld a, l
                sub T_STATE & 0FFh
                add a, a
                add a, a
                add a, a
                add a, TASK_NAMES & 0FFh
                ld c, a
                ld b, TASK_NAMES >> 8
                ld h, d
                ld l, e
vgs_scan:
                ld a, (hl)
                inc hl
                or a
                jr z, vgs_copy
                cp '/'
                jr nz, vgs_scan
                ld d, h
                ld e, l
                jr vgs_scan
vgs_copy:
                ld h, b
                ld l, c
                ld b, TASK_NAME_LEN - 1
vgs_char:
                ld a, (de)
                or a
                jr z, vgs_pad
                cp '.'
                jr z, vgs_pad
                ld (hl), a
                inc hl
                inc de
                djnz vgs_char
vgs_pad:
                inc b
vgs_zero:
                ld (hl), 0
                inc hl
                djnz vgs_zero
vgs_out:
                pop hl
                pop de
                pop bc
                jr vg_run

vol_inode:
                push af
                push hl
                ld de, OFILE
                or a
                sbc hl, de
                ld a, l
                srl a
                srl a
                srl a
                ld l, a
                ld h, 0
                ld de, OF_VOL
                add hl, de
                ld a, (hl)
                pop hl
                push hl
                call vol_bind
                pop hl
                pop af
                ret

vol_route:
                call FD_ROUTE
                jr c, vr_std
                push de
                jr vr_stamp
vr_std:
                push de
                ld hl, vr_mnt
vr_cmp:
                ld a, (de)
                cp (hl)
                jr nz, vr_plain
                inc hl
                inc de
                ld a, (hl)
                or a
                jr nz, vr_cmp
                ld a, (de)
                cp '1'
                jr c, vr_plain
                cp '0' + PT_SLOTS + 1
                jp nc, vr_plain
                jp z, vr_plain
                sub '0'
                push de
                call vol_mount
                pop de
                jr c, vr_mfail
                inc de
                ld a, (de)
                cp '/'
                jr z, vr_mpath
                or a
                jr nz, vr_plain
                ld de, vr_root
                jr vr_setpath
vr_mpath:
                ld (io_path), de
                jr vr_stamp
vr_setpath:
                ld (io_path), de
                jr vr_stamp
vr_plain:
                pop de
                push de
vr_stamp:
                ld b, OFILE_SLOTS
                xor a
vr_of:
                push af
                call ofile_of
                ld a, (hl)
                or a
                jr nz, vr_on
                pop af
                push af
                ld e, a
                ld d, 0
                ld hl, OF_VOL
                add hl, de
                push hl
                ld hl, VOL_CUR
                ld a, (hl)
                pop hl
                ld (hl), a
                pop af
                jr vr_nxt
vr_on:
                pop af
vr_nxt:
                inc a
                cp b
                jr c, vr_of
                pop bc
                ld de, (io_path)
                ret
vr_mfail:
                pop bc
                jp dev_err

vr_mnt:         db "/mnt/hd0p", 0
vr_root:        db "/", 0

vol_mount:
                push af
                add a, FD_DRV & 0FFh
                ld l, a
                ld h, FD_DRV >> 8
                ld (hl), 0
                pop af
                ld (vm_slot), a
                call hd_probe
                ret c
                ld a, (vm_slot)
                call vol_bind
                ld hl, (VOL_BLOCKS)
                ld a, h
                or l
                ret nz
                ld a, (vm_slot)
                call hd_part
                jr c, vm_fail
                call c5fs_pick
                jr nc, vm_geom
                ld a, EIO
                jr vm_fail
vm_geom:
                ld a, (BLK_BUF + SB_SIDES)
                or a
                jp nz, vm_eio
                ld a, (BLK_BUF + SB_TRACKS)
                or a
                jp nz, vm_eio
                ld a, (BLK_BUF + SB_SPT)
                or a
                jp nz, vm_eio
                ld hl, (BLK_BUF + 16)
                ld de, (VOL_BLOCKS)
                or a
                sbc hl, de
                jp nz, vm_eio
                ld hl, (BLK_BUF + 20)
                ld a, l
                cp 1
                jp nz, vm_eio
                ld hl, (VOL_BLOCKS)
                ld de, VOL_WR_MAX + 1
                or a
                sbc hl, de
                jr nc, vm_eio
                call c5fs_layout
                ret nc
vm_eio:
                ld a, EIO
vm_fail:
                push af
                xor a
                ld (VOL_BLOCKS), a
                ld (VOL_BLOCKS + 1), a
                xor a
                call vol_bind
                pop af
                scf
                ret

vm_slot:        db 0

blk_hook:
                push af
                push de
                push hl
                ld hl, VOL_CUR
                ld a, (hl)
                or a
                jr nz, bh_disk
                ld a, DISK_DRIVE0 | DISK_MFM
                jr bh_sel

bh_disk:
                ld a, (VOL_CUR)
                add a, FD_DRV & 0FFh
                ld l, a
                ld h, FD_DRV >> 8
                ld a, (hl)
                or a
                jr z, bh_hd
                or DISK_MFM
; A = drive select. The FDC has one track register for all drives, so a drive
; change saves it for the old drive and loads the new drive's. A drive never
; used yet is restored to track 0 first.
bh_sel:
                ld hl, bh_last
                cp (hl)
                jr z, bh_go
                ld e, (hl)
                ld (hl), a
                ld d, a
                ld a, e
                and 0Fh
                ld e, a
                push de
                ld d, 0
                ld hl, bh_trk
                add hl, de
                in a, (FDC_TRACK)
                ld (hl), a
                pop af
                push af
                and 0Fh
                ld e, a
                ld hl, bh_trk
                add hl, de
                ld a, (hl)
                inc a
                jr nz, bh_known
                pop af
                push af
                out (PORT_DISK), a
                ld a, FDC_CMD_RESTORE | FDC_HEAD_LOAD | FDC_STEP_30MS
                out (FDC_COMMAND), a
                ld de, 0
bh_rest:
                in a, (FDC_STATUS)
                and FDC_BUSY
                jr z, bh_rested
                dec de
                ld a, d
                or e
                jr nz, bh_rest
bh_rested:
                inc a
bh_known:
                dec a
                out (FDC_TRACK), a
                pop af
bh_go:
                ld (fr_sel + 1), a
                jp SEV_DISK

bh_last:        db DISK_DRIVE0 | DISK_MFM
bh_trk:         db 0, 0FFh, 0FFh, 0, 0FFh, 0, 0, 0, 0FFh
bh_hd:
                ld hl, (VOL_BLOCKS)
                or a
                sbc hl, de
                jr c, bh_eio
                jr z, bh_eio
                push de
                ld a, (VOL_CUR)
                call base_at
                ld c, (hl)
                inc hl
                ld b, (hl)
                inc hl
                ld a, (hl)
                ld h, a
                pop de
                ld a, c
                add a, e
                ld c, a
                ld a, b
                adc a, d
                ld b, a
                ld a, h
                adc a, 0
                jr c, bh_eio
                ld (hd_lba + 2), a
                ld a, c
                ld (hd_lba), a
                ld a, b
                ld (hd_lba + 1), a
                pop hl
                pop de
                pop af
                pop bc
                push de
                push hl
                cp FDC_CMD_WRITE
                ld a, HD_CMD_READ
                jr nz, bh_rd
                ld a, HD_CMD_WRITE
bh_rd:
                call hd_xfer
                pop hl
                pop de
                jr c, bh_eio_a
                ei
                xor a
                ret
bh_eio:
                pop hl
                pop de
                pop af
                pop bc
bh_eio_a:
                ld a, EIO
                scf
                ei
                ret
