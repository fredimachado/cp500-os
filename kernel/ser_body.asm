ser_defaults:   db 0Eh, 8, 0, 1, CFG_F_RTSCTS, 0

                MACRO D2C rate_x2
                dw (2 * 24 * CPU_HZ) / (26 * rate_x2) + 1
                ENDM
delay2_table:
                D2C 100
                D2C 150
                D2C 220
                D2C 269
                D2C 300
                D2C 600
                D2C 1200
                D2C 2400
                D2C 3600
                D2C 4800
                D2C 7200
                D2C 9600
                D2C 14400
                D2C 19200
                D2C 38400

ser_open:
                ld a, (SER + S_PHASE)
                cp PH_OPEN
                jp z, dev_err_ebusy
                di
                ld a, (SER + S_PHASE)
                or a
                jr nz, so_gap
                ld a, (SER + S_GAP)
                or a
                jr z, so_probe
so_gap:
                ei
                ld a, CH_TICK
                jp block_retry
so_probe:
                ei
                xor a
                out (PORT_SER_RESET), a
                ld b, 4
so_flush:
                ; A byte the last session never read keeps DR set; drop it, or the probe fails.
                in a, (PORT_SER_DATA)
                djnz so_flush
                in a, (PORT_SER_STATUS)
                and SER_ST_DR | SER_ST_THRE
                cp SER_ST_THRE
                jp nz, dev_err_enodev
                call ring_take
                jp c, dev_err_enomem
                ld (SER + S_RXPG), a
                call ring_take
                jp c, so_give_rx
                ld (SER + S_TXPG), a
                ld a, KIND_SER
                ld (open_kind), a
                xor a
                ld (open_ino), a
                ld (open_ino + 1), a
                call fd_alloc
                jp c, so_free_rings
                push hl
                di
                xor a
                ld (SER + S_RXH), a
                ld (SER + S_RXT), a
                ld (SER + S_TXH), a
                ld (SER + S_TXT), a
                ld (SER + S_HI_SET), a
                ld (SER + S_HI_CLR), a
                ld (SER + S_ERR_SET), a
                ld (SER + S_ERR_SEEN), a
                ld (SER + S_BRK), a
                ld hl, ser_defaults
                ld de, SER + S_CFG
                ld bc, CFG_SIZE
                ldir
                ld hl, SER + S_STATS
                xor a
                ld b, STATS_SIZE
so_stat_z:
                ld (hl), a
                inc hl
                djnz so_stat_z
                in a, (PORT_SER_MODEM)
                bit SER_MS_DCD_BIT, a
                ld a, LN_DTR
                jr z, so_dcd
                or LN_DCD
so_dcd:
                ld (SER + S_LINE), a
                ld a, PH_OPEN
                ld (SER + S_PHASE), a
                call cfg_apply
                ei
                pop hl
                jp DEV_V_OK
so_give_rx:
                ld a, (SER + S_RXPG)
                call ring_give
dev_err_enomem:
                ld a, ENOMEM
                jp DEV_V_ERR
dev_err_enodev:
                ld a, ENODEV
                jp DEV_V_ERR
dev_err_ebusy:
                ld a, EBUSY
                jp DEV_V_ERR
so_free_rings:
                push af
                ld a, (SER + S_RXPG)
                call ring_give
                ld a, (SER + S_TXPG)
                call ring_give
                pop af
                jp DEV_V_ERR

ser_read:
                call io_empty
                ld hl, 0
                ld (io_got), hl
sr_loop:
                ei
                ; RXH = write head (ser_rx), RXT = read tail. Available = RXH - RXT.
                ; RXT in E; clamp copy count like ser_write (never sbc+ld b,l).
                ld a, (SER + S_RXT)
                ld e, a
                ld a, (SER + S_RXH)
                sub e
                jr z, sr_wait
                ld b, a
                ld hl, (io_len)
                ld a, h
                or a
                jr nz, sr_n
                ld a, l
                cp b
                jr nc, sr_n
                ld b, a
sr_n:
                ld a, (SER + S_RXPG)
                ld h, a
                ld l, e
                ld de, (io_buf)
                ld c, b
sr_copy:
                ld a, (hl)
                inc l
                ld (de), a
                inc de
                djnz sr_copy
                ld a, (SER + S_RXT)
                add a, c
                ld (SER + S_RXT), a
                ld b, 0
                ld hl, (io_buf)
                add hl, bc
                ld (io_buf), hl
                ld hl, (io_got)
                add hl, bc
                ld (io_got), hl
                ld hl, (io_len)
                or a
                sbc hl, bc
                ld (io_len), hl
                ; Raise RTS after high water once below low mark (do not block).
                ld a, (SER + S_HI_SET)
                ld c, a
                ld a, (SER + S_HI_CLR)
                cp c
                jr z, sr_hi
                ld a, (SER + S_RXH)
                ld hl, SER + S_RXT
                sub (hl)
                cp SER_RX_LOW + 1
                jr nc, sr_hi
                ld hl, SER + S_HI_CLR
                ld (hl), c
                di
                call ctl_out
sr_hi:
                di
                ld hl, (io_len)
                ld a, h
                or l
                jr z, sr_done
                ld a, (SER + S_RXH)
                ld hl, SER + S_RXT
                sub (hl)
                jr nz, sr_loop
sr_wait:
                call hung
                jr nz, sr_hung
                ld hl, (io_got)
                ld a, h
                or l
                ld a, CH_SER
                jp z, block_retry
                ld hl, 0
                ld (io_len), hl
                jp io_round
sr_hung:
                xor a
                jp DEV_V_RWSHORT
sr_done:
                ld a, CH_SER
                jp io_round

ser_write:
                call io_empty
                call hung
                jp nz, sw_hung
sw_loop:
                di
                ld a, (SER + S_TXH)
                ld e, a
                ld a, (SER + S_TXT)
                ld c, a
                ld a, e
                sub c
                ld c, a
                ld a, 255
                sub c
                or a
                jr z, sw_full
                ld b, a
                ei
                ld hl, (io_len)
                ld a, h
                or a
                jr nz, sw_take
                ld a, l
                cp b
                jr nc, sw_take
                ld b, a
sw_take:
                ld a, b
                or a
                jr z, sw_done
                ld a, (SER + S_TXPG)
                ld h, a
                ld l, e
                ld de, (io_buf)
                ld c, b
sw_copy:
                ld a, (de)
                inc de
                ld (hl), a
                inc l
                djnz sw_copy
                ld a, (SER + S_TXH)
                add a, c
                ld (SER + S_TXH), a
                ld b, 0
                ld hl, (io_buf)
                add hl, bc
                ld (io_buf), hl
                ld hl, (io_got)
                add hl, bc
                ld (io_got), hl
                ld hl, (io_len)
                or a
                sbc hl, bc
                ld (io_len), hl
                di
                call mask_out
                ld hl, (io_len)
                ld a, h
                or l
                jr nz, sw_loop
sw_done:
                ld a, CH_SER
                jp io_round
sw_full:
                ei
                ld a, CH_SER
                jp block_retry
sw_hung:
                ld a, EIO
                jp DEV_V_RWSHORT

ser_ioctl:
                ld a, b
                cp SER_CLASS
                jp nz, DEV_V_EINVAL
                ld a, c
                cp SER_GETCFG & 0ffh
                jp z, si_getcfg
                cp SER_SETCFG & 0ffh
                jp z, si_setcfg
                cp SER_GETLINES & 0ffh
                jp z, si_lines
                cp SER_SETDTR & 0ffh
                jp z, si_dtr
                cp SER_BREAK & 0ffh
                jp z, si_break
                cp SER_STATS & 0ffh
                jp z, si_stats
                jp DEV_V_EINVAL
si_getcfg:
                ld hl, SER + S_CFG
                push ix
                pop de
                ld bc, CFG_SIZE
                ldir
                xor a
                ld hl, 0
                jp DEV_V_OK
