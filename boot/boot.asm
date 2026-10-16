; CP-500 boot sector. The ROM has finished reading track 0 sector 1.
; The body runs at FF00h. It chooses a superblock and loads one kernel
; block to 4200h. That block loads the rest; a full run does not fit here.
; The divide uses the low byte of the kernel start, so that block is below 256.

        include "cp500.inc"

        org BOOT_SECTOR

        di
        ld sp, BOOT_STACK_TOP
        ld hl, BOOT_SECTOR
        ld de, BOOT_HIGH
        ld bc, BOOT_SECTOR_SIZE
        ldir
        jp BOOT_HIGH + (main - BOOT_SECTOR)

main:
        phase BOOT_HIGH + (main - BOOT_SECTOR)

        ld de, 2
        ld c, d
        ld hl, SB_A
        call read
        inc e
        ld c, d
        ld hl, SB_B
        call read

        ld hl, SB_A
        call good
        jr nc, only_b
        ld hl, SB_B
        call good
        jr nc, use_a
        ld hl, SB_A + SB_SEQ + 3
        ld de, SB_B + SB_SEQ + 3
        ld b, 4
seq:
        ld a, (de)
        cp (hl)
        jr nz, seq_diff
        dec hl
        dec de
        djnz seq
use_a:
        ld hl, SB_A
        jr got
seq_diff:
        jr c, use_a
only_b:
        ld hl, SB_B
        call good
        jr nc, halt_s
got:
        push hl
        pop ix
        ld d, (ix + SB_SIDES)
        ld c, (ix + SB_SPT)
        ld l, (ix + SB_KERNEL_START)
        ld a, (ix + SB_KERNEL_COUNT)
        or a
        jr z, halt_k
        ld e, 0
div:
        ld a, l
        sub c
        jr c, rem
        ld l, a
        inc e
        jr div
rem:
        ld a, l
        inc a
        ex af, af'
        ld a, d
        dec a
        jr z, one
        ld a, e
        and 1
        ld c, a
        srl e
        jr track
one:
        ld c, 0
track:
        ld d, e
        ex af, af'
        ld e, a
        ld hl, KERNEL_BASE
        call read
        jp KERNEL_BASE

halt_s:
        ld a, 'S'
        .db 01h
halt_k:
        ld a, 'K'
        .db 01h
halt_d:
        ld a, 'D'
        ld (VIDEO_BASE), a
        halt

; HL = superblock. Carry set when the magic and the CRC match. HL is kept.
good:
        push hl
        ld de, magic
        ld b, 4
magic_cmp:
        ld a, (de)
        cp (hl)
        jr nz, bad
        inc de
        inc hl
        djnz magic_cmp
        pop hl
        push hl
        ld d, h
        ld e, l
        ld hl, 0FFFFh
        ld b, 254
crc_byte:
        ld a, (de)
        inc de
        xor h
        ld h, a
        ld c, 8
crc_bit:
        add hl, hl
        jr nc, crc_next
        ld a, h
        xor 10h
        ld h, a
        ld a, l
        xor 21h
        ld l, a
crc_next:
        dec c
        jr nz, crc_bit
        djnz crc_byte
        ld a, (de)
        cp l
        inc de
        jr nz, bad
        ld a, (de)
        cp h
        jr nz, bad
        pop hl
        scf
        ret
bad:
        pop hl
        or a
        ret

magic:
        db "C5FS"

; D = track, E = sector, C = side. HL advances by 256. D and E are kept.
read:
        ld a, c
        add a, a
        add a, a
        add a, a
        add a, a
        or DISK_DRIVE0 | DISK_MFM
        out (PORT_DISK), a
        ld a, d
        out (FDC_DATA), a
        ld a, FDC_CMD_SEEK | FDC_HEAD_LOAD | FDC_STEP_30MS
        out (FDC_COMMAND), a
        ld a, e
        out (FDC_SECTOR), a
        ld a, FDC_CMD_READ
        out (FDC_COMMAND), a
        ld bc, FDC_DATA
poll:
        in a, (FDC_STATUS)
        rrca
        jr nc, halt_d
        rrca
        jr nc, poll
        ini
        jr nz, poll
        ret

        dephase

        assert $ - BOOT_SECTOR <= BOOT_SECTOR_SIZE, "boot sector is larger than one sector"
