                include "cp500.inc"

                org ORIGIN

                ld (argv), hl
                ld a, 1
                call arg_ptr
                jr c, open_hd0
                ld a, (hl)
                cp 'c'
                jr z, open_create
                cp 't'
                jr z, open_trunc
                cp 'a'
                jr z, open_append
                cp 'x'
                jr z, open_excl
                cp 'm'
                jr z, open_mount_file
                cp 'd'
                jr z, open_mount_dir
                cp 'n'
                jr z, open_bad_slot
                cp 'r'
                jr z, root_after_fail
                cp 'f'
                jp z, part_file
                cp 'w'
                jp z, open_large_write
                cp '3'
                jp z, open_slot3
                jp open_hd0

open_create:
                ld b, O_WRITE | O_CREATE
                jr open_hd0_flags
open_trunc:
                ld b, O_WRITE | O_TRUNC
                jr open_hd0_flags
open_append:
                ld b, O_WRITE | O_APPEND
                jr open_hd0_flags
open_excl:
                ld b, O_WRITE | O_CREATE | O_EXCL
                jr open_hd0_flags

open_hd0:
                ld b, O_READ
open_hd0_flags:
                ld c, SYS_OPEN
                ld de, hd0_path
                rst 08h
                jp c, exit_a
                ld c, SYS_EXIT
                ld de, 0
                rst 08h

open_mount_file:
                ld b, O_READ
                ld c, SYS_OPEN
                ld de, mnt_file
                rst 08h
                jp c, exit_a
                ld c, SYS_EXIT
                ld de, 0
                rst 08h

open_mount_dir:
                ld b, O_READ
                ld c, SYS_OPEN
                ld de, mnt_dir
                rst 08h
                jp c, exit_a
                ld c, SYS_EXIT
                ld de, 0
                rst 08h

open_slot3:
                ld b, O_READ
                ld c, SYS_OPEN
                ld de, mnt_p3
                rst 08h
                jp c, exit_a
                ld c, SYS_EXIT
                ld de, 0
                rst 08h

open_bad_slot:
                ld b, O_READ
                ld c, SYS_OPEN
                ld de, bad_slot
                rst 08h
                jp c, exit_a
                ld c, SYS_EXIT
                ld de, 0
                rst 08h

root_after_fail:
                ld b, O_READ
                ld c, SYS_OPEN
                ld de, mnt_file
                rst 08h
                ld b, O_READ
                ld c, SYS_OPEN
                ld de, note_path
                rst 08h
                jp c, exit_a
                ld c, SYS_EXIT
                ld de, 42
                rst 08h

part_file:
                ld b, O_READ
                ld c, SYS_OPEN
                ld de, mnt_file
                rst 08h
                jp c, exit_a
                ld a, l
                ld (pf_fd), a
                ld e, a
                ld d, 0
                ld hl, buf
                ld ix, 16
                ld c, SYS_READ
                rst 08h
                jp c, exit_a
                ld de, 0
                ld hl, buf
                ld b, 16
pf_chk:
                ld a, e
                xor d
                cp (hl)
                jp nz, exit_a
                inc hl
                inc de
                djnz pf_chk
                ld a, (pf_fd)
                ld e, a
                ld d, 0
                ld hl, at_1k
                ld b, 0
                ld c, SYS_SEEK
                rst 08h
                jp c, exit_a
                ld a, (pf_fd)
                ld e, a
                ld d, 0
                ld hl, buf
                ld ix, 1
                ld c, SYS_READ
                rst 08h
                jp c, exit_a
                ld a, (buf)
                cp 4
                jp nz, exit_a
                ld a, (pf_fd)
                ld e, a
                ld d, 0
                ld hl, st
                ld c, SYS_FSTAT
                rst 08h
                jp c, exit_a
                ld hl, (st + 4)
                ld de, 2048
                or a
                sbc hl, de
                ld a, 43
                jp nz, exit_a
                ld c, SYS_EXIT
                ld de, 44
                rst 08h

open_large_write:
                ld b, O_WRITE | O_CREATE | O_APPEND
                ld c, SYS_OPEN
                ld de, mnt_p2
                rst 08h
                jp c, exit_a
                ld c, SYS_EXIT
                ld de, 0
                rst 08h

exit_a:
                ld e, a
                ld d, 0
                ld c, SYS_EXIT
                rst 08h

hd0_path:       db "/dev/hd0", 0
mnt_file:       db "/mnt/hd0p1/x", 0
mnt_dir:        db "/mnt/hd0p1", 0
bad_slot:       db "/mnt/hd0p5/x", 0
note_path:      db "/home/note", 0
mnt_p2:         db "/mnt/hd0p2/log", 0
mnt_p3:         db "/mnt/hd0p3/x", 0
buf:            ds 16, 0
st:             ds 16, 0
at_1k:          db 0, 4, 0, 0
argv:           dw 0
pf_fd:          db 0

arg_ptr:
                ld hl, (argv)
                ld b, (hl)
                cp b
                ccf
                ret c
                inc hl
                inc hl
                ld b, a
                inc b
ap_skip:
                dec b
                ret z
ap_ch:
                ld a, (hl)
                inc hl
                or a
                jr nz, ap_ch
                jr ap_skip
