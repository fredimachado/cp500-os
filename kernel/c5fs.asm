; Read-only C5FS. One inode in INO_BUF, one sector in BLK_BUF.

c5fs_mount:
                ld de, 1
                call mt_load
                ret c
                call mt_valid
                ld a, 0
                jr c, mt_no1
                ld a, 1
mt_no1:
                ld (mt_flag), a
                ld hl, BLK_BUF + SB_SEQ
                ld de, mt_seq
                ld bc, 4
                ldir
                ld de, 2
                call mt_load
                ret c
                call mt_valid
                jr c, mt_no2
                ld a, (mt_flag)
                or a
                jr z, mt_use
                call mt_b2_higher
                jr c, mt_use
                jr mt_use1
mt_no2:
                ld a, (mt_flag)
                or a
                jp z, fs_eio
mt_use1:
                ld de, 1
                call mt_load
                ret c
mt_use:
                jp mt_apply

mt_load:
                ld hl, BLK_BUF
                jp floppy_read

mt_valid:
                ld hl, BLK_BUF
                ld de, mt_magic
                ld b, 4
mt_mag:
                ld a, (de)
                cp (hl)
                scf
                ret nz
                inc de
                inc hl
                djnz mt_mag
                ld hl, BLK_BUF
                ld b, 254
                call fs_crc
                ld a, (BLK_BUF + SB_CRC)
                cp l
                scf
                ret nz
                ld a, (BLK_BUF + SB_CRC + 1)
                cp h
                scf
                ret nz
                or a
                ret

mt_magic:
                db "C5FS"

; Carry set when the sequence in BLK_BUF is strictly above mt_seq.
mt_b2_higher:
                ld hl, BLK_BUF + SB_SEQ + 3
                ld de, mt_seq + 3
                ld b, 4
mt_cmp:
                ld a, (de)
                cp (hl)
                ret nz
                dec hl
                dec de
                djnz mt_cmp
                or a
                ret

mt_apply:
                ld a, (BLK_BUF + SB_VERSION)
                cp 1
                jp nz, fs_eio
                ld a, (BLK_BUF + SB_FLAGS)
                and 0FEh
                jp nz, fs_eio
                ld a, (BLK_BUF + SB_SPT)
                or a
                jp z, fs_eio
                ld (mt_spt), a
                ld a, (BLK_BUF + SB_SIDES)
                ld (mt_sides), a
                cp 1
                jr z, mt_geom
                cp 2
                jp nz, fs_eio
mt_geom:
                ld hl, (BLK_BUF + 16)
                ld a, h
                or l
                jp z, fs_eio
                ld (mt_blocks), hl
                ld hl, (BLK_BUF + 18)
                ld a, h
                or a
                jp nz, fs_eio
                ld a, l
                cp 3
                jp nz, fs_eio
                ld hl, (BLK_BUF + 23)
                ld a, l
                and 7
                jp nz, fs_eio
                ld a, h
                or l
                jp z, fs_eio
                ld (mt_icount), hl
                call mt_bitmap_len
                ld a, (BLK_BUF + 20)
                cp l
                jp nz, fs_eio
                ld a, l
                add a, 3
                ld l, a
                ld h, 0
                ld (mt_itable), hl
                ld de, (BLK_BUF + 21)
                or a
                sbc hl, de
                jp nz, fs_eio
                ld hl, (mt_itable)
                ld de, (mt_icount)
                srl d
                rr e
                srl d
                rr e
                srl d
                rr e
                add hl, de
                ld (mt_first), hl
                ld de, (BLK_BUF + 25)
                or a
                sbc hl, de
                jp nz, fs_eio
                ld hl, (mt_blocks)
                ld de, (mt_first)
                or a
                sbc hl, de
                jp z, fs_eio
                jp c, fs_eio
                ld a, (BLK_BUF + SB_TRACKS)
                ld c, a
                ld a, (mt_spt)
                call mul88
                ld a, (mt_sides)
                dec a
                jr z, mt_prod
                add hl, hl
                jp c, fs_eio
mt_prod:
                ld de, (mt_blocks)
                or a
                sbc hl, de
                jp nz, fs_eio
                ld a, (BLK_BUF + SB_SIDES)
                cp 1
                jr z, mt_store_sides
                ld a, 2
