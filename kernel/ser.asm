; Serial driver loaded at SER_BASE from /sys/ser.

                include "kernel.sym"

                org SER_BASE

                jp ser_open
                jp ser_read
                jp ser_write
                jp ser_ioctl
                jp ser_close
                jp ser_revents
                jp ser_tick
                jp ser_irq
                jp ser_disk
                jp mask_out

                assert SEV_OPEN == SER_BASE
                assert SEV_READ == SER_BASE + 3
                assert SEV_WRITE == SER_BASE + 6
                assert SEV_IOCTL == SER_BASE + 9
                assert SEV_CLOSE == SER_BASE + 12
                assert SEV_REVENTS == SER_BASE + 15
                assert SEV_TICK == SER_BASE + 18
                assert SEV_IRQ == SER_BASE + 21
                assert SEV_DISK == SER_BASE + 24
                assert SEV_MASK == SER_BASE + 27

ser_body_start:
                include "ser_body.asm"
ser_body_end:
                assert $ <= EXT_OPEN
                ds EXT_OPEN - $, 0
                jp ext_open
                jp ext_go
                jp dev_boot
                jp dev_seek
                jp fd_route
                assert $ == FD_DRV
fd_drv:         ds 5, 0
                include "devextra.asm"
                assert $ <= SER_SC_BLOCK
                ds SER_SC_BLOCK - $, 0

; Bit 15 of T_ARG is armed. Spawn already zeroes that word. The other 15 bits
; are the start tick. A span of 8000h or more does not fit beside the flag.
sc_sleep:
                ld ix, (SC_FRAME)
                ld e, (ix + F_DE)
                ld d, (ix + F_DE + 1)
                ld a, d
                or e
                jr nz, sl_ticks
                ld hl, 0
                jp syscall_ok
sl_ticks:
                bit 7, d
                ld a, EINVAL
                jp nz, syscall_err
                call sl_slot
                inc hl
                bit 7, (hl)
                dec hl
                jr z, sl_arm
                push de
                ld e, (hl)
                inc hl
                ld d, (hl)
                res 7, d
                ld hl, (TICK_COUNT)
                res 7, h
                or a
                sbc hl, de
                ld a, h
                and 7Fh
                ld h, a
                pop de
                or a
                sbc hl, de
                jr c, sl_block
                call sl_slot
                ld (hl), 0
                inc hl
                ld (hl), 0
                ld hl, 0
                jp syscall_ok
sl_arm:
                ld bc, (TICK_COUNT)
                res 7, b
                set 7, b
                ld (hl), c
                inc hl
                ld (hl), b
sl_block:
                ld a, CH_SLEEP
                jp block_retry

sl_slot:
                ld a, (CUR)
                add a, a
                add a, T_ARG & 0FFh
                ld l, a
                ld h, T_ARG >> 8
                ret

sc_uptime:
                ld hl, TICK_COUNT
                ld bc, 4
                ldir
                ld hl, 0
                jp syscall_ok

sc_alloc:
                ld a, (CUR)
                or a
                ld a, EINVAL
                jp z, syscall_err
                ld a, d
                or e
                ld a, EINVAL
                jp z, syscall_err
                ld a, d
                or a
                ld a, ENOMEM
                jp nz, syscall_err
                push de
                call largest_run
                pop de
                ld a, ENOMEM
                jp c, syscall_err
                ld a, (RUN_END)
                ld hl, RUN_START
                sub (hl)
                cp e
                ld a, ENOMEM
                jp c, syscall_err
                ld a, (RUN_START)
                ld b, e
                ld c, a
                call owner_of
                ld a, (CUR)
al_stamp:
                ld (hl), a
                inc hl
                djnz al_stamp
                ld h, c
                ld l, 0
                jp syscall_ok

sc_free:
                ld a, e
                or a
                jp nz, fr_inval
                ld a, d
                cp ARENA_FIRST
                jp c, fr_inval
                cp ARENA_LAST + 1
                jp nc, fr_inval
                call owner_of
                ld a, (hl)
                ld c, a
                ld a, (CUR)
                cp c
                jp nz, fr_inval
                ld b, a
                ld c, b
                ld b, d
fr_one:
                ld a, (hl)
                cp c
                jr nz, fr_done
                ld (hl), 0
                inc b
                ld a, b
                cp ARENA_LAST + 1
                jr z, fr_done
                inc hl
                jr fr_one
fr_inval:
                ld a, EINVAL
                jp syscall_err
fr_done:
                ld hl, 0
                jp syscall_ok

sc_meminfo:
                push de
                ld hl, OWNER
                ld bc, 0
                ld d, ARENA_LAST - ARENA_FIRST + 1
mi_loop:
                ld a, (hl)
                inc hl
                or a
                jr nz, mi_skip
                inc bc
mi_skip:
                dec d
                jr nz, mi_loop
                push bc
                call largest_run
                pop bc
                pop hl
                jr nc, mi_run
                ld de, 0
                jr mi_write
mi_run:
                ld a, (RUN_END)
                push hl
                ld hl, RUN_START
                sub (hl)
                pop hl
                ld e, a
                ld d, 0
mi_write:
                ld (hl), c
                inc hl
                ld (hl), b
                inc hl
                ld (hl), e
                inc hl
                ld (hl), d
                inc hl
                ld (hl), ARENA_LAST - ARENA_FIRST + 1
                inc hl
                ld (hl), 0
                ld hl, 0
                jp syscall_ok

sc_dup2:
                ld a, e
                cp FD_SLOTS
                ld a, EBADF
                jp nc, syscall_err
                ld a, l
                cp FD_SLOTS
                ld a, EBADF
                jp nc, syscall_err
                ld a, h
                or a
                ld a, EBADF
                jp nz, syscall_err
                ld c, e
                ld b, l
                call fd_get
                jp c, syscall_err
                ld a, c
                cp b
                jp z, dp_ok
                ld a, b
                ld e, a
                ld d, 0
                ld hl, TASK + TASK_FD
                add hl, de
                call fd_drop
                ld a, c
                ld e, a
                ld d, 0
                ld hl, TASK + TASK_FD
                add hl, de
                ld a, (hl)
                ld e, b
                ld d, 0
                ld hl, TASK + TASK_FD
                add hl, de
                ld (hl), a
                call ofile_of
                inc hl
                inc (hl)
dp_ok:
                ld hl, 0
                jp syscall_ok

                assert $ <= SC_SLEEP
                ds SC_SLEEP - $, 0
                jp sc_sleep
                jp sc_uptime
                jp sc_alloc
                jp sc_free
                jp sc_meminfo
                jp sc_dup2
                assert $ == SC_DUP2 + 3
                assert $ <= SER_BASE + SER_PAGES * 256