si_setcfg:
                call cfg_check
                jp c, DEV_V_EINVAL
                di
                ld a, (SER + S_TXH)
                ld hl, SER + S_TXT
                cp (hl)
                jr z, si_set_go
                ei
                ld a, CH_SER
                jp block_retry
si_set_go:
                ld hl, ix
                ld de, SER + S_CFG
                ld bc, CFG_SIZE
                ldir
                call cfg_apply
                ei
                xor a
                ld hl, 0
                jp DEV_V_OK
si_lines:
                call lines_now
                jp DEV_V_OK
si_dtr:
                ld a, (ix + 0)
                or a
                jr z, si_dtr0
                ld a, (ix + 1)
                dec a
                jp nz, DEV_V_EINVAL
                di
                ld a, (SER + S_GAP)
                or a
                jr nz, si_dtr_wait
                ld a, (SER + S_LINE)
                or LN_DTR
                ld (SER + S_LINE), a
                call ctl_out
                ei
                xor a
                ld hl, 0
                jp DEV_V_OK
si_dtr_wait:
                ei
                ld a, CH_TICK
                jp block_retry
si_dtr0:
                di
                ld a, (SER + S_LINE)
                bit 0, a
                jr z, si_dtr_done
                res 0, a
                ld (SER + S_LINE), a
                ld a, DTR_GAP_TICKS
                ld (SER + S_GAP), a
                call ctl_out
si_dtr_done:
                ei
                xor a
                ld hl, 0
                jp DEV_V_OK
si_break:
                ld a, (ix + 0)
                dec a
                cp BREAK_MAX
                jp nc, DEV_V_EINVAL
                ld b, a
                inc b
                ld a, (CUR)
                add a, a
                add a, T_ARG & 0FFh
                ld l, a
                ld h, T_ARG >> 8
                ld a, (hl)
                or a
                jr nz, si_brk_wait
                di
                ld hl, SER + S_BRK
                ld (hl), b
                call ctl_out
                call mask_out
                ld a, 1
                ld (hl), a
                ei
                ld a, CH_TICK
                jp block_retry
si_brk_wait:
                di
                ld a, (SER + S_BRK)
                or a
                jr nz, si_brk_wait2
                ei
                xor a
                ld hl, 0
                jp DEV_V_OK
si_brk_wait2:
                ei
                ld a, CH_TICK
                jp block_retry
si_stats:
                di
                ld hl, SER + S_STATS
                push ix
                pop de
                ld bc, STATS_SIZE
                ldir
                ld hl, SER + S_STATS
                xor a
                ld b, STATS_SIZE
si_stz:
                ld (hl), a
                inc hl
                djnz si_stz
                ei
                xor a
                ld hl, 0
                jp DEV_V_OK

ser_close:
                ld a, (SER + S_PHASE)
                cp PH_OPEN
                ret nz
                ld a, i
                push af
                di
                ld a, PH_LINGER
                ld (SER + S_PHASE), a
                ld a, LINGER_TICKS
                ld (SER + S_LINGER), a
                xor a
                ld (SER + S_BRK), a
                call ctl_out
                call mask_out
                pop af
                ret po
                ei
                ret

ser_revents:
                xor a
                ld c, a
                ld a, (SER + S_RXH)
                ld hl, SER + S_RXT
                sub (hl)
                jr z, sr_ev1
                ld c, POLLIN
sr_ev1:
                call hung
                jr z, sr_ev_tx
                ld a, c
                or POLLHUP
                ld c, a
                jr sr_ev3
sr_ev_tx:
                ld a, (SER + S_TXH)
                ld hl, SER + S_TXT
                sub (hl)
                cp 255
                jr z, sr_ev3
                ld a, c
                or POLLOUT
                ld c, a
sr_ev3:
                ld a, (SER + S_ERR_SET)
                ld b, a
                ld a, (SER + S_ERR_SEEN)
                cp b
                jr z, sr_ev4
                ld hl, SER + S_ERR_SEEN
                ld (hl), b
                ld a, c
                or POLLERR
                ld c, a
sr_ev4:
                ld a, c
                ret

