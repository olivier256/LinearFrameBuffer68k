| =====================================================================
|  LFB - Linear Frame Buffer 128x112 4bpp sur Mega Drive (test)
|  GNU as (m68k), options : -m68000 --register-prefix-optional
|
|  Principe : le 68k dessine dans un buffer LINÉAIRE en RAM
|  (64 octets par ligne, 2 pixels par octet). Une ligne = 2 tiles
|  consécutifs (tiles 400+2y, 401+2y). Chaque groupe de 8 px de la ligne
|  est la rangée r = k&7 d'un de ces tiles. On l'affiche en :
|    - plan A pour les groupes pairs, plan B pour les impairs
|    - VScroll par colonne 2-cell : A = 0,2,4,6  B = 1,3,5,7 (+ base)
|    - à chaque ligne écran, la base avance de +7 (8 lignes de plan
|      pour passer à la rangée de tilemap suivante, -1 car l'écran
|      avance lui-même d'une ligne)
|  En mode 2-cell il n'y a PAS de base commune : on réécrit 16 mots
|  de VSRAM à chaque H_INT (table précalculée).
| =====================================================================

        .include "build/config.inc"
        .equ VDP_DATA,  0xC00000
        .equ VDP_CTRL,  0xC00004

        .equ FB_RAM,    0xFF0000        | frame buffer linéaire 7168 octets
        .equ LineCnt,   0xFFFF00        | ligne écran suivante (w)
        .equ FrameFlag, 0xFFFF02        | (w)
        .equ BoxX,      0xFFFF04        | (w) pair
        .equ BoxY,      0xFFFF06        | (w)
        .equ BoxDX,     0xFFFF08        | (w)
        .equ BoxDY,     0xFFFF0A        | (w)
        .equ DmaCmd,    0xFFFF0C        | (l) commande DMA, lue depuis la RAM
        .equ VsPtr,     0xFFFF10        | (l) prochaine entrée de VsTable
        .equ HIntJmp,   0xFFFF14        | jmp.l xxx (6 octets)

        .equ FB_TOP,    56
        .equ FB_H,      112
        .equ FB_BYTES,  7168
        .equ BOX,       16
        .equ VS_BLANK,  900             | ligne écran 0..55 -> plan 900..962

        .equ REG1_ON,   0x8174          | display ON, VINT, DMA, mode 5
        .equ REG1_OFF,  0x8134          | display OFF

        .text
| ---------------------------------------------------------------------
|  Vecteurs
| ---------------------------------------------------------------------
        .long   0x00FFFE00              | SSP
        .long   Start                   | Reset
        .rept   26
        .long   Trap                    | 0x08..0x6C
        .endr
        .long   HIntJmp                 | 0x70 niveau 4 : H_INT (jmp en RAM)
        .long   Trap                    | 0x74
        .long   VInt                    | 0x78 niveau 6 : V_INT
        .rept   33
        .long   Trap
        .endr

| ---------------------------------------------------------------------
|  En-tête
| ---------------------------------------------------------------------
        .org    0x100
        .ascii  "SEGA MEGA DRIVE "
        .ascii  "(C)HOME 2026.NOV"
        .ascii  "LFB LINEAR FRAME BUFFER TEST                    "
        .ascii  "LFB LINEAR FRAME BUFFER TEST                    "
        .ascii  "GM 00000000-00"
        .word   0                       | checksum (patché par build.sh)
        .ascii  "J               "
        .long   0, RomEnd-1
        .long   0xFF0000, 0xFFFFFF
        .ascii  "            "
        .ascii  "            "
        .ascii  "                                        "
        .ascii  "JUE             "

| ---------------------------------------------------------------------
Trap:   rte

| ---------------------------------------------------------------------
|  Initialisation
| ---------------------------------------------------------------------
Start:
        move.w  #0x2700,sr
        move.b  0xA10001,d0             | TMSS
        andi.b  #0x0F,d0
        beq.s   1f
        move.l  #0x53454741,0xA14000    | 'SEGA'
1:
        lea     VDP_CTRL,a1
        lea     VDP_DATA,a2
        tst.w   (a1)

        lea     VdpRegs,a0
        moveq   #(VdpRegsEnd-VdpRegs)/2-1,d1
2:      move.w  (a0)+,(a1)
        dbra    d1,2b

        | --- VRAM à zéro
        move.l  #0x40000000,(a1)
        moveq   #0,d0
        move.w  #0x10000/4-1,d1
3:      move.l  d0,(a2)
        dbra    d1,3b
        | --- VSRAM à zéro
        move.l  #0x40000010,(a1)
        moveq   #40-1,d1
4:      move.w  d0,(a2)
        dbra    d1,4b
        | --- palette
        move.l  #0xC0000000,(a1)
        lea     Palette,a0
        moveq   #16-1,d1
5:      move.w  (a0)+,(a2)
        dbra    d1,5b
        | --- tilemap A (VRAM 0xC000) et B (VRAM 0xE000)
        move.l  #0x40000003,(a1)
        lea     TilemapA,a0
        move.w  #FB_H*64/4-1,d1
6:      move.l  (a0)+,(a2)
        dbra    d1,6b
        move.l  #0x60000003,(a1)
        lea     TilemapB,a0
        move.w  #FB_H*64/4-1,d1
7:      move.l  (a0)+,(a2)
        dbra    d1,7b

        | --- frame buffer RAM <- image de fond
        lea     Background,a0
        lea     FB_RAM,a3
        move.w  #FB_BYTES/4-1,d1
8:      move.l  (a0)+,(a3)+
        dbra    d1,8b

        | --- variables
        move.w  #0x4EF9,HIntJmp         | jmp (xxx).l
        move.l  #HIntIdle,HIntJmp+2
        clr.w   LineCnt
        clr.w   FrameFlag
        move.w  #20,BoxX
        move.w  #30,BoxY
        move.w  #2,BoxDX
        move.w  #1,BoxDY

        move.w  #0x2300,sr              | H_INT + V_INT

| ---------------------------------------------------------------------
|  Boucle principale : le 68k dessine en adressage LINÉAIRE
|  offset = y*64 + x/2
| ---------------------------------------------------------------------
Main:
        clr.w   FrameFlag
1:      tst.w   FrameFlag
        beq.s   1b

        | --- effacer le carré : recopier le fond
        bsr     BoxOffset               | d0 = offset
        lea     Background,a0
        lea     FB_RAM,a3
        adda.w  d0,a0
        adda.w  d0,a3
        moveq   #BOX-1,d2
2:      moveq   #BOX/2-1,d3
3:      move.b  (a0)+,(a3)+
        dbra    d3,3b
        lea     64-BOX/2(a0),a0
        lea     64-BOX/2(a3),a3
        dbra    d2,2b

        | --- déplacer
        move.w  BoxX,d0
        add.w   BoxDX,d0
        cmpi.w  #VIS_W-BOX,d0
        bls.s   4f
        neg.w   BoxDX
        add.w   BoxDX,d0
        add.w   BoxDX,d0
4:      move.w  d0,BoxX
        move.w  BoxY,d0
        add.w   BoxDY,d0
        cmpi.w  #FB_H-BOX,d0
        bls.s   5f
        neg.w   BoxDY
        add.w   BoxDY,d0
        add.w   BoxDY,d0
5:      move.w  d0,BoxY

        | --- dessiner : contour blanc (15), intérieur noir (0)
        bsr     BoxOffset
        lea     FB_RAM,a3
        adda.w  d0,a3
        moveq   #BOX-1,d2
6:      moveq   #BOX/2-1,d3
        move.b  #0xFF,d4                | ligne pleine
        cmpi.w  #0,d2
        beq.s   7f
        cmpi.w  #BOX-1,d2
        beq.s   7f
        moveq   #0,d4                   | ligne creuse
7:      move.b  #0xF0,d5                | bord gauche
        or.b    d4,d5
        move.b  d5,(a3)+
        subq.w  #2,d3
8:      move.b  d4,(a3)+
        dbra    d3,8b
        move.b  #0x0F,d5                | bord droit
        or.b    d4,d5
        move.b  d5,(a3)+
        lea     64-BOX/2(a3),a3
        dbra    d2,6b

        bra     Main

| d0 = BoxY*64 + BoxX/2
BoxOffset:
        move.w  BoxY,d0
        lsl.w   #6,d0
        move.w  BoxX,d1
        lsr.w   #1,d1
        add.w   d1,d0
        rts

| ---------------------------------------------------------------------
|  V_INT : début de trame
| ---------------------------------------------------------------------
VInt:
        movem.l d0-d1/a1,-(sp)
        move.w  #FB_TOP,LineCnt         | la n-ième H_INT prépare la ligne n
        move.l  #HIntWait,HIntJmp+2
        move.l  #VsTable,VsPtr
        lea     VDP_CTRL,a1
        | lignes 0..55 : VScroll vers les rangées vides du plan (112..127)
        move.l  #VSRAM_CMD,(a1)
        move.l  #VS_BLANK*0x10001,d0
        moveq   #VIS_COLS-1,d1
1:      move.l  d0,-4(a1)
        dbra    d1,1b
        move.w  #REG1_ON,(a1)           | display ON (coupé à la ligne 168)
        move.w  #1,FrameFlag
        movem.l (sp)+,d0-d1/a1
        rte

| ---------------------------------------------------------------------
|  H_INT (reg 10 = 0 : fin de chaque ligne active).
|  Vecteur 0x70 -> "jmp" en RAM : machine à états, sans calcul.
| ---------------------------------------------------------------------
| lignes 1..55 : on compte seulement
HIntWait:
        btst    #3,VDP_CTRL+1           | VB : H_INT de la ligne 224 -> ignorer
        bne.s   1f
        subq.w  #1,LineCnt
        beq.s   2f
1:      rte
2:      move.l  #HIntFB,HIntJmp+2       | fin de la ligne 55 : on enchaîne

| lignes 56..167 : VIS_COLS*2 mots de VSRAM pour la ligne suivante
HIntFB:
        movem.l a0-a1,-(sp)
        movea.l VsPtr,a0
        lea     VDP_CTRL,a1
        move.l  #VSRAM_CMD,(a1)
        .rept   VIS_COLS
        move.l  (a0)+,-4(a1)
        .endr
        move.l  a0,VsPtr
        cmpa.l  #VsTableEnd,a0
        bne.s   3f
        move.l  #HIntLast,HIntJmp+2
3:      movem.l (sp)+,a0-a1
        rte

| fin de la ligne 167 : display OFF -> le bas de l'écran + le VBlank
| ne servent qu'au DMA, à pleine vitesse (68k gelé ~35 lignes)
| fin de la ligne 166 : rien. Mesuré sous Genesis Plus GX : l'écriture
| du registre 1 dans l'H_INT n prend effet une ligne plus tôt que celle
| de la VSRAM, d'où ce cran d'attente. À vérifier sur vraie console.
HIntLast:
        move.l  #HIntEnd,HIntJmp+2
        rte

HIntEnd:
        move.l  a1,-(sp)
        lea     VDP_CTRL,a1
        move.w  #REG1_OFF,(a1)
        move.w  #0x9300,(a1)            | longueur 3584 mots
        move.w  #0x940E,(a1)
        move.w  #0x9500,(a1)            | source 0xFF0000 >> 1
        move.w  #0x9680,(a1)
        move.w  #0x977F,(a1)
        move.l  #0x72000080,DmaCmd      | VRAM 0x3200 (tile 400), DMA
        move.w  DmaCmd,(a1)
        move.w  DmaCmd+2,(a1)           | dernier mot lu en RAM
        move.l  #HIntIdle,HIntJmp+2
        move.l  (sp)+,a1
HIntIdle:
        rte

| ---------------------------------------------------------------------
VdpRegs:
        .word   0x8014                  | H_INT on
        .word   REG1_OFF
        .word   0x8230                  | plan A  0xC000
        .word   0x832C                  | window  0xB000
        .word   0x8407                  | plan B  0xE000
        .word   0x855C                  | sprites 0xB800
        .word   0x8600
        .word   0x8700                  | fond : pal 0 coul 0
        .word   0x8800, 0x8900
        .word   0x8A00                  | H_INT à chaque ligne
        .word   0x8B04                  | VScroll 2-cell, HScroll plein écran
        .word   0x8C81                  | H40
        .word   0x8D2F                  | HScroll 0xBC00
        .word   0x8E00
        .word   0x8F02                  | auto-incrément 2
        .word   0x9030                  | plans 32x128
        .word   0x9100, 0x9200          | pas de window
VdpRegsEnd:

        .balign 2
Palette:    .incbin "build/palette.bin"
VsTable:    .incbin "build/vstable.bin"
VsTableEnd:
TilemapA:   .incbin "build/tilemapA.bin"
TilemapB:   .incbin "build/tilemapB.bin"
Background: .incbin "build/bg.bin"
        .balign 2
RomEnd:
