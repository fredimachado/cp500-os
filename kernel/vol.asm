; Mount table and volume binding for /sys/dev.

VOL_RECS        equ 1 + PT_SLOTS
VW_SIZE         equ VOL_SIZE + 6
                assert vol_dirty == vol_sb + 1 && vol_kstart == vol_sb + 2 && vol_kcount == vol_sb + 4
VOL_WIN         equ KPAGE_DEV
VOL_BASE        equ VOL_WIN + VOL_RECS * VW_SIZE
OF_VOL          equ VOL_BASE + VOL_RECS * 3
VOL_CUR         equ OF_VOL + OFILE_SLOTS
VOL_END         equ VOL_CUR + 1
                assert VOL_END <= KPAGE_SNAP && (VOL_WIN >> 8) == ((VOL_END - 1) >> 8)
                assert (OFILE & 0FFh) == 0 && OF_STRIDE == 8
VOL_WR_MAX      equ 2048

; A = record. Keeps A. Destroys BC, DE, HL, F.
vol_bind:
                ld hl, VOL_CUR
                ld b, a
                ld a, (hl)
                cp b
                ret z
                push bc
                push de
                push hl
                ld a, (hl)
                call vb_save
                ld a, b
                call vb_load
                ld hl, VOL_CUR
                ld (hl), b
                pop hl
                pop de
                pop bc
                ret

vb_save:
                call vb_off
                push hl
                ld hl, VOL
                pop de
                ld bc, VW_SIZE
                ldir
                ret

vb_load:
                call vb_off
                ld de, VOL
                ld bc, VW_SIZE
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
                jr nz, vr_done
                inc hl
                inc de
                ld a, (hl)
                or a
                jr nz, vr_cmp
                ld a, (de)
                cp '1'
                jr c, vr_done
                cp '0' + PT_SLOTS + 1
                jp nc, vr_done
                jp z, vr_done
                sub '0'
                push de
                call vol_mount
                pop de
                jr c, vr_mfail
                ld a, (open_flags)
                and O_WRITE | O_CREATE | O_TRUNC | O_APPEND
                jr z, vr_path
                ld hl, (VOL_BLOCKS)
                ld de, VOL_WR_MAX + 1
                or a
                sbc hl, de
                jr c, vr_path
                ld a, EROFS
                jr vr_mfail
vr_path:
                inc de
                ld a, (de)
                cp '/'
                jr z, vr_strip
                or a
                jr nz, vr_done
                ld de, vr_root
                jr vr_stamp
vr_strip:
                inc de
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
                pop hl
                ret
vr_mfail:
                pop hl
                jp dev_err
vr_done:
                pop de
                ret

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
                ret c
                call c5fs_pick
                ret c
                ld a, (BLK_BUF + SB_SIDES)
                or a
                jp nz, vm_fail
                ld a, (BLK_BUF + SB_TRACKS)
                or a
                jp nz, vm_fail
                ld a, (BLK_BUF + SB_SPT)
                or a
                jp nz, vm_fail
                ld hl, (BLK_BUF + 16)
                ld de, (vm_count)
                or a
                sbc hl, de
                jp nz, vm_fail
                ld hl, (BLK_BUF + 20)
                ld a, l
                cp 1
                jp nz, vm_fail
                ld hl, (vm_count)
                ld de, VOL_WR_MAX + 1
                or a
                sbc hl, de
                jr c, vm_layout
vm_fail:
                xor a
                call vol_bind
                ld a, EIO
                scf
                ret
vm_layout:
                call c5fs_layout
                ret nc
                jr vm_fail

vm_count:       dw 0
vm_slot:        db 0

blk_hook:
                push af
                push de
                push hl
                ld hl, VOL_CUR
                ld a, (hl)
                or a
                jr nz, bh_disk
                jp ser_disk

bh_disk:
                pop hl
                pop de
                pop af
                pop bc
                push hl
                push de
                ld hl, (VOL_BLOCKS)
                ld a, h
                or l
                jp z, bh_eio0
                or a
                sbc hl, de
                jr c, bh_eio0
                jp z, bh_eio0
                pop de
                pop hl
                push hl
                push de
                push af
                ld hl, VOL_CUR
                ld a, (hl)
                ld l, a
                ld h, 0
                add hl, hl
                add hl, hl
                add hl, hl
                ld bc, VOL_BASE
                add hl, bc
                ld c, (hl)
                inc hl
                ld b, (hl)
                inc hl
                ld a, (hl)
                ld h, a
                pop af
                pop de
                pop hl
                push hl
                push af
                ld a, h
                push af
                ld hl, bc
                add hl, de
                ld c, l
                ld b, h
                pop af
                adc a, 0
                jp nc, bh_lba
                inc a
                jp nz, bh_eio1
bh_lba:
                ld a, c
                ld (hd_lba), a
                ld a, b
                ld (hd_lba + 1), a
                pop af
                ld (hd_lba + 2), a
                pop af
                cp FDC_CMD_WRITE
                ld a, HD_CMD_READ
                jr nz, bh_rd
                ld a, HD_CMD_WRITE
bh_rd:
                pop hl
                call hd_xfer
                jr c, bh_eio1
                pop de
                pop hl
                ei
                xor a
                ret
bh_eio0:
                pop de
                pop hl
                jr bh_eio
bh_eio1:
                pop af
                pop hl
                pop de
bh_eio:
                ld a, EIO
                scf
                ei
                ret
