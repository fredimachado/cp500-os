; Resident writer, linked at WR_BASE. The kernel loads this file to that address.
; Bitmap, data, inode, then the directory entry. Delete reverses that.
; Added blocks are the lowest free run that holds all of them.
; write appends only when the file size is a multiple of 256.

                include "kernel.sym"

                org WR_BASE

                jp w_mkdir
                jp w_remove
                jp w_rename
                jp w_open
                jp w_write
                jp w_sync
                jp w_time
                jp w_settime

wr_blk          equ fs_dst
wr_slot         equ fs_len
wr_count        equ fs_got
div_n           equ mt_seq
div_q           equ mt_blocks

ok0:            ld hl, 0
                xor a
                ret

w_sync:         call wr_sync
                ret c
                jr ok0

w_time:         push de
                call time_calc
                pop de
                ld hl, div_q
                ld bc, 4
                ldir
                jr ok0

w_settime:      ld h, d
                ld l, e
                ld de, clk_base
                ld bc, 4
                ldir
                ld hl, TICK_COUNT
                ld de, clk_tick
                ld bc, 4
                ldir
                jr ok0

time_calc:      push ix
                ld ix, clk_tick
                ld hl, TICK_COUNT
                ld de, div_n
                ld b, 4
                or a
tc_sub:         ld a, (hl)
                sbc a, (ix + 0)
                ld (de), a
                inc hl
                inc de
                inc ix
                djnz tc_sub
                pop ix
                call div30
                ld hl, div_q
                ld de, clk_base
                ld b, 4
                or a
tc_add:         ld a, (de)
                adc a, (hl)
                ld (hl), a
                inc hl
                inc de
                djnz tc_add
                ret

div30:          ld hl, div_q
                xor a
                ld (hl), a
                inc hl
                ld (hl), a
                inc hl
                ld (hl), a
                inc hl
                ld (hl), a
                ld e, a
                ld b, 32
d30_bit:        ld hl, div_n
                or a
                rl (hl)
                inc hl
                rl (hl)
                inc hl
                rl (hl)
                inc hl
                rl (hl)
                ld a, e
                adc a, a
                ld e, a
                or a
                ld hl, div_q
                rl (hl)
                inc hl
                rl (hl)
                inc hl
                rl (hl)
                inc hl
                rl (hl)
                ld a, e
                cp 30
                jr c, d30_next
                sub 30
                ld e, a
                ld hl, div_q
                set 0, (hl)
d30_next:       djnz d30_bit
                ret

stamp:          ld de, INO_BUF + INO_MOD
                jr time_at

stamp_both:     call stamp
                ld hl, INO_BUF + INO_MOD
                ld de, INO_BUF + INO_CREATE
                ld bc, 4
                ldir
                ret

time_at:        push de
                call time_calc
                pop de
                ld hl, div_q
                ld bc, 4
                ldir
                ret

inc32:          inc (hl)
                ret nz
                inc hl
                inc (hl)
                ret nz
                inc hl
                inc (hl)
                ret nz
                inc hl
                inc (hl)
                ret

; A = 0 dirty (clear clean, bump generation once), 1 clean sync.
wr_super:       ld (wr_flag), a
                ld a, (vol_sb)
                ld e, a
                ld d, 0
                ld hl, BLK_BUF
                call floppy_read
                ret c
                ld hl, BLK_BUF + SB_FLAGS
                ld a, (wr_flag)
                or a
                ld a, (hl)
                jr nz, sup_set
                and 0FEh
                ld (hl), a
                ld a, (vol_dirty)
                or a
                jr nz, sup_seq
                ld hl, BLK_BUF + 14
                inc (hl)
                jr nz, sup_seq
                inc hl
                inc (hl)
                jr sup_seq
sup_set:        or 1
                ld (hl), a
sup_seq:        ld hl, BLK_BUF + SB_SEQ
                call inc32
                ld a, (wr_kflag)
                or a
                jr z, sup_time
                xor a
                ld h, a
                ld l, a
                ld (BLK_BUF + SB_KERNEL_START), hl
                ld (BLK_BUF + SB_KERNEL_COUNT), hl
                ld (vol_kstart), hl
                ld (vol_kcount), hl
                ld (wr_kflag), a
