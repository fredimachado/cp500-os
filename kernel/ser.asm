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
                assert $ <= SER_BASE + SER_PAGES * 256