mt_store_sides:
                ld (VOL_SIDES), a
                ld a, (mt_spt)
                ld (VOL_SPT), a
                ld hl, (mt_blocks)
                ld (VOL_BLOCKS), hl
                ld hl, (mt_itable)
                ld (VOL_ITABLE), hl
                ld hl, (mt_icount)
                ld (VOL_ICOUNT), hl
                ld hl, (mt_first)
                ld (VOL_FIRST), hl
                xor a
                ret

; L = ceil(block count / 2048).
mt_bitmap_len:
                ld hl, (mt_blocks)
                ld de, 2047
                add hl, de
                ld a, 0
                adc a, 0
                ld b, 11
mt_shift:
                srl a
                rr h
                rr l
                djnz mt_shift
                ret

; A * C -> HL. Both factors fit in a byte, and the product fits in 16 bits.
mul88:
                ld hl, 0
                ld e, a
                ld d, 0
                ld b, 8
mul_bit:
                srl c
                jr nc, mul_skip
                add hl, de
mul_skip:
                sla e
                rl d
                djnz mul_bit
                ret

; HL = data, B = length. HL = CRC-16/CCITT-FALSE, init FFFFh, poly 1021h.
fs_crc:
                ld d, h
                ld e, l
                ld hl, 0FFFFh
fs_crc_byte:
                ld a, (de)
                inc de
                xor h
                ld h, a
                ld c, 8
fs_crc_bit:
                add hl, hl
                jr nc, fs_crc_next
                ld a, h
                xor 10h
                ld h, a
                ld a, l
                xor 21h
                ld l, a
fs_crc_next:
                dec c
                jr nz, fs_crc_bit
                djnz fs_crc_byte
                ret

fs_eio:
                ld a, EIO
                scf
                ret

; BC = inode. Fills and checks INO_BUF.
c5fs_inode:
                ld a, b
                or c
                jp z, fs_eio
                push bc
                ld hl, (VOL_ICOUNT)
                or a
                sbc hl, bc
                jp z, ino_pop
                jp c, ino_pop
                ld a, c
                and 7
                ld l, a
                ld h, 0
                add hl, hl
                add hl, hl
                add hl, hl
                add hl, hl
                add hl, hl
                push hl
                ld h, b
                ld l, c
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                ld de, (VOL_ITABLE)
                add hl, de
                ex de, hl
                ld hl, BLK_BUF
                call floppy_read
                pop hl
                jr c, ino_pop
                ld de, BLK_BUF
                add hl, de
                ld de, INO_BUF
                ld bc, 32
                ldir
                pop bc
                jp ino_check
ino_pop:
                pop bc
                jp fs_eio

ino_check:
                ld a, (INO_BUF + INO_RES)
                or a
                jp nz, fs_eio
                ld a, (INO_BUF + INO_TYPE)
                bit 7, a
                jp nz, fs_eio
                and 0Fh
                cp INO_KIND_FILE
                jr z, ino_count
                cp INO_KIND_DIR
                jp nz, fs_eio
ino_count:
                ld a, (INO_BUF + INO_TYPE)
                and INO_INDIRECT
                ld b, a
                ld a, (INO_BUF + INO_EXTENTS)
                ld c, a
                ld a, b
                or a
                jr z, ino_direct_n
                ld a, c
                cp 7
                jp c, fs_eio
                cp 91
                jp nc, fs_eio
                jr ino_sum
ino_direct_n:
                ld a, c
                cp 7
                jp nc, fs_eio
ino_sum:
                ld hl, 0
                ld (fs_sum), hl
                ld a, (INO_BUF + INO_TYPE)
                and INO_INDIRECT
                jr nz, ino_indirect
                ld hl, INO_BUF + INO_EXT0
                ld a, (INO_BUF + INO_EXTENTS)
                ld b, a
                call ino_extents
                ret c
                ld de, INO_BUF + INO_RES
                call ino_zeros
                ret c
                jp ino_size
ino_indirect:
                ld hl, INO_BUF + INO_EXT0
                ld b, 5
                call ino_extents
                ret c
                ld e, (hl)
                inc hl
                ld d, (hl)
                inc hl
                ld a, (hl)
                or a
                jp nz, fs_eio
                call ino_one_block
                ret c
                ld hl, BLK_BUF
                call floppy_read
                ret c
                ld hl, BLK_BUF
                ld a, (INO_BUF + INO_EXTENTS)
                sub 5
                ld b, a
                call ino_extents
                ret c
                ld de, BLK_BUF + 256
                call ino_zeros
                ret c
                jp ino_size

