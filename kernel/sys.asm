; System page jumps. The ROM enters here with interrupts still disabled.

sys_init:
                ld a, 0C3h
                ld (SYS_RST08), a
                ld hl, syscall_ret
                ld (SYS_RST08 + 1), hl
                ld a, 0C9h
                ld (SYS_RST10), a
                ld (SYS_RST18), a
                ld (SYS_RST20), a
                ld (SYS_RST28), a
                ld (SYS_RST30), a
                ld a, 0C3h
                ld (SYS_ISR), a
                ld hl, isr
                ld (SYS_ISR + 1), hl
                ld (SYS_NMI), a
                ld hl, nmi
                ld (SYS_NMI + 1), hl

                ld hl, TICK_COUNT
                ld (hl), 0
                ld de, TICK_COUNT + 1
                ld bc, 4048h - TICK_COUNT
                ldir
                ld hl, KBD_ACCEPTED
                ld (hl), 0
                ld de, KBD_ACCEPTED + 1
                ld bc, BLINK_DIV - KBD_ACCEPTED
                ldir
                ld a, 0FFh
                ld (KBD_REP_ROW), a

                call console_init
                in a, (PORT_TIMER_ACK)
                xor a
                out (PORT_NMI), a
                ld a, IRQ_TIMER
                out (PORT_IRQ), a
                ret

syscall_ret:
                ret

nmi:
                retn
