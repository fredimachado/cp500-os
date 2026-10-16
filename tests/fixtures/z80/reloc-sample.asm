; Relocation fixture: assembled at ORIGIN 0000h, 0100h and 6200h. mkreloc must
; mark the high byte of every absolute address and nothing else, so relocating
; the 0000h link to page 62h reproduces the 6200h link.

    org ORIGIN

start:
    ld sp, stack_top
    ld hl, table
    ld b, (table_end - table) / 2
next:
    ld e, (hl)
    inc hl
    ld d, (hl)
    inc hl
    push hl
    call dispatch
    pop hl
    djnz next
    jr start                            ; relative: unchanged by relocation
dispatch:
    ex de, hl
    jp (hl)
first:
    ld a, (counter)
    inc a
    ld (counter), a
    jr nz, .done                        ; relative
    jp z, second
.done:
    ret
second:
    ld bc, 0100h                        ; a constant that looks like a page, not an address
    ld ix, counter
    ld (ix + 1), c
    ret

table:
    dw first, second, start
table_end:

counter:
    db 0, 0
stack:
    ds 32, 0
stack_top:
