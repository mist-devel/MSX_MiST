; systest.asm - MSX2 MiST system test, runs as MAIN-ROM (slot 0, 0000h)
; results are written to C000h+n (mapper segment 0 = SDRAM 0x0000000)
    IFDEF MSX1T
        output "systest_msx1.bin"
    ELSE
        output "systest_main.bin"
    ENDIF
        org 0
        di
        ld a,0C0h               ; page 3 = slot 3, pages 0-2 = slot 0
        out (0A8h),a
        ld a,0AAh
        ld (0FFFFh),a           ; slot 3: every page -> 3-2 (memory mapper)
        ld a,3
        out (0FCh),a
        ld a,2
        out (0FDh),a
        ld a,1
        out (0FEh),a
        xor a
        out (0FFh),a
        ld sp,0F000h
        ld ix,0C000h
        ld (ix+0),11h           ; [00] started

        ; [01] RAM read back
        ld a,5Ah
        ld (0C100h),a
        ld a,(0C100h)
        ld (ix+1),a

        ; mapper: page 2 = slot 3-2
        ld a,0F0h
        out (0A8h),a
        ld a,5
        out (0FEh),a
        ld a,55h
        ld (8000h),a
        ld a,6
        out (0FEh),a
        ld a,66h
        ld (8000h),a
        ld a,5
        out (0FEh),a
        ld a,(8000h)
        ld (ix+2),a             ; [02] = 55
        ld a,6
        out (0FEh),a
        ld a,(8000h)
        ld (ix+3),a             ; [03] = 66
        in a,(0FEh)
        ld (ix+4),a             ; [04] = 06 | ~mask
        ld a,1
        out (0FEh),a
        ld a,0C0h
        out (0A8h),a

        ; copy the RAM routines to D000h
        ld hl,ramcode
        ld de,0D000h
        ld bc,ramcode_end-ramcode
        ldir

        call 0D000h + (rd_sub - ramcode)
        ld (ix+5),b             ; [05] 'C'
        ld (ix+6),c             ; [06] 'D'

        call 0D000h + (rd_disk - ramcode)
        ld (ix+7),b             ; [07] 'A'  disk ROM
        ld (ix+8),c             ; [08] 'B'
        ld (ix+9),d             ; [09] FDC sector register read back (05)
        ld (ix+10),e            ; [0A] 7FFF (status: /DRQ /INTRQ)
    IFDEF MSX1T
        ; MSX1: slot 3 is not expanded, FFFFh is a normal RAM byte
        ld a,5Ah
        ld (0FFFFh),a
        ld a,(0FFFFh)
        ld (ix+15),a            ; [0F] = 5A
        ld a,0AAh
        ld (0FFFFh),a
    ELSE
        ld a,(0FFFFh)
        ld (ix+15),a            ; [0F] = 55 (inverted secondary slot register)
    ENDIF

        call 0D000h + (rd_cart1 - ramcode)   ; results in C010-C01F
        call 0D000h + (rd_cart2 - ramcode)   ; results in C020-C02F

        ; PSG port A: bit 7 = cassette input
        ld a,15
        out (0A0h),a
        ld a,0
        out (0A1h),a
        ld a,14
        out (0A0h),a
        in a,(0A2h)
        ld (ix+11),a            ; [0B] PSG port A
        ; cassette motor on
        ld a,08h
        out (0ABh),a
        in a,(0AAh)
        ld (ix+12),a            ; [0C] PPI port C
        ; VDP status
        in a,(099h)
        ld (ix+13),a            ; [0D]
        ld a,1
        out (099h),a
        ld a,08Fh
        out (099h),a
        in a,(099h)
        ld (ix+14),a            ; [0E] VDP S#1 (ID)
        xor a
        out (099h),a
        ld a,08Fh
        out (099h),a

        ld a,0A5h
        ld (0C0FFh),a           ; done
loop:   jr loop