sup_time:       ld de, BLK_BUF + 38
                call time_at
                ld hl, BLK_BUF
                ld b, 254
                call fs_crc
                ld (BLK_BUF + SB_CRC), hl
                ld a, 3
                ld hl, vol_sb
                sub (hl)
                ld (vol_sb), a
                ld e, a
                ld d, 0
                ld a, (wr_flag)
                xor 1
                ld (vol_dirty), a
                ld hl, BLK_BUF
                jp floppy_write

wr_dirty:       ld a, (vol_dirty)
                or a
                jr z, dirt_go
                ld a, (wr_kflag)
                or a
                ret z
dirt_go:        xor a
                jp wr_super

wr_sync:        ld a, (vol_dirty)
                or a
                ret z
                ld a, 1
                jp wr_super

fail:           ld a, c
                scf
                ret

path_kernel:    push de
                ld hl, (io_path)
                ld de, pk_lit
pk_cmp:         ld a, (de)
                or a
                jr z, pk_end
                call walk_fold
                ld c, a
                ld a, (hl)
                call walk_fold
                cp c
                jr nz, pk_no
                inc hl
                inc de
                jr pk_cmp
pk_end:         ld a, (hl)
                or a
                jr nz, pk_no
                pop de
                scf
                ret
pk_no:          pop de
                or a
                ret

pk_lit:         db "/sys/kernel", 0

k_off:          xor a
                ld (wr_kflag), a
                ret

wr_ialloc:      ld bc, 1
ia_loop:        push bc
                ld hl, (VOL_ICOUNT)
                or a
                sbc hl, bc
                jr z, ia_full
                jr c, ia_full
                call c5fs_slot
                jr c, ia_full
                ld a, (INO_BUF)
                or a
                jr z, ia_got
                pop bc
                inc bc
                jr ia_loop
ia_got:         pop bc
                xor a
                ret
ia_full:        pop bc
                ld c, ENOSPC
                jr fail

bit_at:         push bc
                push de
                ld a, e
                and 7
                ld b, a
                ld a, 1
                jr z, bit_i
bit_s:          add a, a
                djnz bit_s
bit_i:          push af
                srl d
                rr e
                srl d
                rr e
                srl d
                rr e
                ld hl, BLK_BUF
                add hl, de
                pop af
                pop de
                pop bc
                ret

bit_free:       call bit_at
                and (hl)
                ret

bit_set:        call bit_at
                or (hl)
                ld (hl), a
                ret

bit_clr:        call bit_at
                cpl
                and (hl)
                ld (hl), a
                ret

bm_load:        ld de, 3
                ld hl, BLK_BUF
                jp floppy_read

bm_save:        ld de, 3
                ld hl, BLK_BUF
                jp floppy_write

; C = block count. Bitmap already loaded. One extent, or extend the last.
grow_run:       ld b, c
                ld de, (VOL_FIRST)
gr_scan:        ld hl, (VOL_BLOCKS)
                or a
                sbc hl, de
                jr z, ia_full
                jr c, ia_full
                push bc
                push de
                ld c, 0
gr_len:         ld a, c
                cp b
                jr z, gr_have
                ld hl, (VOL_BLOCKS)
                or a
                sbc hl, de
                jr z, gr_have
                jr c, gr_have
                call bit_free
                jr nz, gr_have
                inc de
                inc c
                jr gr_len
gr_have:        ld a, c
                pop de
                pop bc
                cp b
                jr z, gr_take
                inc de
                jr gr_scan
gr_take:        push de
                push bc
gr_mark:        ld a, b
                or a
                jr z, gr_rec
                call bit_set
                inc de
                dec b
                jr gr_mark
gr_rec:         pop bc
                pop de
                ld (wr_blk), de
                ld a, (INO_BUF + INO_EXTENTS)
                or a
                jr z, gr_new
                dec a
                ld hl, INO_BUF + INO_EXT0
                jr z, gr_at
gr_sk:          inc hl
                inc hl
                inc hl
                dec a
                jr nz, gr_sk
gr_at:          push hl
                ld a, (hl)
                inc hl
                push de
                ld e, a
                ld a, (hl)
                ld d, a
                inc hl
                ld a, (hl)
                add a, e
                ld e, a
                ld a, d
                adc a, 0
                ld d, a
                pop hl
                or a
                sbc hl, de
                pop hl
                jr nz, gr_new
                push hl
                inc hl
                inc hl
                ld a, (hl)
                add a, c
                jr c, gr_new2
                ld (hl), a
                pop hl
                xor a
                ret
gr_new2:        pop hl
gr_new:         ld de, (wr_blk)
                ld a, (INO_BUF + INO_EXTENTS)
                cp 6
                jp nc, ia_full
                ld l, a
                inc a
                ld (INO_BUF + INO_EXTENTS), a
                ld a, l
                add a, a
                add a, l
                ld hl, INO_BUF + INO_EXT0
                add a, l
                ld l, a
                jr nc, gr_put
                inc h
gr_put:         ld (hl), e
                inc hl
                ld (hl), d
                inc hl
                ld (hl), c
                xor a
                ret

wr_release:     ld a, (INO_BUF + INO_TYPE)
                and INO_INDIRECT
                ld c, EINVAL
                jp nz, fail
                ld a, (INO_BUF + INO_EXTENTS)
                ld (wr_count), a
                ld hl, INO_BUF + INO_EXT0
                ld de, wr_saved
                ld bc, 18
                ldir
                xor a
                ld (INO_BUF + INO_EXTENTS), a
                ld (INO_BUF + INO_SIZE), a
                ld (INO_BUF + INO_SIZE + 1), a
                ld (INO_BUF + INO_SIZE + 2), a
                ld hl, INO_BUF + INO_EXT0
                ld b, 18
rel_z:          ld (hl), a
                inc hl
                djnz rel_z
                ld a, (INO_BUF + INO_TYPE)
                and 33h
                ld (INO_BUF + INO_TYPE), a
                call stamp
                ld bc, (wr_child)
                call inode_store
                ret c
                call bm_load
                ret c
                ld hl, wr_saved
                ld a, (wr_count)
                ld b, a
rel_one:        ld a, b
                or a
                jp z, bm_save
                ld e, (hl)
                inc hl
                ld d, (hl)
                inc hl
                ld c, (hl)
                inc hl
                push hl
rel_bit:        ld a, c
                or a
                jr z, rel_dec
                push bc
                call bit_clr
                pop bc
                inc de
                dec c
                jr rel_bit
rel_dec:        pop hl
                dec b
                jr rel_one

inode_store:    call slot_ptr
                ret c
                push de
                ld d, h
                ld e, l
                ld hl, INO_BUF
                ld bc, 32
                ldir
                pop de
                ld hl, BLK_BUF
                jp floppy_write

zero_blk:       ld hl, BLK_BUF
                ld (hl), 0
                ld d, h
                ld e, l
                inc de
                ld bc, 255
                ldir
                ret

dir_add:        ld de, 1
da_find:        call slot_past
                jr c, da_grow
                push de
                call slot_addr
                pop de
                ret c
                ld a, (hl)
                inc hl
                or (hl)
                jr z, da_use
                inc de
                jr da_find
da_grow:        push de
                ld a, e
                and 7
                jr nz, da_sz
                call bm_load
                jr c, da_pop
                ld c, 1
                call grow_run
                jr c, da_pop
                call bm_save
                jr c, da_pop
da_sz:          ld hl, INO_BUF + INO_SIZE
                ld a, (hl)
                add a, 32
                ld (hl), a
                jr nc, da_ok
                inc hl
                inc (hl)
da_ok:          pop de
da_use:         ld (wr_slot), de
                ld b, 3
