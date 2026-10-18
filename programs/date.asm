; yyyy-MM-dd HH:mm:ss, seconds since 1980-01-01.
; No arguments prints the clock. Two arguments, the date and the time, set it.
; A no-argument run also stores the tick and the seconds at F7F0h for tests.

                include "cp500.inc"

SNAP            equ KPAGE_SNAP

                org ORIGIN

                ld (argv), hl
                ld a, (hl)
                cp 1
                jp z, show
                cp 3
                ld a, EINVAL
                jp nz, fail
                ld a, 1
                call arg_ptr
                ld a, EINVAL
                jp c, fail
                call parse_date
                jp c, fail
                ld a, 2
                call arg_ptr
                ld a, EINVAL
                jp c, fail
                call parse_hms
                jp c, fail
                call pack
                ld c, SYS_SETTIME
                ld de, t0
                rst 08h
                jp c, fail
show:
                ld hl, TICK_COUNT
                ld de, SNAP
                ld bc, 4
                ldir
                ld c, SYS_TIME
                ld de, t0
                rst 08h
                jp c, fail
                ld hl, t0
                ld de, SNAP + 4
                ld bc, 4
                ldir
                call unpack
                call emit
                jp exit0

parse_date:
                ld b, 4
                call digits
                ret c
                ld (year), de
                call dash
                ret c
                ld b, 2
                call digits
                ret c
                ld a, e
                or a
                jp z, bad
                cp 13
                jp nc, bad
                ld (month), a
                call dash
                ret c
                ld b, 2
                call digits
                ret c
                ld a, (hl)
                or a
                jp nz, bad
                ld a, e
                or a
                jp z, bad
                cp 32
                jp nc, bad
                ld (day), a
                or a
                ret

parse_hms:
                ld b, 2
                call digits
                ret c
                ld a, e
                cp 24
                jp nc, bad
                ld (hour), a
                call colon
                ret c
                ld b, 2
                call digits
                ret c
                ld a, e
                cp 60
                jp nc, bad
                ld (mins), a
                call colon
                ret c
                ld b, 2
                call digits
                ret c
                ld a, (hl)
                or a
                jp nz, bad
                ld a, e
                cp 60
                jp nc, bad
                ld (secs), a
                or a
                ret

dash:
                ld a, (hl)
                cp '-'
                jp nz, bad
                inc hl
                or a
                ret

colon:
                ld a, (hl)
                cp ':'
                jp nz, bad
                inc hl
                or a
                ret

; B digits. DE = value. HL advances.
digits:
                ld de, 0
dg:
                ld a, (hl)
                cp '0'
                jp c, bad
                cp '9' + 1
                jp nc, bad
                sub '0'
                push hl
                ld h, d
                ld l, e
                add hl, hl
                add hl, hl
                add hl, de
                add hl, hl
                ld e, a
                ld d, 0
                add hl, de
                ex de, hl
                pop hl
                inc hl
                djnz dg
                or a
                ret

bad:
                ld a, EINVAL
                scf
                ret

pack:
                ld hl, 0
                ld (days), hl
                ld hl, 1980
pk_y:
                ld de, (year)
                or a
                sbc hl, de
                jr z, pk_m
                add hl, de
                push hl
                call ylen
                ld de, (days)
                add hl, de
                ld (days), hl
                pop hl
                inc hl
                jr pk_y
pk_m:
                ld a, 1
pk_ml:
                ld hl, month
                cp (hl)
                jr z, pk_d
                push af
                call mlen
                ld e, a
                ld d, 0
                ld hl, (days)
                add hl, de
                ld (days), hl
                pop af
                inc a
                jr pk_ml
pk_d:
                ld a, (day)
                dec a
                ld e, a
                ld d, 0
                ld hl, (days)
                add hl, de
                ld (days), hl
                ld hl, 0
                ld (t0), hl
                ld (t0 + 2), hl
                ld bc, (days)
pk_mul:
                ld a, b
                or c
                jr z, pk_h
                dec bc
                ld hl, t0
                ld de, 86400 & 0FFFFh
                call add16
                ld hl, t0 + 2
                ld a, (hl)
                add a, 1
                ld (hl), a
                inc hl
                ld a, (hl)
                adc a, 0
                ld (hl), a
                jr pk_mul
pk_h:
                ld a, (hour)
                ld b, a
pk_hl:
                ld a, b
                or a
                jr z, pk_mi
                dec b
                ld hl, t0
                ld de, 3600
                call add16
                jr pk_hl
pk_mi:
                ld a, (mins)
                ld b, a
pk_mil:
                ld a, b
                or a
                jr z, pk_s
                dec b
                ld hl, t0
                ld de, 60
                call add16
                jr pk_mil
pk_s:
                ld a, (secs)
                ld e, a
                ld d, 0
                ld hl, t0
                jp add16

; HL = year. Returns HL = 365 or 366. Year kept by the caller.
ylen:
                ld a, l
                and 3
                ld hl, 365
                ret nz
                ld hl, 366
                ret

; A = month 1-12. A = length. Uses (year) for February.
mlen:
                cp 2
                jr nz, ml_tab
                ld hl, (year)
                ld a, l
                and 3
                ld a, 28
                ret nz
                ld a, 29
                ret
