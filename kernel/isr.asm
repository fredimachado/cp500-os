; IM 1 timer. RETI does not ack this IRQ and does not set IFF1.

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
                pop hl
                pop de
                pop bc
                pop af
                ei
                reti