da_sh:          srl d
                rr e
                djnz da_sh
                call fs_map
                ret c
                push de
                ld de, (wr_slot)
                call slot_addr
                pop de
                ret c
                push de
                ld bc, (wr_child)
                ld (hl), c
                inc hl
                ld (hl), b
                inc hl
                ex de, hl
                ld hl, (fs_namep)
                ld a, (fs_namel)
                ld b, a
                ld c, 30
da_ch:          ld a, b
                or a
                jr z, da_pad
                ld a, (hl)
                ld (de), a
                inc hl
                inc de
                dec b
                dec c
                jr da_ch
da_pad:         xor a
                ld b, c
                inc b
da_padl:        dec b
                jr z, da_put
                ld (de), a
                inc de
                jr da_padl
da_put:         pop de
                ld hl, BLK_BUF
                call floppy_write
                ret c
                call stamp
                ld bc, (wr_parent)
                jp inode_store
da_pop:         pop de
                ret

dir_clear:      ld de, 0
dc_find:        call slot_past
                ld c, EIO
                jp c, fail
                push de
                call slot_addr
                pop de
                ret c
                ld a, (hl)
                inc hl
                or (hl)
                dec hl
                jr z, dc_nx
                push de
                push hl
                call walk_eq
                pop hl
                pop de
                jr z, dc_hit
dc_nx:          inc de
                jr dc_find
dc_hit:         push de
                ld b, 32
dc_z:           ld (hl), 0
                inc hl
                djnz dc_z
                pop de
                ld b, 3
dc_sh:          srl d
                rr e
                djnz dc_sh
                call fs_map
                ret c
                ld hl, BLK_BUF
                call floppy_write
                ret c
                call stamp
                ld bc, (wr_parent)
                jp inode_store

blank:          ld hl, INO_BUF
                ld b, 32
bl_z:           ld (hl), 0
                inc hl
                djnz bl_z
                ret

save_name:      ld hl, (fs_ino)
                ld (wr_parent), hl
                ld hl, (fs_namep)
                ld (wr_namep), hl
                ld a, (fs_namel)
                ld (wr_namel), a
                ret

rest_name:      ld bc, (wr_parent)
                call c5fs_inode
                ret c
                ld hl, (wr_namep)
                ld (fs_namep), hl
                ld a, (wr_namel)
                ld (fs_namel), a
                xor a
                ret

ro_parent:      ld a, (INO_BUF + INO_TYPE)
                and INO_RO
                ret z
                ld c, EROFS
                jp fail

w_open:        call k_off
                call c5fs_walk
                jr nc, wo_have
                cp ENOENT
                scf
                ret nz
                ld a, b
                dec a
                ld c, ENOENT
                jp nz, fail
                ld a, (open_flags)
                and O_CREATE
                jp z, fail
wr_create:      call path_kernel
                ld c, EINVAL
                jp c, fail
                call ro_parent
                ret c
                call save_name
                call wr_ialloc
                ret c
                ld (wr_child), bc
                ld (open_ino), bc
                call wr_dirty
                ret c
                call blank
                ld a, INO_KIND_FILE
                ld (INO_BUF), a
                call stamp_both
                ld bc, (wr_child)
                call inode_store
                ret c
                call rest_name
                ret c
                call dir_add
                ret c
                call wr_sync
                ret c
wo_kind:        ld a, KIND_FILE
                ld (open_kind), a
                xor a
                ret
wo_have:        ld (open_ino), hl
                ld (wr_child), hl
                ld a, (open_flags)
                and O_CREATE | O_EXCL
                cp O_CREATE | O_EXCL
                ld c, EEXIST
                jp z, fail
                call path_kernel
                ld c, EINVAL
                jp c, fail
                ld a, (INO_BUF + INO_TYPE)
                and 0Fh
                cp INO_KIND_DIR
                ld c, EISDIR
                jp z, fail
                ld a, (open_flags)
                and O_WRITE | O_TRUNC | O_APPEND
                jr z, wo_kind
                call ro_parent
                ret c
                ld a, (open_flags)
                and O_TRUNC
                jr z, wo_kind
                call wr_dirty
                ret c
                call wr_release
                ret c
                call wr_sync
                ret c
                jr wo_kind

