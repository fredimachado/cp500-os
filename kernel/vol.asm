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
                pop hl
                pop af
                jp syscall

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
                jp SEV_DISK

bh_disk:
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
