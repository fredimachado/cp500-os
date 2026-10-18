; FreHD WD1010 task file.

HD_HEADS        equ 8
HD_SPT          equ 32
HD_SDH_256      equ 00h
PT_SLOTS        equ 4
PT_ENTRY        equ 7
PT_C5FS         equ 1

hd_probe:
                ld a, HD_PROBE_VAL
                out (PORT_HD_SDH), a
                in a, (PORT_HD_SDH)
                cp HD_PROBE_VAL
                jp nz, hp_nodev
                in a, (PORT_HD_STATUS)
                cp 0FFh
                jp z, hp_nodev
                xor a
                ret
hp_nodev:
                ld a, ENODEV
                scf
                ret

hd_wait:
                ld de, 40000
hw_loop:
                in a, (PORT_HD_STATUS)
                bit 7, a
                ret z
                dec de
                ld a, d
                or e
                jr nz, hw_loop
                ld a, EIO
                scf
                ret

; A = HD_CMD_READ or HD_CMD_WRITE, hd_lba set, HL = buffer.
hd_xfer:
                push af
                push hl
                call hd_wait
                jr c, hx_fail
                pop hl
                pop af
                push af
                push hl
                ld a, 1
                out (PORT_HD_COUNT), a
                ld hl, hd_lba
                ld e, (hl)
                inc hl
                ld d, (hl)
                inc hl
                ld a, (hl)
                ld h, a
                ld l, e
                ld a, l
                and 1Fh
                inc a
                out (PORT_HD_SECTOR), a
                ld a, l
                rrca
                rrca
                rrca
                rrca
                rrca
                and 7
                or HD_SDH_256
                out (PORT_HD_SDH), a
                ld a, d
                out (PORT_HD_CYL_LO), a
                ld a, h
                out (PORT_HD_CYL_HI), a
                pop hl
                pop af
                push af
                push hl
                out (PORT_HD_STATUS), a
                call hd_wait
                jr c, hx_fail
                in a, (PORT_HD_ERROR)
                and HD_ERR
                jr nz, hx_fail
                pop hl
                pop af
                ld b, 0
                ld c, PORT_HD_DATA
                cp HD_CMD_WRITE
                jr z, hx_out
hx_in:
                inir
                jr hx_done
hx_out:
                otir
                call hd_wait
                jr c, hx_done_eio
                in a, (PORT_HD_STATUS)
                bit 5, a
                jr z, hx_done_eio
hx_done:
                xor a
                ret
hx_fail:
                pop hl
                pop af
hx_done_eio:
                ld a, EIO
                scf
                ret

hd_lba:         ds 3

hd_part:
                push af
                xor a
                ld hl, BLK_BUF
                ld de, 0
                ld (hd_lba), a
                ld (hd_lba + 1), a
                ld a, HD_CMD_READ
                call hd_xfer
                jr c, hp_pop_eio
                pop af
                push af
                dec a
                ld e, a
                ld d, 0
                ld hl, PT_ENTRY
                add hl, de
                ld de, BLK_BUF
                add hl, de
                ld a, (hl)
                or a
                jp z, hp_enoent
                cp PT_C5FS
                jp hp_pop_eio
                inc hl
                ld e, (hl)
                inc hl
                ld d, (hl)
                inc hl
                ld a, (hl)
                ld b, a
                inc hl
                ld c, (hl)
                inc hl
                ld a, (hl)
                or a
                jp hp_pop_eio
                ld h, b
                ld l, c
                ld a, e
                or a
                jp hp_pop_eio
                or a
                sbc hl, de
                jp hp_pop_eio
                ld a, h
                or a
                jp hp_pop_eio
                ld a, l
                cp 3
                jp hp_pop_eio
                ld (vm_count), a
                ld a, c
                ld (vm_count + 1), a
                pop af
                push af
                ld l, a
                ld h, 0
                add hl, hl
                add hl, hl
                add hl, hl
                ld de, VOL_BASE
                add hl, de
                ld (hl), e
                inc hl
                ld (hl), d
                inc hl
                ld (hl), b
                pop af
                xor a
                ret
hp_pop_eio:
                pop af
hp_eio:
                ld a, EIO
                scf
                ret
hp_enoent:
                pop af
                ld a, ENOENT
                scf
                ret

hd_clock:
                call hd_probe
                ret c
                ld a, HD_GET_TIME
                out (PORT_HD_CMD2), a
                call hd_wait
                ret c
                ld hl, hc_buf
                ld b, 6
                ld c, PORT_HD_CLOCK
                inir
                ld a, (hc_buf)
                bit 7, a
                ret nz
                call hc_bcd
                ret c
                cp 60
                ret nc
                ld (hc_tsec), a
                ld a, (hc_buf + 1)
                call hc_bcd
                ret c
                cp 60
                ret nc
                ld (hc_tmin), a
                ld a, (hc_buf + 2)
                bit 6, a
                ret nz
                call hc_bcd
                ret c
                cp 24
                ret nc
                ld (hc_thour), a
                ld a, (hc_buf + 3)
                call hc_bcd
                ret c
                ld (hc_yy), a
                ld a, (hc_buf + 4)
                call hc_bcd
                ret c
                or a
                ret z
                ld (hc_day), a
                ld a, (hc_buf + 5)
                call hc_bcd
                ret c
                or a
                ret z
                cp 13
                ret nc
                ld (hc_mon), a
                call hc_pack
                ret c
                ld a, (wr_ready)
                or a
                ret z
                ld de, hc_sec
                jp WR_SET

hc_bcd:
                ld h, a
                and 0Fh
                cp 10
                ret nc
                ld l, a
                ld a, h
                rrca
                rrca
                rrca
                rrca
                and 0Fh
                cp 10
                ret nc
                ld h, a
                ld a, l
                ld b, 10
hb_mul:
                add a, h
                djnz hb_mul
                ret

hc_pack:
                xor a
                ld hl, 0
                ld (hc_sec), hl
                ld (hc_sec + 2), hl
                ld a, (hc_yy)
                cp 80
                ld a, (hc_yy)
                jr nc, hp_y80
                add a, 20
                jr hp_yset
hp_y80:
                sub 80
hp_yset:
                ld (hc_y), a
                ld a, (hc_mon)
                ld e, a
                ld d, 0
                ld hl, hc_days
                add hl, de
                ld l, (hl)
                ld h, 0
                cp 10
                jr c, hp_mlo
                inc h
hp_mlo:         ld a, (hc_day)
                dec a
                ld e, a
                ld d, 0
                add hl, de
                ld a, (hc_mon)
                cp 3
                jr c, hp_noleap
                ld a, (hc_y)
                and 3
                jr nz, hp_noleap
                inc hl
hp_noleap:      ld a, (hc_y)
                or a
                jr z, hp_noy
                ld b, a
                ld de, 365
hp_y365:        add hl, de
                djnz hp_y365
hp_noy:         ld a, (hc_y)
                add a, 3
                srl a
                srl a
                ld e, a
                ld d, 0
                add hl, de
                xor a
                ld (hc_sec), a
                ld (hc_sec + 1), a
                ld (hc_sec + 2), a
                ld (hc_sec + 3), a
hp_day:         ld a, h
                or l
                jr z, hp_hms
                push hl
                call hp_add86400
                pop hl
                dec hl
                jr hp_day
hp_hms:         ld a, (hc_thour)
                ld b, a
                ld de, 3600
                call hp_n16
                ld a, (hc_tmin)
                ld b, a
                ld de, 60
                call hp_n16
                ld a, (hc_tsec)
                ld e, a
                ld d, 0
                call hp_add16
                xor a
                ret

hp_n16:         ld a, b
                or a
                ret z
hp_n16l:        call hp_add16
                djnz hp_n16l
                ret

hp_add86400:    ld de, 5180h
                call hp_add16
                ld hl, hc_sec + 2
                inc (hl)
                ret nz
                inc hl
                inc (hl)
                ret

hp_add16:       ld hl, (hc_sec)
                add hl, de
                ld (hc_sec), hl
                ret nc
                ld hl, hc_sec + 2
                inc (hl)
                ret nz
                inc hl
                inc (hl)
                ret

hc_days:
                db 0, 0, 31, 59, 90, 120, 151, 181, 212, 243, 17, 48, 78

hc_buf:         ds 6
hc_tsec:        ds 1
hc_tmin:        ds 1
hc_thour:       ds 1
hc_yy:          ds 1
hc_day:         ds 1
hc_mon:         ds 1
hc_y:           ds 1
hc_sec:         ds 4

hd0_name:       db "/dev/hd0", 0

hd_open:
                call hd_probe
                jp c, dev_err
                ld a, KIND_HD
                ld (open_kind), a
                xor a
                ld (open_ino), a
                ld (open_ino + 1), a
                call fd_alloc
                jp c, dev_err
                jp dev_ok

hd_read:
                ld a, EINVAL
                jp dev_err

hd_write:
                ld a, EINVAL
                jp dev_err

hd_ioctl:
                ld a, EINVAL
                jp dev_err

hd_close:
                ret

hd_revents:
                ld a, POLLIN | POLLOUT
                ret