ml_tab:
                push af
                dec a
                ld hl, mdays
                ld e, a
                ld d, 0
                add hl, de
                ld a, (hl)
                pop bc
                ret

mdays:          db 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31

add16:
                ld a, (hl)
                add a, e
                ld (hl), a
                inc hl
                ld a, (hl)
                adc a, d
                ld (hl), a
                inc hl
                ld a, (hl)
                adc a, 0
                ld (hl), a
                inc hl
                ld a, (hl)
                adc a, 0
                ld (hl), a
                ret

unpack:
                ld hl, (t0)
                ld (rem), hl
                ld hl, (t0 + 2)
                ld (rem + 2), hl
                ld hl, 0
                ld (days), hl
un_d:
                call sub86400
                jr c, un_h0
                ld hl, (days)
                inc hl
                ld (days), hl
                jr un_d
un_h0:
                xor a
                ld (hour), a
un_h:
                call sub3600
                jr c, un_m0
                ld hl, hour
                inc (hl)
                jr un_h
un_m0:
                xor a
                ld (mins), a
un_m:
                call sub60
                jr c, un_s
                ld hl, mins
                inc (hl)
                jr un_m
un_s:
                ld a, (rem)
                ld (secs), a
                ld hl, 1980
un_y:
                push hl
                call ylen
                ld de, (days)
                or a
                sbc hl, de
                jr c, un_next
                jr z, un_next
                jr un_yin
un_next:
                pop hl
                push hl
                call ylen
                ld de, (days)
                ex de, hl
                or a
                sbc hl, de
                ld (days), hl
                pop hl
                inc hl
                jr un_y
un_yin:
                pop hl
                ld (year), hl
un_mo:
                ld a, 1
un_ml:
                push af
                call mlen
                ld b, a
                ld a, (days)
                ld e, a
                ld a, (days + 1)
                or a
                jr nz, un_sub
                ld a, e
                cp b
                jr c, un_day
un_sub:
                ld hl, (days)
                ld e, b
                ld d, 0
                or a
                sbc hl, de
                ld (days), hl
                pop af
                inc a
                jr un_ml
un_day:
                pop af
                ld (month), a
                ld a, (days)
                inc a
                ld (day), a
                ret

; Carry when rem < N, and rem is restored.
sub86400:
                ld hl, rem
                ld a, (hl)
                sub 80h
                ld (hl), a
                inc hl
                ld a, (hl)
                sbc a, 51h
                ld (hl), a
                inc hl
                ld a, (hl)
                sbc a, 01h
                ld (hl), a
                inc hl
                ld a, (hl)
                sbc a, 0
                ld (hl), a
                ret nc
                ld hl, rem
                ld a, (hl)
                add a, 80h
                ld (hl), a
                inc hl
                ld a, (hl)
                adc a, 51h
                ld (hl), a
                inc hl
                ld a, (hl)
                adc a, 01h
                ld (hl), a
                inc hl
                ld a, (hl)
                adc a, 0
                ld (hl), a
                scf
                ret

sub3600:
                ld de, 3600
                jr sub_small

sub60:
                ld de, 60
sub_small:
                ld hl, (rem + 2)
                ld a, h
                or l
                jr nz, ss_do
                ld hl, (rem)
                or a
                sbc hl, de
                jr c, ss_no
ss_do:
                ld hl, rem
                call sub16
                or a
                ret
ss_no:
                scf
                ret

sub16:
                ld a, (hl)
                sub e
                ld (hl), a
                inc hl
                ld a, (hl)
                sbc a, d
                ld (hl), a
                inc hl
                ld a, (hl)
                sbc a, 0
                ld (hl), a
                inc hl
                ld a, (hl)
                sbc a, 0
                ld (hl), a
                ret

emit:
                ld hl, (year)
                call dec4
                ld a, '-'
                call putc
                ld a, (month)
                call dec2
                ld a, '-'
                call putc
                ld a, (day)
                call dec2
                ld a, ' '
                call putc
                ld a, (hour)
                call dec2
                ld a, ':'
                call putc
                ld a, (mins)
                call dec2
                ld a, ':'
                call putc
                ld a, (secs)
                call dec2
                jp cr

dec2:
                ld l, a
                ld h, 0
                call div10
                push af
                ld a, l
                add a, '0'
                call putc
                pop af
                add a, '0'
                jp putc

dec4:
                call div10
                push af
                call div10
                push af
                call div10
                push af
                call div10
                add a, '0'
                call putc
                pop af
                add a, '0'
                call putc
                pop af
                add a, '0'
                call putc
                pop af
                add a, '0'
                jp putc

; HL / 10 -> HL quotient, A remainder.
div10:
                xor a
                ld c, 16
d10:
                add hl, hl
                rla
                cp 10
                jr c, d10n
                sub 10
                inc l
d10n:
                dec c
                jr nz, d10
                ret

year:           dw 0
month:          db 0
day:            db 0
hour:           db 0
mins:           db 0
secs:           db 0
days:           dw 0
t0:             ds 4, 0
rem:            ds 4, 0

                include "run.inc"