ser_irq:
                bit IRQ_SER_RX_BIT, a
                jr nz, si_done
                push af
                call ser_rx
                pop af
si_done:
                bit IRQ_SER_TX_BIT, a
                ret nz
                jp ser_tx

ser_rx:
                in a, (PORT_SER_STATUS)
                bit SER_ST_DR_BIT, a
                ret z
                ld b, a
                in a, (PORT_SER_DATA)
                ld c, a
                bit SER_ST_OE_BIT, b
                call nz, stat_inc0
                bit SER_ST_FE_BIT, b
                call nz, stat_inc1
                bit SER_ST_PE_BIT, b
                call nz, stat_inc2
                ld a, (SER + S_RXH)
                ld hl, SER + S_RXT
                sub (hl)
                cp 255
                jr z, srx_drop
                ld a, (SER + S_RXPG)
                ld h, a
                ld a, (SER + S_RXH)
                ld l, a
                ld (hl), c
                ld a, (SER + S_RXH)
                ld b, a
                inc a
                ld (SER + S_RXH), a
                ld a, b
                ld hl, SER + S_RXT
                sub (hl)
                jr nz, srx_wake
                ld a, CH_SER
                call wake
srx_wake:
                ld a, (SER + S_CFG + CFG_FLAGS)
                and CFG_F_RTSCTS
                jr z, srx_ret
                ld a, (SER + S_RXH)
                ld hl, SER + S_RXT
                sub (hl)
                cp SER_RX_HIGH
                jr c, srx_ret
                ld a, (SER + S_HI_SET)
                ld b, a
                ld a, (SER + S_HI_CLR)
                cp b
                jr nz, srx_ret
                inc a
                ld (SER + S_HI_SET), a
                call ctl_out
srx_ret:
                ret
srx_drop:
                call err_bump
                call stat_inc3
                ret

ser_tx:
                ld a, (SER + S_TXH)
                ld hl, SER + S_TXT
                cp (hl)
                jr z, st_empty
                ld a, (SER + S_BRK)
                or a
                jr nz, st_empty
                ld a, (SER + S_CFG + CFG_FLAGS)
                and CFG_F_RTSCTS
                jr z, st_send
                in a, (PORT_SER_MODEM)
                bit SER_MS_CTS_BIT, a
                jr z, st_empty
st_send:
                ld a, (SER + S_TXPG)
                ld h, a
                ld a, (SER + S_TXT)
                ld l, a
                ld a, (hl)
                out (PORT_SER_DATA), a
                ld hl, SER + S_TXT
                inc (hl)
                ld a, (SER + S_TXH)
                sub (hl)
                cp SER_TX_WAKE
                jr nz, st_w0
                ld a, CH_SER
                call wake
                jr st_mask
st_w0:
                or a
                jr nz, st_mask
                ld a, CH_SER
                call wake
st_mask:
                call mask_out
                ret
st_empty:
                call mask_out
                ret

ser_tick:
                ld a, (SER + S_GAP)
                or a
                jr z, st_ph
                dec a
                ld (SER + S_GAP), a
st_ph:
                ld a, (SER + S_PHASE)
                or a
                ret z
                ld a, (SER + S_BRK)
                or a
                jr z, st_brk
                dec a
                ld (SER + S_BRK), a
                jr nz, st_brk
                call ctl_out
                call mask_out
st_brk:
                ld a, (SER + S_PHASE)
                cp PH_LINGER
                jr nz, st_open
                ld a, (SER + S_LINGER)
                dec a
                ld (SER + S_LINGER), a
                jr z, st_drop
                ld a, (SER + S_TXH)
                ld hl, SER + S_TXT
                cp (hl)
                jr nz, st_lmask
                ld a, 1
                ld (SER + S_LINGER), a
st_lmask:
                call mask_out
                ret
st_drop:
                jp ser_drop
