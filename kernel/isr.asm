; IM 1 timer. RETI does not ack this IRQ and does not set IFF1.
; During a call it only counts the quantum down; QUANTUM at 0 makes the call
; switch on its way back to user code.

isr:
                push af
                push bc
                push de
                push hl
                in a, (PORT_TIMER_ACK)
                ld hl, TICK_COUNT
                inc (hl)
                jr nz, isr_scanned
                inc hl
                inc (hl)
                jr nz, isr_scanned
                inc hl
                inc (hl)
                jr nz, isr_scanned
                inc hl
                inc (hl)
isr_scanned:
                call kbd_scan
                call console_blink
                ld a, (KBD_TAIL)
                ld hl, KBD_HEAD
                cp (hl)
                ld a, CH_KEY
                call nz, wake
                ld hl, QUANTUM
                ld a, (hl)
                or a
                jr z, isr_due
                dec (hl)
isr_due:
                ld a, (KBUSY)
                or a
                jr nz, isr_return
                ld a, (hl)
                or a
                jr z, isr_switch
                ld a, (CUR)
                or a
                jr z, isr_switch
                call t_state_a
                ld a, (hl)
                dec a
                jr z, isr_return
isr_switch:
                push ix
                push iy
                ex af, af'
                exx
                push af
                push bc
                push de
                push hl
                jp sched_save
isr_return:
                pop hl
                pop de
                pop bc
                pop af
                ei
                reti