; ---------------------------------------------------------------------------
ramcode:
; B,C = first 2 bytes of the SUB-ROM (slot 3-1, 0000h)
rd_sub:
        in a,(0A8h)
        push af
        ld a,0F3h               ; page0 = slot 3, page1 = slot 0, page2/3 = slot 3
        out (0A8h),a
        ld a,0A9h               ; page0 -> 3-1, pages 1-3 -> 3-2
        ld (0FFFFh),a
        ld a,(0000h)
        ld b,a
        ld a,(0001h)
        ld c,a
        ld a,0AAh               ; back to 3-2 everywhere
        ld (0FFFFh),a
        pop af
        out (0A8h),a
        ret

; B,C = first bytes of the DISK-ROM (3-3, 4000h), D = FDC sector reg, E = 7FFF
rd_disk:
        in a,(0A8h)
        push af
    IFDEF MSX1T
        ld a,0F8h               ; MSX1: page1 = slot 2 (disk interface, no cartridge)
        out (0A8h),a
    ELSE
        ld a,0FCh               ; page1 = slot 3
        out (0A8h),a
        ld a,0AEh               ; page1 -> 3-3, the others -> 3-2
        ld (0FFFFh),a
    ENDIF
        ld a,(4000h)
        ld b,a
        ld a,(4001h)
        ld c,a
        ld a,05h
        ld (7FFAh),a
        ld a,(7FFAh)
        ld d,a
        ld a,(7FFFh)
        ld e,a
    IFNDEF MSX1T
        ld a,0AAh               ; back to 3-2 everywhere
        ld (0FFFFh),a
    ENDIF
        pop af
        out (0A8h),a
        ret

; slot 1: Konami SCC cartridge (bank number at offset 10h of each 8K bank)
rd_cart1:
        in a,(0A8h)
        push af
        ld a,0D4h               ; page1/2 = slot 1
        out (0A8h),a
        ld a,(4000h)
        ld (ix+10h),a           ; 'A'
        ld a,(4010h)
        ld (ix+11h),a           ; 0
        ld a,(6010h)
        ld (ix+12h),a           ; 1
        ld a,(8010h)
        ld (ix+13h),a           ; 2
        ld a,(0A010h)
        ld (ix+14h),a           ; 3
        ld a,7
        ld (7000h),a
        ld a,(6010h)
        ld (ix+15h),a           ; 7
        ld a,8
        ld (9000h),a
        ld a,(8010h)
        ld (ix+16h),a           ; 8
        ld a,4
        ld (5000h),a
        ld a,(4010h)
        ld (ix+17h),a           ; 4
        ld a,3Fh                ; SCC on
        ld (9000h),a
        ld a,12h
        ld (9800h),a
        ld a,34h
        ld (9801h),a
        ld a,(9800h)
        ld (ix+18h),a           ; 12
        ld a,(9801h)
        ld (ix+19h),a           ; 34
        ld a,2
        ld (9000h),a
        ld a,(8010h)
        ld (ix+1Ah),a           ; 2
        pop af
        out (0A8h),a
        ret

; slot 2: ASCII 16K cartridge (80h+bank at offset 10h of each 16K bank)
rd_cart2:
        in a,(0A8h)
        push af
        ld a,0E8h               ; page1/2 = slot 2
        out (0A8h),a
        ld a,(4001h)
        ld (ix+20h),a           ; 'B'
        ld a,(4010h)
        ld (ix+21h),a           ; 80
        ld a,(8010h)
        ld (ix+22h),a           ; 80
        ld a,3
        ld (6000h),a
        ld a,(4010h)
        ld (ix+23h),a           ; 83
        ld a,4
        ld (7000h),a
        ld a,(8010h)
        ld (ix+24h),a           ; 84
        ld a,(0010h)
        ld (ix+25h),a           ; page 0 of slot 2 is our code (slot 0 selected) -> 0
        pop af
        out (0A8h),a
        ret
ramcode_end:

        ds 8000h - $, 0FFh