; HL = extent array, B = count. HL advances past the array.
ino_extents:
                ld a, b
                or a
                ret z
ino_ext_one:
                call ino_extent
                ret c
                djnz ino_ext_one
                or a
                ret

ino_extent:
                ld e, (hl)
                inc hl
                ld d, (hl)
                inc hl
                ld a, (hl)
                inc hl
                or a
                scf
                ret z
                ld c, a
                push hl
                ld hl, (VOL_FIRST)
                ld a, d
                cp h
                jr c, ino_ext_bad
                jr nz, ino_ext_ge
                ld a, e
                cp l
                jr c, ino_ext_bad
ino_ext_ge:
                ld a, e
                add a, c
                ld e, a
                ld a, d
                adc a, 0
                ld d, a
                jr c, ino_ext_bad
                ld hl, (VOL_BLOCKS)
                ld a, d
                cp h
                jr c, ino_ext_len
                jr nz, ino_ext_bad
                ld a, e
                cp l
                jr z, ino_ext_len
                jr nc, ino_ext_bad
ino_ext_len:
                push bc
                ld b, 0
                ld hl, (fs_sum)
                add hl, bc
                pop bc
                jr c, ino_ext_bad
                ld (fs_sum), hl
                pop hl
                or a
                ret
ino_ext_bad:
                pop hl
                scf
                ret

; DE is one data-area block number.
ino_one_block:
                push hl
                ld hl, (VOL_FIRST)
                ld a, d
                cp h
                jr c, ino_blk_bad
                jr nz, ino_blk_ge
                ld a, e
                cp l
                jr c, ino_blk_bad
ino_blk_ge:
                ld hl, (VOL_BLOCKS)
                ld a, d
                cp h
                jr c, ino_blk_ok
                jr nz, ino_blk_bad
                ld a, e
                cp l
                jr c, ino_blk_ok
ino_blk_bad:
                pop hl
                scf
                ret
ino_blk_ok:
                pop hl
                or a
                ret

; Bytes from HL up to DE are zero.
ino_zeros:
ino_zloop:
                ld a, l
                cp e
                jr nz, ino_zbyte
                ld a, h
                cp d
                ret z
ino_zbyte:
                ld a, (hl)
                or a
                scf
                ret nz
                inc hl
                jr ino_zloop

ino_size:
                ld a, (INO_BUF + INO_SIZE)
                add a, 255
                ld l, a
                ld a, (INO_BUF + INO_SIZE + 1)
                adc a, 0
                ld h, a
                ld a, (INO_BUF + INO_SIZE + 2)
                adc a, 0
                jp c, fs_eio
                ld l, h
                ld h, a
                ld de, (fs_sum)
                or a
                sbc hl, de
                jp nz, fs_eio
                ld a, (INO_BUF + INO_TYPE)
                and 0Fh
                cp INO_KIND_DIR
                jr nz, ino_ok
                ld a, (INO_BUF + INO_SIZE)
                and 31
                jp nz, fs_eio
                ld a, (INO_BUF + INO_SIZE)
                ld hl, INO_BUF + INO_SIZE + 1
                or (hl)
                inc hl
                or (hl)
                jp z, fs_eio
ino_ok:
                xor a
                ret

; DE = logical block. DE = physical block. INO_BUF stays put.
fs_map:
                ld (fs_log), de
                ld l, 0
fs_map_next:
                ld a, (INO_BUF + INO_EXTENTS)
                cp l
                jp z, fs_eio
                jp c, fs_eio
                push hl
                call fs_extent_n
                pop hl
                ret c
                ld a, (fs_log + 1)
                or a
                jr nz, fs_map_skip
                ld a, (fs_log)
                cp c
                jr c, fs_map_hit
fs_map_skip:
                ld a, (fs_log)
                sub c
                ld (fs_log), a
                ld a, (fs_log + 1)
                sbc a, 0
                ld (fs_log + 1), a
                inc l
                jr fs_map_next
fs_map_hit:
                ld a, (fs_log)
                add a, e
                ld e, a
                ld a, d
                adc a, 0
                ld d, a
                or a
                ret

; L = extent index. DE = start, C = length.
fs_extent_n:
                ld a, (INO_BUF + INO_TYPE)
                and INO_INDIRECT
                jr z, fs_ext_inline
                ld a, l
                cp 5
                jr c, fs_ext_inline
                sub 5
                push af
                ld hl, INO_BUF + 28
                ld e, (hl)
                inc hl
                ld d, (hl)
                ld hl, BLK_BUF
                call floppy_read
                pop af
                ret c
                ld hl, BLK_BUF
                jr fs_ext_index