w_mkdir:       call k_off
                call path_kernel
                ld c, EINVAL
                jp c, fail
                call ro_parent
                ret c
                call save_name
                call wr_ialloc
                ret c
                ld (wr_child), bc
                call wr_dirty
                ret c
                call bm_load
                ret c
                ld c, 1
                call grow_run
                ret c
                call bm_save
                ret c
                ld hl, INO_BUF + INO_EXT0
                ld e, (hl)
                inc hl
                ld d, (hl)
                push de
                call zero_blk
                ld hl, (wr_parent)
                ld (BLK_BUF), hl
                ld a, '.'
                ld (BLK_BUF + 2), a
                ld (BLK_BUF + 3), a
                pop de
                ld hl, BLK_BUF
                call floppy_write
                ret c
                push de
                call blank
                pop de
                ld (INO_BUF + INO_EXT0), de
                ld a, INO_KIND_DIR
                ld (INO_BUF), a
                ld a, 1
                ld (INO_BUF + INO_EXTENTS), a
                ld (INO_BUF + INO_EXT0 + 2), a
                ld a, 32
                ld (INO_BUF + INO_SIZE), a
                call stamp_both
                ld bc, (wr_child)
                call inode_store
                ret c
                call rest_name
                ret c
                call dir_add
                ret c
                jp ok0

w_remove:       xor a
                ld (wr_kflag), a
                call path_kernel
                jr nc, rm_dir
                ld (wr_kflag), a
                inc a
                ld (wr_kflag), a
rm_dir:         ld a, (INO_BUF + INO_TYPE)
                and 0Fh
                cp INO_KIND_DIR
                jr nz, rm_ro
                ld de, 1
rm_sc:          call slot_past
                jr c, rm_ro
                push de
                call slot_addr
                pop de
                ret c
                ld a, (hl)
                inc hl
                or (hl)
                ld c, ENOTEMPTY
                jp nz, fail
                inc de
                jr rm_sc
rm_ro:          call ro_parent
                ret c
                ld de, (io_path)
                call c5fs_parent
                ret c
                call ro_parent
                ret c
                call save_name
                call wr_dirty
                ret c
                call dir_clear
                ret c
                ld bc, (wr_child)
                call c5fs_inode
                ret c
                call wr_release
                ret c
                jp ok0

w_rename:       call k_off
                ld de, (ren_old)
                ld (io_path), de
                call path_kernel
                ld c, EINVAL
                jp c, fail
                call c5fs_walk
                ret c
                ld (wr_child), hl
                ld a, (INO_BUF + INO_TYPE)
                ld (wr_kind), a
                call ro_parent
                ret c
                ld de, (ren_new)
                ld (io_path), de
                call path_kernel
                ld c, EINVAL
                jp c, fail
                call c5fs_walk
                ld c, EEXIST
                jp nc, fail
                cp ENOENT
                scf
                ret nz
                ld a, b
                dec a
                ld c, ENOENT
                jp nz, fail
                call ro_parent
                ret c
                call save_name
                ld hl, (wr_parent)
                ld (wr_newp), hl
                ld de, (ren_old)
                call c5fs_parent
                ret c
                call ro_parent
                ret c
                ld hl, (fs_ino)
                ld (wr_oldp), hl
                ld hl, (fs_namep)
                ld (wr_oname), hl
                ld a, (fs_namel)
                ld (wr_onlen), a
                call wr_dirty
                ret c
                ld hl, (wr_newp)
                ld (wr_parent), hl
                call rest_name
                ret c
                call dir_add
                ret c
                ld hl, (wr_oldp)
                ld (wr_parent), hl
                ld hl, (wr_oname)
                ld (fs_namep), hl
                ld a, (wr_onlen)
                ld (fs_namel), a
                ld bc, (wr_oldp)
                call c5fs_inode
                ret c
                call dir_clear
                ret c
                ld a, (wr_kind)
                and 0Fh
                cp INO_KIND_DIR
                jp nz, ok0
                ld hl, (wr_oldp)
                ld de, (wr_newp)
                or a
                sbc hl, de
                jp z, ok0
                ld bc, (wr_child)
                call c5fs_inode
                ret c
                ld de, 0
                call fs_map
                ret c
                push de
                ld hl, BLK_BUF
                call floppy_read
                pop de
                ret c
                ld hl, (wr_newp)
                ld (BLK_BUF), hl
                push de
                ld hl, BLK_BUF
                call floppy_write
                pop de
                ret c
                call stamp
                ld bc, (wr_child)
                call inode_store
                ret c
                jp ok0

w_write:        call k_off
                ld hl, (ofile_ptr)
                push hl
                ld de, OF_INO
                add hl, de
                ld c, (hl)
                inc hl
                ld b, (hl)
                ld (wr_child), bc
                pop hl
                call take_inode
                ret c
                call ro_parent
                ret c
                ld hl, (io_len)
                ld a, h
                or l
                jp z, ok0
                ld hl, (io_pos)
                ld a, (hl)
                or a
                ld c, EINVAL
                jp nz, fail
                ld a, (INO_BUF + INO_SIZE)
                or a
                jp nz, fail
                inc hl
                ld a, (INO_BUF + INO_SIZE + 1)
                cp (hl)
                jp nz, fail
                inc hl
                ld a, (INO_BUF + INO_SIZE + 2)
                cp (hl)
                jp nz, fail
                ld a, (io_len)
                ld c, a
                ld a, (io_len + 1)
                ld b, a
                ld (wr_count), a
                or c
                jp z, ok0
                ld a, c
                or a
                jr z, pw_n
                inc b
pw_n:           ld c, b
                exx
                call wr_dirty
                jr c, pw_x
                call bm_load
pw_x:           exx
                ret c
                call grow_run
                ret c
                call bm_save
                ret c
                ld a, (wr_count)
                ld b, a
                ld a, (INO_BUF + INO_SIZE + 1)
                ld e, a
                ld a, (INO_BUF + INO_SIZE + 2)
                ld d, a
; B = whole blocks left, DE = logical block. floppy_write does not keep BC.
pw_full:        ld a, b
                or a
                jr z, pw_part
                push bc
                push de
                call fs_map
                ld hl, (io_buf)
                call nc, floppy_write
                pop de
                pop bc
                ret c
                inc h
                ld (io_buf), hl
                inc de
                dec b
                jr pw_full
pw_part:        ld a, (io_len)
                or a
                jr z, pw_size
                push af
                call fs_map
                pop bc
                ret c
                ld (wr_blk), de
                push bc
                call zero_blk
                pop bc
                ld hl, (io_buf)
                ld de, BLK_BUF
                ld c, b
                ld b, 0
                ldir
                ld de, (wr_blk)
                ld hl, BLK_BUF
                call floppy_write
                ret c
pw_size:        ld hl, (io_len)
                ld a, (INO_BUF + INO_SIZE)
                add a, l
                ld (INO_BUF + INO_SIZE), a
                ld a, (INO_BUF + INO_SIZE + 1)
                adc a, h
                ld (INO_BUF + INO_SIZE + 1), a
                ld a, (INO_BUF + INO_SIZE + 2)
                adc a, 0
                ld (INO_BUF + INO_SIZE + 2), a
                ld hl, (io_pos)
                ld a, (hl)
                add a, 0
                ld de, (io_len)
                add a, e
                ld (hl), a
                inc hl
                ld a, (hl)
                adc a, d
                ld (hl), a
                inc hl
                ld a, (hl)
                adc a, 0
                ld (hl), a
                inc hl
                ld a, (hl)
                adc a, 0
                ld (hl), a
                call stamp
                ld bc, (wr_child)
                call inode_store
                ret c
                call wr_sync
                ret c
                ld hl, (io_len)
                xor a
                ret

wr_kflag:       db 0
wr_flag:        db 0
wr_parent:      dw 0
wr_newp:        dw 0
wr_oldp:        dw 0
wr_namep:       dw 0
wr_namel:       db 0
wr_oname:       dw 0
wr_onlen:       db 0
wr_kind:        db 0
wr_saved:       ds 18, 0