st_open:
                in a, (PORT_SER_MODEM)
                bit SER_MS_DCD_BIT, a
                jr nz, st_dcd_rise
                ld a, (SER + S_LINE)
                bit 3, a
                jr z, st_cts
                res 3, a
                ld (SER + S_LINE), a
                ld a, (SER + S_CFG + CFG_FLAGS)
                and CFG_F_DCD
                jr z, st_cts
                ld a, (SER + S_LINE)
                or LN_HUNG
                ld (SER + S_LINE), a
                ld a, CH_SER
                call wake
                jr st_cts
st_dcd_rise:
                ld a, (SER + S_LINE)
                bit 3, a
                jr nz, st_cts
                res 2, a
                or LN_DCD
                ld (SER + S_LINE), a
st_cts:
                ld a, (SER + S_TXH)
                ld hl, SER + S_TXT
                cp (hl)
                ret z
                call mask_out
                ret

ser_drop:
                di
                ld a, PH_CLOSED
                ld (SER + S_PHASE), a
                ld a, (SER + S_LINE)
                and ~LN_DTR
                ld (SER + S_LINE), a
                call mask_out
                call ctl_out
                ld a, DTR_GAP_TICKS
                ld (SER + S_GAP), a
                ld a, (SER + S_RXPG)
                call ring_give
                ld a, (SER + S_TXPG)
                call ring_give
                xor a
                ld (SER + S_RXPG), a
                ld (SER + S_TXPG), a
                ret

mask_out:
                ld a, IRQ_TIMER
                ld b, a
                ld a, (SER + S_PHASE)
                cp PH_OPEN
                jr nz, mo_tx
                ld a, b
                or IRQ_SER_RX
                ld b, a
mo_tx:
                ld a, (SER + S_PHASE)
                cp PH_CLOSED
                jr z, mo_out
                ld a, (SER + S_TXH)
                ld hl, SER + S_TXT
                cp (hl)
                jr z, mo_out
                ld a, (SER + S_BRK)
                or a
                jr nz, mo_out
                ld a, (SER + S_CFG + CFG_FLAGS)
                and CFG_F_RTSCTS
                jr z, mo_en_tx
                in a, (PORT_SER_MODEM)
                bit SER_MS_CTS_BIT, a
                jr z, mo_out
mo_en_tx:
                ld a, b
                or IRQ_SER_TX
                ld b, a
mo_out:
                ld a, b
                out (PORT_IRQ), a
                ret

ctl_out:
                call cfg_bits
                ld b, a
                ld a, (SER + S_LINE)
                bit 0, a
                jr z, co_dtr
                ld a, b
                or SER_CT_DTR
                ld b, a
co_dtr:
                ld a, (SER + S_PHASE)
                cp PH_OPEN
                jr nz, co_brk
                ld a, (SER + S_LINE)
                bit 1, a
                jr nz, co_brk
                ld a, (SER + S_CFG + CFG_FLAGS)
                and CFG_F_RTSCTS
                jr z, co_rts
                ld a, (SER + S_HI_SET)
                ld c, a
                ld a, (SER + S_HI_CLR)
                cp c
                jr nz, co_brk
co_rts:
                ld a, b
                or SER_CT_RTS
                ld b, a
co_brk:
                ld a, (SER + S_BRK)
                or a
                jr z, co_out
                ; Bit 2 is active-low: clear it to hold TX in break.
                ld a, b
                and 0FFh - SER_CT_BREAK
                ld b, a
co_out:
                ld a, SER_CTL_LOAD
                out (PORT_SER_MODEM), a
                ld a, b
                out (PORT_SER_CTL), a
                ret

cfg_apply:
                ld a, (SER + S_CFG + CFG_BAUD)
                ld c, a
                ld b, a
                add a, a
                add a, a
                add a, a
                add a, a
                or b
                out (PORT_SER_BAUD), a
                ld l, c
                ld h, 0
                add hl, hl
                ld de, delay2_table
                add hl, de
                ld e, (hl)
                inc hl
                ld d, (hl)
                ld (SER + S_DELAY), de
                call ctl_out
                call mask_out
                ret

