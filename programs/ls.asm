; Names from readdir, in the section 7 folded order. ".." is included.

                include "cp500.inc"

                org ORIGIN

                ld (argv), hl
                ld a, 1
                call arg_ptr
                jr nc, ls_open
                ld hl, root
ls_open:
                ex de, hl
                ld c, SYS_OPEN
                ld b, O_READ
                rst 08h
                jp c, fail
                ld a, l
                ld (fd), a
                ld hl, 0
                ld (count), hl
ls_read:
                ld a, (count)
                cp 32
                jr z, ls_sort
                ld c, SYS_READDIR
                ld a, (fd)
                ld e, a
                ld d, 0
                ld hl, ent
                rst 08h
                jp c, fail
                ld a, h
                or l
                jr z, ls_sort
                ld hl, (count)
                add hl, hl
                add hl, hl
                add hl, hl
                add hl, hl
                add hl, hl
                ld de, names
                add hl, de
                ex de, hl
                ld hl, ent
                ld bc, 32
                ldir
                ld hl, (count)
                inc hl
                ld (count), hl
                jr ls_read

ls_sort:
                ld a, (count)
                cp 2
                jr c, ls_print
                dec a
                ld b, a
ls_pass:
                push bc
                ld c, 0
ls_pair:
                ld a, c
                call name_at
                push hl
                ld a, c
                inc a
                call name_at
                pop de
                call name_gt
                jr c, ls_swap
ls_next:
                inc c
                djnz ls_pair
                pop bc
                djnz ls_pass
                jr ls_print
ls_swap:
                push bc
                ld a, c
                call name_at
                ld de, ent
                ld bc, 32
                push hl
                ldir
                pop de
                ld hl, 32
                add hl, de
                ld bc, 32
                push hl
                ldir
                pop hl
                ld de, -32
                add hl, de
                ex de, hl
                ld hl, ent
                ld bc, 32
                ldir
                pop bc
                jr ls_next

ls_print:
                ld a, (count)
                or a
                jp z, exit0
                ld b, a
                ld c, 0
ls_line:
                push bc
                ld a, c
                call name_at
                inc hl
                inc hl
                call puts
                call cr
                pop bc
                inc c
                djnz ls_line
                jp exit0

; A = index. HL = name record.
name_at:
                ld l, a
                ld h, 0
                add hl, hl
                add hl, hl
                add hl, hl
                add hl, hl
                add hl, hl
                ld de, names
                add hl, de
                ret

; DE = left record, HL = right record. Carry when left > right.
name_gt:
                push bc
                inc de
                inc de
                inc hl
                inc hl
                ld b, 30
ng:
                ld a, (de)
                call fold
                ld c, a
                ld a, (hl)
                call fold
                cp c
                jr c, ng_yes
                jr nz, ng_no
                inc hl
                inc de
                djnz ng
ng_no:
                pop bc
                or a
                ret
ng_yes:
                pop bc
                scf
                ret

fold:
                cp 'A'
                ret c
                cp 'Z' + 1
                jr c, fold_add
                cp 0C0h
                ret c
                cp 0D7h
                ret z
                cp 0DFh
                ret nc
fold_add:
                add a, 20h
                ret

root:           db "/", 0
fd:             db 0
count:          dw 0
ent:            ds 32, 0

                include "run.inc"

names:
