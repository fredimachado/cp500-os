; DE = dotted IPv4 string, HL = 4-byte output. Carry set on success.

parse_ip:
                ld b, 4
pi_oct:
                ld c, 0
pi_dig:
                ld a, (de)
                cp '0'
                jr c, pi_fail
                cp '9' + 1
                jr nc, pi_fail
                sub '0'
                push af
                ld a, c
                add a, a
                add a, a
                add a, c
                add a, a
                ld c, a
                pop af
                add a, c
                ld c, a
                inc de
                ld a, (de)
                cp '.'
                jr z, pi_dot
                or a
                jr z, pi_end
                jr pi_dig
pi_dot:
                ld a, c
                ld (hl), a
                inc hl
                inc de
                djnz pi_oct
                scf
                ret
pi_end:
                dec b
                jr nz, pi_fail
pi_last:
                ld a, c
                ld (hl), a
                scf
                ret
pi_fail:
                or a
                ret