cfg_check:
                push ix
                pop hl
                ld a, (hl)
                inc hl
                cp 10h
                jr nc, cfg_bad
                ld a, (hl)
                inc hl
                cp 5
                jr c, cfg_bad
                cp 9
                jr nc, cfg_bad
                ld a, (hl)
                inc hl
                cp 3
                jr nc, cfg_bad
                ld a, (hl)
                inc hl
                dec a
                cp 2
                jr nc, cfg_bad
                ld a, (hl)
                inc hl
                and 0FCh
                jr nz, cfg_bad
                ld a, (hl)
                or a
                ret z
cfg_bad:
                scf
                ret

cfg_bits:
                ld a, (SER + S_CFG + CFG_DATA)
                sub 5
                ld b, SER_CT_WLEN_SHIFT
cb_shift:
                add a, a
                djnz cb_shift
                ld c, a
                ld a, (SER + S_CFG + CFG_STOP)
                dec a
                jr z, cb_parity
                ld a, c
                or SER_CT_STOP2
                ld c, a
cb_parity:
                ld a, (SER + S_CFG + CFG_PARITY)
                or a
                jr z, cb_none
                dec a
                jr z, cb_done
                ld a, c
                or SER_CT_EVEN
                ld c, a
                jr cb_done
cb_none:
                ld a, c
                or SER_CT_NOPARITY
                ld c, a
cb_done:
                ld a, c
                ; Bit 2 is active-low: set it so break is off (matches ResetControl 6Ch).
                or SER_CT_BREAK
                ret

lines_now:
                in a, (PORT_SER_MODEM)
                ld c, a
                xor a
                bit SER_MS_CTS_BIT, c
                jr z, ln0
                or 1
ln0:
                bit SER_MS_DSR_BIT, c
                jr z, ln1
                or 2
ln1:
                bit SER_MS_DCD_BIT, c
                jr z, ln2
                or 4
ln2:
                bit SER_MS_RI_BIT, c
                jr z, ln3
                or 8
ln3:
                ld h, 0
                ld l, a
                ret

hung:
                ld a, (SER + S_LINE)
                and LN_HUNG
                ret z
                ld a, (SER + S_CFG + CFG_FLAGS)
                and CFG_F_DCD
                ret

ring_take:
                call largest_run
                ret c
                ld a, (RUN_END)
                dec a
                push af
                call owner_of
                ld (hl), 0FFh
                pop af
                ret

ring_give:
                call owner_of
                ld (hl), 0
                ret

ser_disk:
                pop hl
                pop de
                pop af
                push af
                push de
                push hl
                ld a, (KBUSY)
                dec a
                jr nz, sd_ret
                ld a, (SER + S_PHASE)
                cp PH_OPEN
                jr nz, sd_ret
                ld a, (SER + S_CFG + CFG_FLAGS)
                and CFG_F_RTSCTS
                jr z, sd_ret
                ld a, i
                jp po, sd_ret
                di
                ld a, (SER + S_LINE)
                or LN_DISK
                ld (SER + S_LINE), a
                call ctl_out
                ei
                call delay2
                pop af
                pop hl
                ld de, ser_disk_post
                push de
                push hl
                ret
sd_ret:
                pop hl
                pop de
                pop af
                ret

ser_disk_post:
                push af
                di
                ld a, (SER + S_LINE)
                and ~LN_DISK
                ld (SER + S_LINE), a
                call ctl_out
                ei
                pop af
                ret

delay2:
                ld hl, (SER + S_DELAY)
                ld bc, hl
d2_loop:
                dec bc
                ld a, b
                or c
                jr nz, d2_loop
                ret

stat_inc0:
                ld hl, SER + S_STATS
                call inc16
                ret
stat_inc1:
                ld hl, SER + S_STATS + 2
                call inc16
                ret
stat_inc2:
                ld hl, SER + S_STATS + 4
                call inc16
                ret
stat_inc3:
                ld hl, SER + S_STATS + 6
                call inc16
                ret
err_bump:
                ld hl, SER + S_ERR_SET
                inc (hl)
                ret
inc16:
                inc (hl)
                ret nz
                inc hl
                inc (hl)
                ret