fs_ext_inline:
                ld a, l
                ld hl, INO_BUF + INO_EXT0
fs_ext_index:
                ld b, a
                or a
                jr z, fs_ext_read
fs_ext_skip:
                inc hl
                inc hl
                inc hl
                djnz fs_ext_skip
fs_ext_read:
                ld e, (hl)
                inc hl
                ld d, (hl)
                inc hl
                ld c, (hl)
                or a
                ret

; HL = destination, IX = length, DE = pointer to the 4-byte offset.
c5fs_read:
                ld (fs_dst), hl
                ld (fs_len), ix
                ld hl, fs_acc
                ex de, hl
                ld bc, 4
                ldir
                ld hl, 0
                ld (fs_got), hl
                ld a, (INO_BUF + INO_TYPE)
                and 0Fh
                cp INO_KIND_FILE
                jp nz, fs_eio
rd_loop:
                ld hl, (fs_len)
                ld a, h
                or l
                jp z, rd_done
                call rd_eof
                jp c, rd_done
                ld a, (fs_acc)
                ld (fs_within), a
                ld a, (fs_acc + 1)
                ld e, a
                ld a, (fs_acc + 2)
                ld d, a
                call fs_map
                ret c
                ld hl, BLK_BUF
                call floppy_read
                ret c
                ld a, (fs_within)
                ld e, a
                ld d, 0
                ld hl, 256
                or a
                sbc hl, de
                ld de, (fs_len)
                push hl
                or a
                sbc hl, de
                pop hl
                jr c, rd_len_ok
                ld h, d
                ld l, e
rd_len_ok:
                push hl
                call rd_room
                pop hl
                ld a, d
                or a
                jr nz, rd_copy
                push hl
                or a
                sbc hl, de
                pop hl
                jr c, rd_copy
                ld h, d
                ld l, e
rd_copy:
                ld b, h
                ld c, l
                ld a, b
                or c
                jr z, rd_done
                push bc
                ld hl, BLK_BUF
                ld a, (fs_within)
                add a, l
                ld l, a
                ld a, h
                adc a, 0
                ld h, a
                ld de, (fs_dst)
                ldir
                ld (fs_dst), de
                pop bc
                ld hl, (fs_got)
                add hl, bc
                ld (fs_got), hl
                ld hl, (fs_len)
                or a
                sbc hl, bc
                ld (fs_len), hl
                ld hl, fs_acc
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
                jp rd_loop
rd_done:
                ld hl, (fs_got)
                xor a
                ret

; Carry set when the working offset is at or past the file size.
rd_eof:
                ld a, (fs_acc + 3)
                or a
                scf
                ret nz
                ld hl, INO_BUF + INO_SIZE
                ld a, (fs_acc)
                sub (hl)
                inc hl
                ld a, (fs_acc + 1)
                sbc a, (hl)
                inc hl
                ld a, (fs_acc + 2)
                sbc a, (hl)
                ccf
                ret

; DE = bytes from the offset to the end of the file, or 65535 when that is larger.
rd_room:
                ld hl, fs_acc
                ld a, (INO_BUF + INO_SIZE)
                sub (hl)
                ld e, a
                inc hl
                ld a, (INO_BUF + INO_SIZE + 1)
                sbc a, (hl)
                ld d, a
                inc hl
                ld a, (INO_BUF + INO_SIZE + 2)
                sbc a, (hl)
                ret c
                or a
                ret z
                ld de, 65535
                ret

; DE = slot index, HL = 32-byte destination. HL = 1 and DE = next slot, or HL = 0 at the end.
c5fs_readdir:
                ld a, (INO_BUF + INO_TYPE)
                and 0Fh
                cp INO_KIND_DIR
                jp nz, fs_eio
                ld (fs_dst), hl
dir_next:
                call slot_past
                jr c, dir_end
                push de
                call slot_addr
                pop de
                ret c
                ld a, (hl)
                inc hl
                or (hl)
                dec hl
                jr nz, dir_hit
                inc de
                jr dir_next
dir_hit:
                push de
                ld de, (fs_dst)
                ld bc, 32
                ldir
                pop hl
                inc hl
                ex de, hl
                ld hl, 1
                xor a
                ret
dir_end:
                ld hl, 0
                xor a
                ret

