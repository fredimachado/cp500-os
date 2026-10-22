; cp500-os kernel. The first 256 bytes continue the boot load.

                include "cp500.inc"

; Zero-initialized kernel variables live in KPAGE, outside the 8 KiB image.
kv = KVARS
                MACRO kvar kv_label, kv_bytes
kv_label        equ kv
kv = kv + kv_bytes
                ENDM

                org KERNEL_BASE

                include "load.asm"
                include "init.asm"

                assert $ <= KERNEL_BASE + 256, "kernel loader exceeds one block"
                ds KERNEL_BASE + 256 - $, 0

kernel_main:
                di
                ld a, (ix + SB_SIDES)
                cp 1
                jr z, km_sides
                ld a, 2
km_sides:
                ld (VOL_SIDES), a
                ld a, (ix + SB_SPT)
                ld (VOL_SPT), a
                ld sp, BOOT_STACK_TOP
                call sys_init
                ei
                call c5fs_pick
                call nc, mt_apply
                push af
                call nc, load_sys
                ld hl, banner
                call console_puts
                xor a
                ld (CUR_PHASE), a
                ld (BLINK_DIV), a
                pop af
                jr c, km_mount
                xor a
                ld (KBUSY), a
                jp init_task
km_mount:
                ld a, 'M'
                ld (VIDEO_BASE + 15 * VIDEO_COLS), a
                di
                halt
                jr km_mount

banner:
                db 1Bh, "[2J"
                db 1Bh, "[H"
                db "cp500-os", 0Dh
                db 0

                include "sys.asm"
                include "task.asm"
                include "pipe.asm"
                include "isr.asm"
                include "keyboard.asm"
                include "console.asm"
                include "floppy.asm"
                include "c5fs.asm"

                assert $ <= 60FFh
                assert $ <= BLK_BUF
                ds ARENA_BASE - $, 0

                assert kv <= T_LIVE
