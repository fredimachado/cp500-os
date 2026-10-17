; /sys/keymap. The kernel loads it to KEYMAP at mount. In the key tables 0 is no key.

                include "cp500.inc"

                org KEYMAP

                db '@', 'a', 'b', 'c', 'd', 'e', 'f', 'g'
                db 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o'
                db 'p', 'q', 'r', 's', 't', 'u', 'v', 'w'
                db 'x', 'y', 'z', 0, 0, 0, 0, 0
                db '0', '1', '2', '3', '4', '5', '6', '7'
                db '8', '9', ':', ';', ',', '-', '.', '/'
                db 0Dh, K_CLEAR, K_BREAK, '[', K_DOWN, K_LEFT, K_RIGHT, ' '
                db 0, 0, 0, 0, 0, 0, 0, 0

                assert $ == KBD_SHIFTED
                db '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G'
                db 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O'
                db 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W'
                db 'X', 'Y', 'Z', 0, 0, 0, 0, 0
                db 0, '!', '"', '#', '$', '%', '&', "'"
                db '(', ')', '*', '+', '<', '=', '>', '?'
                db 0Dh, K_CLEAR, K_BREAK, 0, K_DOWN, K_LEFT, K_RIGHT, ' '
                db 0, 0, 0, 0, 0, 0, 0, 0

                assert $ == ACUTE_FROM
                db "aeiouAEIOUcC '"
                assert $ == ACUTE_TO
                db 0E1h, 0E9h, 0EDh, 0F3h, 0FAh, 0C1h, 0C9h, 0CDh, 0D3h, 0DAh, 0E7h, 0C7h, DEAD_ACUTE, DEAD_ACUTE

; Letters the character generator has no glyph for show their base letter;
; x and / stand in for D7h and F7h, ? for thorn.
                assert $ == LAT1_GLYPH
                db 41h, 41h, 05h, 0Fh, 0Eh, 41h, 41h, 1Eh, 45h, 1Ch, 45h, 45h, 49h, 49h, 49h, 49h
                db 44h, 10h, 4Fh, 4Fh, 4Fh, 13h, 07h, 78h, 08h, 55h, 55h, 55h, 04h, 59h, 3Fh, 14h
                db 19h, 1Ah, 0Ch, 61h, 18h, 61h, 61h, 63h, 65h, 03h, 65h, 65h, 69h, 69h, 69h, 69h
                db 64h, 0Ah, 6Fh, 6Fh, 6Fh, 16h, 11h, 2Fh, 12h, 09h, 75h, 75h, 15h, 79h, 3Fh, 79h

                assert $ - KEYMAP <= 255