; Carry set when DE is at or past the directory's slot count.
slot_past:
                ld hl, (INO_BUF + INO_SIZE)
                ld a, (INO_BUF + INO_SIZE + 2)
                ld b, 5
slot_shr:
                srl a
                rr h
                rr l
                djnz slot_shr
                or a
                ret nz
                push hl
                or a
                sbc hl, de
                pop hl
                jr c, slot_yes
                jr z, slot_yes
                or a
                ret
slot_yes:
                scf
                ret

; DE = slot. HL points at that 32-byte slot in BLK_BUF.
slot_addr:
                ld a, e
                and 7
                ld l, a
                ld h, 0
                add hl, hl
                add hl, hl
                add hl, hl
                add hl, hl
                add hl, hl
                push hl
                ld h, d
                ld l, e
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                ex de, hl
                call fs_map
                pop hl
                ret c
                push hl
                ld hl, BLK_BUF
                call floppy_read
                pop hl
                ret c
                ld de, BLK_BUF
                add hl, de
                or a
                ret

; BC = inode number, HL = 16-byte stat record.
c5fs_stat:
                ld (hl), c
                inc hl
                ld (hl), b
                inc hl
                ld a, (INO_BUF + INO_TYPE)
                and 3Fh
                ld (hl), a
                inc hl
                xor a
                ld (hl), a
                inc hl
                ld a, (INO_BUF + INO_SIZE)
                ld (hl), a
                inc hl
                ld a, (INO_BUF + INO_SIZE + 1)
                ld (hl), a
                inc hl
                ld a, (INO_BUF + INO_SIZE + 2)
                ld (hl), a
                inc hl
                xor a
                ld (hl), a
                inc hl
                ex de, hl
                ld hl, INO_BUF + INO_MOD
                ld bc, 8
                ldir
                ld hl, 0
                xor a
                ret

; DE = path. HL = inode and B = 0, or carry and A = error.
; A final miss leaves B = 1 and the parent in INO_BUF.
c5fs_walk:
                xor a
                ld (fs_mode), a
                jr walk_go

c5fs_parent:
                ld a, 1
                ld (fs_mode), a
                jr walk_go

c5fs_syntax:
                ld a, 2
                ld (fs_mode), a

walk_go:
                xor a
                ld (fs_scan), a
                ld (fs_canon), a
                ld (fs_ptr), de
                ld hl, (fs_ptr)
                ld a, (hl)
                cp '/'
                jp nz, walk_inval
                call walk_eat
                ret c
                ld a, (fs_mode)
                cp 2
                jr z, walk_seg
                ld bc, 1
                ld (fs_ino), bc
                call c5fs_inode
                ret c
walk_seg:
                call walk_slashes
                ret c
                ld hl, (fs_ptr)
                ld a, (hl)
                or a
                jp z, walk_ok
                call walk_name
                ret c
                call walk_dot
                ret c
                call walk_last
                ret c
                ld a, (fs_mode)
                cp 2
                jr z, walk_seg
                ld a, (fs_islast)
                or a
                jr z, walk_look
                ld a, (fs_mode)
                dec a
                jr z, walk_ok
walk_look:
                call walk_find
                jr nc, walk_hit
                or a
                scf
                ret nz
                ld a, (fs_islast)
                or a
                jr z, walk_miss0
                ld b, 1
                ld a, ENOENT
                scf
                ret
walk_miss0:
                ld b, 0
                ld a, ENOENT
                scf
                ret
walk_hit:
                ld (fs_ino), bc
                call c5fs_inode
                ret c
                ld a, (fs_islast)
                or a
                jr nz, walk_ok
                ld a, (INO_BUF + INO_TYPE)
                and 0Fh
                cp INO_KIND_DIR
                jr z, walk_seg
                ld a, ENOTDIR
                scf
                ret
walk_ok:
                ld a, (fs_mode)
                cp 2
                jr z, walk_syn
                ld hl, (fs_ino)
                ld b, 0
                xor a
                ret
walk_syn:
                xor a
                ret
walk_inval:
                ld a, EINVAL
                scf
                ret

walk_eat:
                ld a, (fs_scan)
                cp 128
                jr z, walk_inval
                ld hl, (fs_ptr)
                ld a, (hl)
                inc hl
                ld (fs_ptr), hl
                ld hl, fs_scan
                inc (hl)
                or a
                ret

