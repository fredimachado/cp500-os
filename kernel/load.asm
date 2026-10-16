; First kernel block. The boot sector loaded this page to 4200h and left IX
; pointing at the winning superblock. The rest of the image follows on disk.

                ld e, (ix + SB_KERNEL_START)
                ld d, (ix + SB_KERNEL_START + 1)
                inc de
                ld a, (ix + SB_KERNEL_COUNT)
                dec a
                jr z, kernel_enter
                ld b, a
                ld a, (ix + SB_SIDES)
                ld i, a
                ld a, (ix + SB_SPT)
                ex af, af'
                ld hl, KERNEL_BASE + 256

load_more:
                push bc
                push de
                push hl
                call load_block
                pop hl
                inc h
                pop de
                inc de
                pop bc
                djnz load_more

kernel_enter:
                jp kernel_main

; DE = block number, HL = destination. Sides are in I, sectors per track in A'.
load_block:
                push hl
                ld h, d
                ld l, e
                ex af, af'
                ld b, a
                ex af, af'
                ld d, 0
load_div:
                ld a, l
                sub b
                ld e, a
                ld a, h
                sbc a, 0
                jr c, load_rem
                ld h, a
                ld l, e
                inc d
                jr load_div
load_rem:
                ld a, l
                inc a
                ld e, a
                ld a, i
                dec a
                jr z, load_side0
                ld a, d
                and 1
                ld c, a
                srl d
                jr load_read
load_side0:
                ld c, 0
load_read:
                pop hl
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
load_poll:
                in a, (FDC_STATUS)
                rrca
                jr nc, load_disk
                rrca
                jr nc, load_poll
                ini
                jr nz, load_poll
                ret

load_disk:
                ld a, 'D'
                ld (VIDEO_BASE), a
                halt
