; Boot and task 0 support. Shares the first kernel block with the loader.

nmi:
                retn

; HL = start, BC = count - 1, A = byte.
fill:
                ld (hl), a
                ld d, h
                ld e, l
                inc de
                ldir
                ret

; A = kind, C = console. Fills the ofile at HL with one reference and steps HL.
init_ofile:
                ld (hl), a
                inc l
                ld (hl), 1
                inc l
                ld (hl), c
                ld de, OF_STRIDE - 2
                add hl, de
                ret

init_rec:       db 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 0FFh, 0FFh, 1, 0

; Task 0. Starts a shell for each console that wants one, else idles in HALT.
init_task:
                di
                ld a, (CON_WANT)
                or a
                jr nz, init_spawn
                ei
                halt
                jr init_task
init_spawn:
                ld hl, CON_WANT
                ld ix, 0
                bit 0, (hl)
                res 0, (hl)
                jr nz, init_go
                res 1, (hl)
                ld ix, init_map1
init_go:
                ei
                ld c, SYS_SPAWN
                ld de, shell_path
                ld hl, empty_argv
                rst 08h
                jr init_task

shell_path:     db "/bin/sh", 0
empty_argv:     db 0, 0
init_map1:      db 3, 4, 5, 0FFh, 0FFh, 0FFh, 0FFh, 0FFh