walk_slashes:
                ld hl, (fs_ptr)
                ld a, (hl)
                cp '/'
                jr z, walk_slash_eat
                xor a
                ret
walk_slash_eat:
                call walk_eat
                ret c
                jr walk_slashes

walk_name:
                ld hl, (fs_ptr)
                ld (fs_namep), hl
                xor a
                ld (fs_namel), a
walk_nloop:
                ld hl, (fs_ptr)
                ld a, (hl)
                or a
                jr z, walk_nend
                cp '/'
                jr z, walk_nend
                call walk_char
                ret c
                ld a, (fs_namel)
                cp 30
                jp z, walk_inval
                call walk_eat
                ret c
                ld hl, fs_namel
                inc (hl)
                jr walk_nloop
walk_nend:
                ld a, (fs_namel)
                or a
                jp z, walk_inval
                ld hl, fs_namel
                ld a, (fs_canon)
                add a, (hl)
                inc a
                jp c, walk_inval
                cp 128
                jp nc, walk_inval
                ld (fs_canon), a
                xor a
                ret

walk_char:
                cp 20h
                jp c, walk_inval
                cp 7Fh
                jr c, walk_char_ok
                cp 0A0h
                jp c, walk_inval
walk_char_ok:
                xor a
                ret

walk_dot:
                ld a, (fs_namel)
                cp 1
                jr z, walk_dot1
                cp 2
                jr nz, walk_dot_ok
                ld hl, (fs_namep)
                ld a, (hl)
                cp '.'
                jr nz, walk_dot_ok
                inc hl
                ld a, (hl)
                cp '.'
                jp z, walk_inval
walk_dot_ok:
                xor a
                ret
walk_dot1:
                ld hl, (fs_namep)
                ld a, (hl)
                cp '.'
                jr nz, walk_dot_ok
                jp walk_inval

; fs_islast = 1 when only slashes and a NUL follow the name.
walk_last:
                ld hl, (fs_ptr)
                push hl
                ld a, (fs_scan)
                push af
                call walk_slashes
                jr c, walk_last_bad
                ld hl, (fs_ptr)
                ld a, (hl)
                or a
                ld c, 0
                jr nz, walk_last_no
                ld c, 1
walk_last_no:
                pop af
                ld (fs_scan), a
                pop hl
                ld (fs_ptr), hl
                ld a, c
                ld (fs_islast), a
                xor a
                ret
walk_last_bad:
                pop af
                ld (fs_scan), a
                pop hl
                ld (fs_ptr), hl
                jp walk_inval

walk_find:
                ld de, 0
walk_fnext:
                push de
                call slot_past
                pop de
                jr c, walk_fno
                push de
                call slot_addr
                pop de
                ret c
                ld c, (hl)
                inc hl
                ld b, (hl)
                dec hl
                ld a, b
                or c
                jr z, walk_fadv
                push bc
                push de
                call walk_eq
                pop de
                pop bc
                jr nz, walk_fadv
                xor a
                ret
walk_fadv:
                inc de
                jr walk_fnext
walk_fno:
                xor a
                scf
                ret

walk_eq:
                inc hl
                inc hl
                ld de, (fs_namep)
                ld a, (fs_namel)
                ld b, a
walk_eq_b:
                ld a, (de)
                call walk_fold
                ld c, a
                ld a, (hl)
                call walk_fold
                cp c
                ret nz
                inc hl
                inc de
                djnz walk_eq_b
                ld a, (fs_namel)
                cp 30
                ret z
                ld a, (hl)
                or a
                ret

walk_fold:
                cp 'A'
                ret c
                cp 'Z' + 1
                jr c, walk_fold_add
                cp 0C0h
                ret c
                cp 0D7h
                ret z
                cp 0DFh
                ret nc
walk_fold_add:
                add a, 20h
                ret

mt_flag:        db 0
mt_seq:         ds 4, 0
mt_spt:         db 0
mt_sides:       db 0
mt_blocks:      dw 0
mt_icount:      dw 0
mt_itable:      dw 0
mt_first:       dw 0
fs_sum:         dw 0
fs_log:         dw 0
fs_dst:         dw 0
fs_len:         dw 0
fs_got:         dw 0
fs_acc:         ds 4, 0
fs_within:      db 0
fs_scan:        db 0
fs_canon:       db 0
fs_mode:        db 0
fs_namel:       db 0
fs_namep:       dw 0
fs_ptr:         dw 0
fs_ino:         dw 0
fs_islast:      db 0
