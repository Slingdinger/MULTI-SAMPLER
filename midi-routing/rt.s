/* MIDI ROUTING -- MIDI tracks play audio tracks, set in NOTE SETUP (rt.c below).
 * Sender hook: 303 FOLLOW's operands (radiohagen's MIDI LOOPBACK): the stock midi_send (0x40010bc8) at
 * the sequencer note sites (the track in d7 at the note-on sites) and the live note (track d5).
 * NOTE SETUP: its key table (0x400bc4b8: UP / DOWN / LEFT / RIGHT were stock no-ops 0x400321f0 /
 * 0x400321f4, YES 0x4004af20), its D / F encoder entries, D / F value draw (as MIDI FOLLOW's RFOL),
 * its open callback and the end of its draw (0x40036548). */
    .text
    .global rt_send,rt_send_live,f3_page_send,rt_din,rt_usb,rt_v
    .global rt_open,rt_k_arrow,rt_k_yes,rt_enc,rt_dval,rt_draw,rt_fmt_mode,rt_fmt_out
    .weak usbmidi_tx_append,usbmidi_up

rt_send:
    move.l 8(%sp),-(%sp)        /* bytes */
    move.l 8(%sp),-(%sp)        /* len */
    move.l %d7,-(%sp)           /* the producer's track (meaningful at the note-on sites) */
    move.l 12(%sp),-(%sp)       /* the producer's return address */
    jsr rt_route
    lea 16(%sp),%sp
    tst.l %d0
    bne.s .rt_kept
    jmp 0x40010bc8
.rt_kept:
    rts

rt_send_live:
    move.l 8(%sp),-(%sp)
    move.l 8(%sp),-(%sp)
    move.l %d5,-(%sp)           /* the live note's MIDI track */
    move.l 12(%sp),-(%sp)
    jsr rt_route
    lea 16(%sp),%sp
    tst.l %d0
    bne.s .rt_live_kept
    jmp 0x40010bc8
.rt_live_kept:
    rts

/* f3_page_send(len, bytes): CHORDS FACTORY's page send (its ch_fsend, a weak reference): the page's
 * MIDI track (0x100b14cc), routed as a live note. */
f3_page_send:
    move.l 8(%sp),-(%sp)
    move.l 8(%sp),-(%sp)
    moveq #0,%d0
    move.b 0x100b14cc,%d0
    andi.l #7,%d0
    move.l %d0,-(%sp)
    pea 0x4009ea9a
    jsr rt_route
    lea 16(%sp),%sp
    tst.l %d0
    bne.s .rt_page_kept
    jmp 0x40010bc8
.rt_page_kept:
    rts

/* rt_din(len, bytes): the stock sender past its entry, so USB's mirror there (USB MIDI's detour, or
 * stock) is skipped: its displaced prologue, then the body. */
rt_din:
    lea -20(%sp),%sp
    movem.l %d2-%d5/%a2,(%sp)
    jmp 0x40010bd0

/* rt_usb(len, bytes): USB MIDI's queue only (when the USB module is in and the port is up). */
rt_usb:
    lea -24(%sp),%sp
    movem.l %d0-%d3/%a0-%a1,(%sp)
    lea usbmidi_up,%a0
    cmpa.l #0,%a0
    beq.s 9f
    tst.b (%a0)
    beq.s 9f
    move.l 28(%sp),%d0
    move.l 32(%sp),%a0
    jsr usbmidi_tx_append
9:  movem.l (%sp),%d0-%d3/%a0-%a1
    lea 24(%sp),%sp
    rts

/* NOTE SETUP's open callback: the cursor on the open track's column, T1; then the stock's. */
rt_open:
    move.b 0x100b14cc,%d0
    andi.l #7,%d0
    move.b %d0,rt_cx
    clr.b rt_cy
    jmp 0x400597b4

/* key handlers (key, ...): UP / DOWN / LEFT / RIGHT move the cursor; YES toggles its cell. */
rt_k_arrow:
    move.l 4(%sp),-(%sp)
    jsr rt_key
    addq.l #4,%sp
    tst.l %d0
    beq.s 9f
rt_redraw:
    jsr 0x40036548
    moveq #1,%d0
    move.l %d0,0x46c7c72c
9:  rts

rt_k_yes:
    jsr rt_yes
    tst.l %d0
    bne.s rt_redraw
    jmp 0x4004af20

/* D / F encoder entries (knob, raw delta): the stock detent accumulator (MIDI FOLLOW's bf_ui_delta),
 * the cursor's track's MODE / OUT, the redraw. Other knobs: the stock handler. */
rt_enc:
    move.l 4(%sp),%d0
    cmpi.l #3,%d0
    beq.s 1f
    cmpi.l #5,%d0
    beq.s 1f
    jmp 0x4003a8e8
1:  move.l 8(%sp),%d1
    cmpi.l #4,%d1
    ble.s 2f
    moveq #4,%d1
2:  cmpi.l #-4,%d1
    bge.s 3f
    moveq #-4,%d1
3:  pea 1024
    move.l %d1,-(%sp)
    move.l %d0,-(%sp)
    jsr 0x40032510
    lea 12(%sp),%sp
    tst.l %d0
    beq.s 4f
    move.l %d0,-(%sp)
    move.l 8(%sp),-(%sp)
    jsr rt_knob
    addq.l #8,%sp
    bra.s rt_redraw
4:  rts

/* 0x40036674 in the draw's knob loop (d4 the knob, a5 its value long): D and F show the cursor's
 * track's MODE / OUT, with no pending-edit mark (48(sp), as MIDI FOLLOW's bf_draw_value). */
rt_dval:
    move.l (%a5),%d3
    cmpi.l #3,%d4
    beq.s 1f
    cmpi.l #5,%d4
    bne.s 2f
1:  move.l %d4,-(%sp)
    jsr rt_value
    addq.l #4,%sp
    move.l %d0,%d3
    move.l %d3,48(%sp)
2:  move.l %d4,%d2
    moveq #3,%d0
    jmp 0x4003667a

/* the end of NOTE SETUP's draw (also its no-window exit): the map, then the stock epilogue. */
rt_draw:
    move.l 0x400bc6c0,%d0
    beq.s 1f
    addi.l #36,%d0
    move.l %d0,-(%sp)
    jsr rt_map
    addq.l #4,%sp
1:  movem.l (%sp),%d2-%d7/%a2-%a6
    lea 52(%sp),%sp
    rts

/* 0x4000b9a2 in the frame ISR's sequencer step (8 bytes: move.l (a0,a1.l*4),d0; move.w d0,ccr; bne
 * 0x4000b9d4): bit 2 of the step's command word 0x46c7e998[] is a trig (set: the track's flag byte
 * 0x46104d15[t] takes 0x10, the voice starts), clear a trigless lock. A linked pair (OctaZach 211):
 * an audio track playing a sound generator (MULTI, machine type 5) takes its notes from its MIDI
 * track only, so its own trigs are taken as trigless: their locks apply, no note starts. t = 114(sp).
 * Uses d1 a2 a3 (stock reloads them). */
    .global rt_seqtrig
rt_seqtrig:
    move.l (%a0,%a1.l*4),%d0
    btst #0,%d0                         | an audio step fires: its locks for the MIDI notes (rt_stk,
    beq.s 3f                            | OctaZach 214), from its pending slot 0x46c7ab30 + (n*8+t)*32
    move.l 120(%sp),%d1                 | (n = 120(sp), t = 114(sp): the copy at 0x4000bac2 reads them)
    lsl.l #3,%d1
    add.l 114(%sp),%d1
    lsl.l #5,%d1
    lea 0x46c7ab30,%a2
    adda.l %d1,%a2
    move.l 114(%sp),%d1
    lsl.l #5,%d1
    lea rt_stk,%a3
    adda.l %d1,%a3
    move.l (%a2)+,(%a3)+
    move.l (%a2)+,(%a3)+
    move.l (%a2)+,(%a3)+
    move.l (%a2)+,(%a3)+
    move.l (%a2)+,(%a3)+
    move.l (%a2)+,(%a3)+
    move.l (%a2)+,(%a3)+
    move.l (%a2)+,(%a3)+
3:
    movea.l 0x46c82456,%a2
    moveq #0,%d1
    move.b 0x100b14cf,%d1
    andi.l #3,%d1
    mulu.w #6322,%d1
    adda.l %d1,%a2
    adda.l 114(%sp),%a2
    adda.l #0x8eda2,%a2
    move.b (%a2),%d1
    cmpi.b #5,%d1
    beq.s 2f
    move.w %d0,%ccr
    bne.s 1f
    jmp 0x4000b9aa
1:  jmp 0x4000b9d4
2:  btst #2,%d0                         | linked: a note trig (event 29, or 61 one-shot: bit 2) becomes
    beq.s 1b                            | a lock-only step (event 1: the step handler 0x4009d1e8's codes,
    andi.l #-61,%d0                     | 29 note, 25 trigless, 61 one-shot, 1 lock-only) in the step's
    move.l %d0,(%a0,%a1.l*4)            | word itself, so every later reader sees a trigless lock.
    jmp 0x4000b9d4                      | (211 skipped the trig, 212 kept its word: no locks applied.)

/* formatters (char *buf, int value) */
rt_fmt_mode:
    move.l 4(%sp),%a0
    lea .rt_s_all,%a1
    tst.l 8(%sp)
    beq.s rt_cpy
    lea .rt_s_sprd,%a1
rt_cpy:
    move.b (%a1)+,(%a0)+
    bne.s rt_cpy
    rts
rt_fmt_out:
    move.l 4(%sp),%a0
    move.l 8(%sp),%d0
    andi.l #3,%d0
    lsl.l #3,%d0
    lea .rt_s_out,%a1
    adda.l %d0,%a1
    bra.s rt_cpy
.rt_s_all:  .asciz "ALL"
.rt_s_sprd: .asciz "SPRD"
    .balign 2
.rt_s_out:  .ascii "OFF\0\0\0\0\0DIN\0\0\0\0\0USB\0\0\0\0\0BOTH\0\0\0\0"
    .balign 2
rt_v:
    .long brain_v_octabam_midi_routing_1
    .long brain_v_octabam_midi_routing_2
    .long brain_v_octabam_midi_routing_3
    .long brain_v_octabam_midi_routing_4
    .long brain_v_octabam_midi_routing_5
    .long brain_v_octabam_midi_routing_6
    .long brain_v_octabam_midi_routing_7
    .long brain_v_octabam_midi_routing_8
    .long brain_v_octabam_midi_routing_9
    .long brain_v_octabam_midi_routing_10
    .long brain_v_octabam_midi_routing_11
    .long brain_v_octabam_midi_routing_12
    .long brain_v_octabam_midi_routing_13
    .long brain_v_octabam_midi_routing_14
    .long brain_v_octabam_midi_routing_15
    .long brain_v_octabam_midi_routing_16
    .long brain_v_octabam_midi_routing_17
    .long brain_v_octabam_midi_routing_18
    .long brain_v_octabam_midi_routing_19
    .long brain_v_octabam_midi_routing_20
    .long brain_v_octabam_midi_routing_21
    .long brain_v_octabam_midi_routing_22
    .long brain_v_octabam_midi_routing_23
    .long brain_v_octabam_midi_routing_24

/* ---- rt.c, m68k-linux-gnu-gcc -mcpu=54455 -O2 -fomit-frame-pointer (labels prefixed, sections joined) */
#NO_APP
	.align	2
rt_name:
	lea (-40,%sp),%sp
	movem.l #15612,(%sp)
	move.l 44(%sp),%d2
	move.l #1096,%d0
	muls.l %d0,%d2
	move.l %d2,%a0
	add.l #269161712,%a0
	add.l #269161967,%d2
	move.l %a0,%a1
.Lrt_2:
	move.b (%a0),%d0
	move.l %a0,%d1
	addq.l #1,%d1
	tst.b %d0
	jeq .Lrt_6
	move.b (%a0),%d0
	moveq #47,%d3
	mvs.b %d0,%d0
	cmp.l %d0,%d3
	jeq .Lrt_47
	move.l %d1,%a0
	cmp.l %d1,%d2
	jne .Lrt_2
.Lrt_6:
	clr.l %d1
.Lrt_4:
	lea (%a1,%d1.l),%a0
	move.b (%a0),%d0
	jeq .Lrt_8
	move.b (%a0),%d0
	moveq #46,%d2
	mvs.b %d0,%d0
	cmp.l %d0,%d2
	jeq .Lrt_8
	addq.l #1,%d1
	moveq #64,%d7
	cmp.l %d1,%d7
	jne .Lrt_4
.Lrt_7:
	move.w #-1,%a5
	move.l %a1,%d6
	moveq #2,%d5
	moveq #1,%d3
	sub.l %a0,%a0
	subq.l #1,%d6
	lea (rt_pc2),%a3
.Lrt_24:
	lea (%a1,%a0.l),%a2
	moveq #6,%d7
	move.b (%a2),%d4
	move.l %d4,%d2
	add.l #-65,%d2
	mvz.b %d2,%d2
	cmp.l %d2,%d7
	jcs .Lrt_48
	tst.l %a0
	jeq .Lrt_49
	lea (%a0,%d6.l),%a2
	moveq #64,%d0
	move.b (%a2),%d7
	move.l %d3,%d2
	mvs.b %d7,%d7
	cmp.l %d7,%d0
	jge .Lrt_15
	move.b (%a2),%d7
	moveq #90,%d0
	mvs.b %d7,%d7
	cmp.l %d7,%d0
	jge .Lrt_11
.Lrt_15:
	move.b (%a2),%d7
	moveq #96,%d0
	mvs.b %d7,%d7
	cmp.l %d7,%d0
	jge .Lrt_16
	move.b (%a2),%d7
	moveq #122,%d0
	mvs.b %d7,%d7
	cmp.l %d7,%d0
	jge .Lrt_11
.Lrt_16:
	cmp.l %d1,%d3
	jge .Lrt_13
	mvs.b %d4,%d4
	move.l %d3,%a2
	move.l %d3,%a4
	mvs.b -65(%a3,%d4.l),%d7
.Lrt_14:
	add.l %a1,%a2
	move.b (%a2),%d4
	moveq #35,%d0
	mvs.b %d4,%d4
	cmp.l %d4,%d0
	jeq .Lrt_17
	move.b (%a2),%d4
	moveq #115,%d0
	mvs.b %d4,%d4
	cmp.l %d4,%d0
	jeq .Lrt_17
	move.b (%a2),%d4
	moveq #83,%d0
	mvs.b %d4,%d4
	cmp.l %d4,%d0
	jeq .Lrt_17
	move.b (%a2),%d4
	moveq #98,%d0
	mvs.b %d4,%d4
	cmp.l %d4,%d0
	jeq .Lrt_50
	move.b (%a2),%d4
	moveq #45,%d0
	mvs.b %d4,%d4
	cmp.l %d4,%d0
	jeq .Lrt_51
.Lrt_25:
	sub.l %a4,%a4
.Lrt_21:
	move.b (%a2),%d4
	moveq #47,%d0
	mvs.b %d4,%d4
	cmp.l %d4,%d0
	jge .Lrt_11
	move.b (%a2),%d4
	moveq #57,%d0
	mvs.b %d4,%d4
	cmp.l %d4,%d0
	jlt .Lrt_11
	move.b (%a2),%d4
	mvs.b %d4,%d4
	move.l %d4,%a2
	tst.l %a4
	jne .Lrt_22
	add.l #-48,%d4
.Lrt_23:
	addq.l #1,%d4
	moveq #12,%d0
	muls.l %d0,%d4
	add.l %d7,%d4
	cmp.l #128,%d4
	jcc .Lrt_11
	move.l 52(%sp),%a2
	move.l %d4,%a5
	move.l %a0,(%a2)
.Lrt_11:
	addq.l #1,%a0
	addq.l #1,%d3
	addq.l #1,%d5
	cmp.l %d1,%d2
	jlt .Lrt_24
.Lrt_13:
	move.l %a5,%d0
	movem.l (%sp),#15612
	move.l 48(%sp),%a0
	move.l %a1,(%a0)
	lea (40,%sp),%sp
	rts
.Lrt_47:
	lea (1,%a0),%a1
	move.l %a1,%d1
	move.l %d1,%a0
	cmp.l %d1,%d2
	jne .Lrt_2
	jra .Lrt_6
.Lrt_50:
	subq.l #1,%d7
	move.l %d5,%a4
.Lrt_19:
	cmp.l %d5,%d1
	jle .Lrt_11
	lea (%a1,%d5.l),%a2
	moveq #45,%d0
	move.b (%a2),%d4
	mvs.b %d4,%d4
	cmp.l %d4,%d0
	jne .Lrt_25
.Lrt_51:
	addq.l #1,%a4
	cmp.l %a4,%d1
	jle .Lrt_11
	lea (%a1,%a4.l),%a2
	move.w #1,%a4
	jra .Lrt_21
.Lrt_48:
	move.l %d3,%d2
	addq.l #1,%a0
	addq.l #1,%d3
	addq.l #1,%d5
	cmp.l %d1,%d2
	jlt .Lrt_24
	jra .Lrt_13
.Lrt_17:
	addq.l #1,%d7
	move.l %d5,%a4
	jra .Lrt_19
.Lrt_49:
	moveq #1,%d0
	cmp.l %d1,%d0
	jeq .Lrt_13
	mvs.b %d4,%d4
	move.w #1,%a2
	move.w #1,%a4
	move.l %d3,%d2
	mvs.b -65(%a3,%d4.l),%d7
	jra .Lrt_14
.Lrt_8:
	tst.l %d1
	jne .Lrt_7
	move.w #-1,%a5
	move.l 48(%sp),%a0
	move.l %a5,%d0
	movem.l (%sp),#15612
	move.l %a1,(%a0)
	lea (40,%sp),%sp
	rts
.Lrt_22:
	moveq #48,%d4
	sub.l %a2,%d4
	jra .Lrt_23
	.align	2
rt_same:
	link.w %fp,#-16
	move.l %a2,-(%sp)
	move.l %d2,-(%sp)
	pea -8(%fp)
	pea -16(%fp)
	lea rt_name,%a2
	move.l 8(%fp),-(%sp)
	jsr (%a2)
	lea (12,%sp),%sp
	tst.l %d0
	jlt .Lrt_53
	pea -4(%fp)
	pea -12(%fp)
	move.l 12(%fp),-(%sp)
	jsr (%a2)
	lea (12,%sp),%sp
	tst.l %d0
	jlt .Lrt_53
	move.l -8(%fp),%d2
	cmp.l -4(%fp),%d2
	jne .Lrt_53
	tst.l %d2
	jle .Lrt_56
	move.l -12(%fp),%a1
	move.l -16(%fp),%a0
	add.l %a0,%d2
.Lrt_55:
	move.b (%a0),%d1
	move.b (%a1),%d0
	addq.l #1,%a0
	addq.l #1,%a1
	mvs.b %d1,%d1
	mvs.b %d0,%d0
	cmp.l %d1,%d0
	jne .Lrt_53
	cmp.l %a0,%d2
	jne .Lrt_55
.Lrt_56:
	move.l -24(%fp),%d2
	moveq #1,%d0
	move.l -20(%fp),%a2
	unlk %fp
	rts
.Lrt_53:
	move.l -24(%fp),%d2
	clr.l %d0
	move.l -20(%fp),%a2
	unlk %fp
	rts
	.align	2
rt_stop:
	lea (-16,%sp),%sp
	movem.l #1052,(%sp)
	move.l 24(%sp),%d3
	moveq #127,%d4
	move.l 20(%sp),%d2
	lea mu_note,%a2
	and.l %d3,%d4
	tst.l %a2
	jeq .Lrt_61
	move.l 1187521622,%a0
	moveq #3,%d1
	move.b -2147483645,%d0
	add.l #585122,%a0
	add.l %d2,%a0
	and.l %d1,%d0
	move.l #6322,%d1
	muls.l %d1,%d0
	add.l %d0,%a0
	move.b (%a0),%d0
	mvz.b %d0,%d0
	subq.l #5,%d0
	tst.l %d0
	jeq .Lrt_75
.Lrt_61:
	lea rt_note,%a0
	mvz.b (%a0,%d2.l),%d0
	cmp.l %d0,%d4
	jeq .Lrt_76
.Lrt_65:
	moveq #1,%d0
	lea rt_on,%a0
	lsl.l %d2,%d0
	move.b (%a0,%d3.l),%d1
	not.l %d0
	and.l %d1,%d0
	move.b %d0,(%a0,%d3.l)
	movem.l (%sp),#1052
	lea (16,%sp),%sp
	rts
.Lrt_76:
	lea rt_chan,%a1
	mvz.b (%a1,%d2.l),%d1
	move.l %d3,%d0
	lsr.l #7,%d0
	cmp.l %d1,%d0
	jne .Lrt_65
	move.l %d2,%d0
	add.l #296878293,%d0
	lsl.l #2,%d0
	moveq #64,%d1
	move.l %d0,%a1
	move.l (%a1),%d0
	or.l %d1,%d0
	clr.b %d1
	move.l %d0,(%a1)
	st %d0
	addq.l #1,rt_offs
	move.b %d0,(%a0,%d2.l)
	lea rt_held,%a0
	moveq #1,%d0
	move.b %d1,(%a0,%d2.l)
	lea rt_on,%a0
	lsl.l %d2,%d0
	move.b (%a0,%d3.l),%d1
	not.l %d0
	and.l %d1,%d0
	move.b %d0,(%a0,%d3.l)
	movem.l (%sp),#1052
	lea (16,%sp),%sp
	rts
.Lrt_75:
	move.l %d2,-(%sp)
	jsr mu_is_ms
	addq.l #4,%sp
	tst.l %d0
	jne .Lrt_63
	add.l #24,%d4
.Lrt_63:
	clr.l -(%sp)
	move.l %d4,-(%sp)
	move.l %d2,-(%sp)
	jsr (%a2)
	lea (12,%sp),%sp
	lea rt_held,%a0
	move.b (%a0,%d2.l),%d0
	jeq .Lrt_65
	subq.l #1,%d0
	move.b %d0,(%a0,%d2.l)
	moveq #1,%d0
	lea rt_on,%a0
	lsl.l %d2,%d0
	move.b (%a0,%d3.l),%d1
	not.l %d0
	and.l %d1,%d0
	move.b %d0,(%a0,%d3.l)
	movem.l (%sp),#1052
	lea (16,%sp),%sp
	rts
	.align	2
rt_play:
	lea (-60,%sp),%sp
	movem.l #31996,(%sp)
	move.l 72(%sp),%d3
	move.l 68(%sp),%d4
	move.l 64(%sp),%d7
	lsl.l #7,%d3
	lea mu_note,%a2
	add.l %d4,%d3
	tst.l %a2
	jeq .Lrt_78
	move.l 1187521622,%a0
	moveq #3,%d1
	move.b -2147483645,%d0
	add.l #585122,%a0
	add.l %d7,%a0
	and.l %d1,%d0
	move.l #6322,%d1
	muls.l %d1,%d0
	add.l %d0,%a0
	move.b (%a0),%d0
	mvz.b %d0,%d0
	subq.l #5,%d0
	tst.l %d0
	jeq .Lrt_130
.Lrt_78:
	lea rt_note,%a2
	mvz.b (%a2,%d7.l),%d0
	lea rt_chan,%a3
	cmp.l #255,%d0
	jne .Lrt_81
	move.l 1187521622,%a0
	moveq #3,%d1
	move.b -2147483645,%d0
	move.l %d7,%d2
	lsl.l #5,%d2
	and.l %d1,%d0
	move.l #6322,%d1
	move.l %d2,%a4
	add.l #1187504090,%a4
	muls.l %d1,%d0
	add.l %a0,%d0
	move.l %d7,%a0
	add.l #585122,%a0
	add.l %d0,%a0
	move.b (%a0),%d5
	mvz.b %d5,%d5
	subq.l #1,%d5
	tst.l %d5
	jeq .Lrt_131
.Lrt_85:
	move.l %d4,%d0
	moveq #-12,%d1
	add.l #-60,%d0
	cmp.l %d0,%d1
	jle .Lrt_107
	moveq #-12,%d0
.Lrt_108:
	muls.w #5,%d0
	add.l #64,%d0
	move.b %d0,(%a4)
.Lrt_89:
	moveq #7,%d1
	cmp.l %d7,%d1
	jcs .Lrt_106
	move.l #1187504089,%d6
	move.l %d2,%a0
	sub.l #rt_stk,%d6
	add.l #rt_stk+1,%a0
	add.l #rt_stk+31,%d2
.Lrt_105:
	move.b (%a0)+,%d1
	mvz.b %d1,%d0
	lea (%a0,%d6.l),%a1
	cmp.l #255,%d0
	jeq .Lrt_104
	move.b (%a1),%d0
	mvz.b %d0,%d0
	cmp.l #255,%d0
	jeq .Lrt_132
.Lrt_104:
	cmp.l %a0,%d2
	jne .Lrt_105
.Lrt_106:
	pea -1.w
	pea 1.w
	pea 29.w
	move.l %d7,-(%sp)
	jsr 1073762352
	moveq #1,%d0
	lea (91,%sp),%a0
	move.b (%a0),(%a3,%d7.l)
	lea rt_held,%a0
	move.b %d4,(%a2,%d7.l)
	lea (16,%sp),%sp
	move.b %d0,(%a0,%d7.l)
.Lrt_84:
	lea rt_on,%a0
	moveq #1,%d0
	move.b (%a0,%d3.l),%d2
	lsl.l %d7,%d0
	move.l rt_clock,%a1
	addq.l #1,%a1
	lea rt_age,%a2
	move.l %a1,(%a2,%d7.l*4)
	lea (79,%sp),%a3
	lea rt_src,%a2
	move.b (%a3),(%a2,%d7.l)
	lea rt_osrc,%a2
	move.b (%a3),(%a2,%d3.l)
	or.l %d2,%d0
	move.l %a1,rt_clock
	addq.l #1,rt_notes
	move.b %d0,(%a0,%d3.l)
.Lrt_77:
	movem.l (%sp),#31996
	lea (60,%sp),%sp
	rts
.Lrt_81:
	mvz.b (%a3,%d7.l),%d2
	lsl.l #7,%d2
	move.l %d2,%a0
	move.l %d7,%d2
	pea (%a0,%d0.l)
	move.l %d7,-(%sp)
	jsr rt_stop
	lsl.l #5,%d2
	addq.l #8,%sp
	move.l 1187521622,%a0
	moveq #3,%d1
	move.b -2147483645,%d0
	move.l %d2,%a4
	add.l #1187504090,%a4
	and.l %d1,%d0
	move.l #6322,%d1
	muls.l %d1,%d0
	add.l %a0,%d0
	move.l %d7,%a0
	add.l #585122,%a0
	add.l %d0,%a0
	move.b (%a0),%d5
	mvz.b %d5,%d5
	subq.l #1,%d5
	tst.l %d5
	jne .Lrt_85
	jra .Lrt_131
.Lrt_130:
	move.l %d7,-(%sp)
	jsr mu_is_ms
	addq.l #4,%sp
	tst.l %d0
	jeq .Lrt_79
.Lrt_80:
	pea 1.w
	move.l %d4,-(%sp)
	move.l %d7,-(%sp)
	jsr (%a2)
	lea (12,%sp),%sp
	tst.l %d0
	jeq .Lrt_77
	lea rt_held,%a0
	moveq #7,%d1
	move.b (%a0,%d7.l),%d0
	mvz.b %d0,%d2
	cmp.l %d2,%d1
	jcs .Lrt_84
	addq.l #1,%d0
	move.b %d0,(%a0,%d7.l)
	lea rt_on,%a0
	moveq #1,%d0
	move.b (%a0,%d3.l),%d2
	lsl.l %d7,%d0
	move.l rt_clock,%a1
	addq.l #1,%a1
	lea rt_age,%a2
	move.l %a1,(%a2,%d7.l*4)
	lea (79,%sp),%a3
	lea rt_src,%a2
	move.b (%a3),(%a2,%d7.l)
	lea rt_osrc,%a2
	move.b (%a3),(%a2,%d3.l)
	or.l %d2,%d0
	move.l %a1,rt_clock
	addq.l #1,rt_notes
	move.b %d0,(%a0,%d3.l)
	jra .Lrt_77
.Lrt_132:
	move.b %d1,(%a1)
	cmp.l %a0,%d2
	jne .Lrt_105
	jra .Lrt_106
.Lrt_131:
	move.l %d7,%d5
	lsl.l #2,%d5
	move.l %d5,%a0
	add.l %d7,%a0
	add.l %d0,%a0
	add.l #585803,%a0
	move.b (%a0),%d0
	mvz.b %d0,%d1
	move.l %d1,44(%sp)
	tst.b %d0
	jlt .Lrt_85
	pea 56(%sp)
	pea 56(%sp)
	move.l 52(%sp),-(%sp)
	jsr rt_name
	lea (12,%sp),%sp
	tst.l %d0
	jlt .Lrt_85
	move.l 44(%sp),%d5
	move.l %d5,%a6
	lea rt_same,%a5
.Lrt_93:
	move.l %d5,%d6
	subq.l #1,%d6
	tst.l %d5
	jeq .Lrt_94
	move.l %a6,-(%sp)
	move.l %d6,-(%sp)
	jsr (%a5)
	addq.l #8,%sp
	tst.l %d0
	jeq .Lrt_94
	move.l %d6,%d5
	jra .Lrt_93
.Lrt_107:
	moveq #12,%d1
	cmp.l %d0,%d1
	jge .Lrt_108
	moveq #12,%d0
	muls.w #5,%d0
	add.l #64,%d0
	move.b %d0,(%a4)
	jra .Lrt_89
.Lrt_79:
	add.l #24,%d4
	jra .Lrt_80
.Lrt_94:
	move.l 44(%sp),%d6
	move.l %d6,%a6
	lea rt_same,%a5
	move.l %d2,48(%sp)
.Lrt_92:
	move.l %d6,%d2
	moveq #127,%d0
	addq.l #1,%d2
	cmp.l %d6,%d0
	jeq .Lrt_133
	move.l %a6,-(%sp)
	move.l %d2,-(%sp)
	jsr (%a5)
	addq.l #8,%sp
	tst.l %d0
	jeq .Lrt_134
	move.l %d2,%d6
	jra .Lrt_92
.Lrt_133:
	move.l 48(%sp),%d2
	moveq #60,%d1
	move.w #1000,%a5
	move.w #-1,%a6
	move.l %d2,44(%sp)
	move.l %d5,%d2
	move.l %d1,%d5
.Lrt_100:
	pea 56(%sp)
	pea 56(%sp)
	move.l %d2,-(%sp)
	jsr rt_name
	lea (12,%sp),%sp
	move.l %d4,%a0
	move.l %d2,%a1
	sub.l %d0,%a0
	addq.l #1,%a1
	tst.l %a0
	jlt .Lrt_135
.Lrt_98:
	cmp.l %a0,%a5
	jle .Lrt_99
	move.l %d2,%a6
	move.l %a0,%a5
	move.l %d0,%d5
.Lrt_99:
	cmp.l %d2,%d6
	jeq .Lrt_136
	pea 56(%sp)
	move.l %a1,%d2
	pea 56(%sp)
	move.l %d2,-(%sp)
	jsr rt_name
	lea (12,%sp),%sp
	move.l %d4,%a0
	move.l %d2,%a1
	sub.l %d0,%a0
	addq.l #1,%a1
	tst.l %a0
	jge .Lrt_98
.Lrt_135:
	move.l %d0,%a0
	sub.l %d4,%a0
	jra .Lrt_98
.Lrt_136:
	move.l %d4,%d0
	moveq #-12,%d1
	move.l 44(%sp),%d2
	sub.l %d5,%d0
	cmp.l %d0,%d1
	jle .Lrt_101
	moveq #-12,%d0
.Lrt_102:
	muls.w #5,%d0
	add.l #64,%d0
	move.b %d0,(%a4)
	tst.l %a6
	jlt .Lrt_89
	move.w %a6,%d0
	move.l %d2,%a0
	add.l #1187504121,%a0
	move.b %d0,(%a0)
	jra .Lrt_89
.Lrt_101:
	moveq #12,%d1
	cmp.l %d0,%d1
	jge .Lrt_102
	moveq #12,%d0
	jra .Lrt_102
.Lrt_134:
	move.l 48(%sp),%d2
	cmp.l %d6,%d5
	jhi .Lrt_85
	moveq #60,%d1
	move.l %d2,44(%sp)
	move.l %d5,%d2
	move.l %d1,%d5
	move.w #1000,%a5
	move.w #-1,%a6
	jra .Lrt_100
	.align	2
	.globl	rt_locks
rt_locks:
	move.l %d3,-(%sp)
	moveq #7,%d0
	move.l %d2,-(%sp)
	move.l 12(%sp),%d2
	cmp.l %d2,%d0
	jcs .Lrt_137
	lsl.l #5,%d2
	move.l #1187504089,%d3
	sub.l #rt_stk,%d3
	move.l %d2,%a0
	add.l #rt_stk+31,%d2
	add.l #rt_stk+1,%a0
.Lrt_140:
	move.b (%a0)+,%d1
	mvz.b %d1,%d0
	lea (%a0,%d3.l),%a1
	cmp.l #255,%d0
	jeq .Lrt_139
	move.b (%a1),%d0
	mvz.b %d0,%d0
	cmp.l #255,%d0
	jeq .Lrt_147
.Lrt_139:
	cmp.l %a0,%d2
	jne .Lrt_140
.Lrt_137:
	move.l (%sp)+,%d2
	move.l (%sp)+,%d3
	rts
.Lrt_147:
	move.b %d1,(%a1)
	cmp.l %a0,%d2
	jne .Lrt_140
	jra .Lrt_137
	.align	2
	.globl	rt_route
rt_route:
	lea (-44,%sp),%sp
	moveq #3,%d0
	movem.l #15612,(%sp)
	move.l 60(%sp),%a2
	cmp.l 56(%sp),%d0
	jne .Lrt_149
	move.b (%a2),%d0
	move.b 1(%a2),%d2
	moveq #15,%d3
	moveq #127,%d1
	and.l %d0,%d3
	and.l %d1,%d2
	move.l %d0,%d1
	and.l #240,%d1
	move.l %d3,%d0
	lsl.l #7,%d3
	add.l %d2,%d3
	cmp.l #144,%d1
	jeq .Lrt_238
	cmp.l #128,%d1
	jeq .Lrt_151
.Lrt_149:
	movem.l (%sp),#15612
	clr.l %d0
	lea (44,%sp),%sp
	rts
.Lrt_151:
	lea rt_on,%a0
	mvz.b (%a0,%d3.l),%d4
	tst.l %d4
	jeq .Lrt_149
	lea rt_osrc,%a0
	clr.l %d2
	mvz.b (%a0,%d3.l),%d5
	lea rt_stop,%a3
.Lrt_172:
	btst %d2,%d4
	jne .Lrt_239
.Lrt_171:
	addq.l #1,%d2
	moveq #8,%d7
	cmp.l %d2,%d7
	jne .Lrt_172
	lea rt_v,%a0
	moveq #3,%d0
	move.l 64(%a0,%d5.l*4),%a0
	moveq #1,%d1
	and.l (%a0),%d0
	cmp.l %d0,%d1
	jeq .Lrt_166
.Lrt_234:
	moveq #2,%d3
	cmp.l %d0,%d3
	jeq .Lrt_167
	tst.l %d0
	jne .Lrt_149
	moveq #1,%d0
.Lrt_242:
	movem.l (%sp),#15612
	lea (44,%sp),%sp
	rts
.Lrt_239:
	move.l %d3,-(%sp)
	move.l %d2,-(%sp)
	jsr (%a3)
	addq.l #8,%sp
	jra .Lrt_171
.Lrt_238:
	tst.b 2(%a2)
	jeq .Lrt_151
	move.l 48(%sp),%d7
	cmp.l #1074396082,%d7
	jeq .Lrt_152
	cmp.l #1074396410,%d7
	jeq .Lrt_152
	cmp.l #1074391706,%d7
	jne .Lrt_149
.Lrt_152:
	moveq #7,%d1
	cmp.l 52(%sp),%d1
	jcs .Lrt_149
	move.l 52(%sp),%d4
	lea rt_v,%a3
	move.l (%a3,%d4.l*4),%a0
	move.l (%a0),%d5
	mvz.b %d5,%d5
	tst.l %d5
	jeq .Lrt_149
	lea rt_on,%a4
	move.b (%a4,%d3.l),%d1
	jeq .Lrt_153
	mvz.b %d1,%d1
	clr.l %d4
	lea rt_stop,%a5
	btst %d4,%d1
	jne .Lrt_240
.Lrt_154:
	addq.l #1,%d4
	moveq #8,%d7
	cmp.l %d4,%d7
	jeq .Lrt_153
	move.b (%a4,%d3.l),%d1
	mvz.b %d1,%d1
	btst %d4,%d1
	jeq .Lrt_154
	jra .Lrt_240
.Lrt_153:
	move.l 52(%sp),%d1
	move.l 32(%a3,%d1.l*4),%a0
	tst.l (%a0)
	jne .Lrt_174
	clr.l %d3
	lea rt_play,%a4
.Lrt_158:
	btst %d3,%d5
	jne .Lrt_241
	addq.l #1,%d3
	moveq #8,%d4
	cmp.l %d3,%d4
	jne .Lrt_158
.Lrt_159:
	move.l 52(%sp),%d0
	moveq #1,%d1
	move.l 64(%a3,%d0.l*4),%a0
	moveq #3,%d0
	and.l (%a0),%d0
	cmp.l %d0,%d1
	jne .Lrt_234
.Lrt_166:
	move.l %a2,-(%sp)
	pea 3.w
	jsr rt_din
	addq.l #8,%sp
	moveq #1,%d0
	jra .Lrt_242
.Lrt_240:
	move.l %d3,-(%sp)
	move.l %d4,-(%sp)
	move.l %d0,48(%sp)
	jsr (%a5)
	addq.l #8,%sp
	move.l 40(%sp),%d0
	jra .Lrt_154
.Lrt_167:
	move.l %a2,-(%sp)
	pea 3.w
	jsr rt_usb
	addq.l #8,%sp
	moveq #1,%d0
	jra .Lrt_242
.Lrt_241:
	move.l 52(%sp),-(%sp)
	move.l %d0,-(%sp)
	moveq #8,%d4
	move.l %d2,-(%sp)
	move.l %d3,-(%sp)
	move.l %d0,56(%sp)
	jsr (%a4)
	lea (16,%sp),%sp
	addq.l #1,%d3
	move.l 40(%sp),%d0
	cmp.l %d3,%d4
	jne .Lrt_158
	jra .Lrt_159
.Lrt_174:
	clr.l %d1
	lea rt_held,%a4
	lea mu_note,%a1
.Lrt_156:
	move.l %d5,%d3
	lsr.l %d1,%d3
	moveq #1,%d4
	and.l %d3,%d4
	btst #0,%d3
	jne .Lrt_243
.Lrt_160:
	addq.l #1,%d1
	moveq #8,%d3
	cmp.l %d1,%d3
	jne .Lrt_156
	move.w #-1,%a1
	clr.l %d3
	lea rt_age,%a4
.Lrt_164:
	btst %d3,%d5
	jeq .Lrt_163
	move.l (%a4,%d3.l*4),%a0
	cmp.l %a1,%a0
	jcc .Lrt_163
	move.l %d3,%d1
	move.l %a0,%a1
.Lrt_163:
	addq.l #1,%d3
	moveq #8,%d4
	cmp.l %d3,%d4
	jne .Lrt_164
	moveq #7,%d7
	cmp.l %d1,%d7
	jcs .Lrt_159
	move.l 52(%sp),-(%sp)
	move.l %d0,-(%sp)
	move.l %d2,-(%sp)
	move.l %d1,-(%sp)
	jsr rt_play
	lea (16,%sp),%sp
.Lrt_245:
	moveq #1,%d1
	move.l 52(%sp),%d0
	move.l 64(%a3,%d0.l*4),%a0
	moveq #3,%d0
	and.l (%a0),%d0
	cmp.l %d0,%d1
	jne .Lrt_234
	jra .Lrt_166
.Lrt_243:
	mvz.b (%a4,%d1.l),%d6
	tst.l %a1
	jeq .Lrt_161
	move.l 1187521622,%a0
	moveq #3,%d7
	move.b -2147483645,%d3
	add.l #585122,%a0
	and.l %d7,%d3
	move.l #6322,%d7
	muls.l %d7,%d3
	add.l %d3,%a0
	add.l %d1,%a0
	move.b (%a0),%d3
	mvz.b %d3,%d3
	subq.l #5,%d3
	tst.l %d3
	jeq .Lrt_244
.Lrt_161:
	cmp.l %d6,%d4
	jls .Lrt_160
.Lrt_237:
	move.l 52(%sp),-(%sp)
	move.l %d0,-(%sp)
	move.l %d2,-(%sp)
	move.l %d1,-(%sp)
	jsr rt_play
	lea (16,%sp),%sp
	jra .Lrt_245
.Lrt_244:
	moveq #8,%d4
	cmp.l %d6,%d4
	jhi .Lrt_237
	jra .Lrt_160
.Lrt_C0:
	.string	"%s"
	.align	2
	.globl	rt_map
rt_map:
	lea (-48,%sp),%sp
	movem.l #31996,(%sp)
	move.b rt_cx,%d5
	move.b rt_cy,%d1
	moveq #7,%d2
	moveq #49,%d3
	pea 1.w
	moveq #50,%d6
	pea 51.w
	move.l 60(%sp),%d0
	clr.l %d7
	move.w #48,%a3
	lea (rt_s1),%a4
	move.l %d0,rt_fb
	and.l %d2,%d5
	and.l %d1,%d2
	move.w %d5,%d1
	move.l %d2,%a5
	mulu.w #5,%d1
	move.l %d1,%a0
	pea 14(%a0)
	pea 5.w
	pea 10(%a0)
	move.l %d0,-(%sp)
	jsr 1073816148
	lea (24,%sp),%sp
.Lrt_252:
	move.l %d7,%d4
	move.l %a3,%d2
	add.l #49,%d4
	move.l rt_fb,%d0
	subq.l #1,%d2
	cmp.l %d7,%a5
	jeq .Lrt_257
	move.b %d4,(%a4)
	clr.b %d1
	moveq #1,%d4
	lsl.l %d7,%d4
	move.w #11,%a2
	move.l %a4,-(%sp)
	pea .Lrt_C0
	move.l %a4,-(%sp)
	clr.l -(%sp)
	clr.l -(%sp)
	move.l %d2,-(%sp)
	pea 5.w
	move.l %d0,-(%sp)
	move.l #1074505846,-(%sp)
	clr.l %d2
	move.b %d1,rt_s1+1
	jsr 1073821956
	lea (36,%sp),%sp
	lea rt_v,%a6
	move.l %d7,44(%sp)
.Lrt_251:
	cmp.l %d5,%d2
	sne %d0
	move.l (%a6)+,%a1
	move.l %d4,%d7
	move.l rt_fb,%d1
	lea (1,%a2),%a0
	and.l (%a1),%d7
	mvs.b %d0,%d0
	neg.l %d0
	tst.l %d7
	jeq .Lrt_249
	move.l %d0,-(%sp)
	move.l %d6,-(%sp)
	pea 2(%a2)
	move.l %a3,-(%sp)
	move.l %a2,-(%sp)
	move.l %d1,-(%sp)
	jsr 1073816148
	lea (24,%sp),%sp
	addq.l #1,%d2
	addq.l #5,%a2
	moveq #8,%d0
	cmp.l %d2,%d0
	jne .Lrt_251
.Lrt_258:
	move.l 44(%sp),%d7
	subq.l #6,%a3
	addq.l #1,%d7
	subq.l #6,%d6
	subq.l #6,%d3
	tst.l %a3
	jne .Lrt_252
	movem.l (%sp),#31996
	lea (48,%sp),%sp
	rts
.Lrt_249:
	move.l %d0,-(%sp)
	move.l %d3,-(%sp)
	move.l %a0,-(%sp)
	move.l %d3,-(%sp)
	move.l %a0,-(%sp)
	move.l %d1,-(%sp)
	jsr 1073816148
	lea (24,%sp),%sp
	addq.l #1,%d2
	addq.l #5,%a2
	moveq #8,%d0
	cmp.l %d2,%d0
	jne .Lrt_251
	jra .Lrt_258
.Lrt_257:
	pea 1.w
	pea 4(%a3)
	pea 8.w
	pea -2(%a3)
	pea 4.w
	move.l %d0,-(%sp)
	jsr 1073816148
	move.w #11,%a2
	move.b %d4,(%a4)
	clr.b %d0
	moveq #1,%d4
	lsl.l %d7,%d4
	move.l %a4,-(%sp)
	pea .Lrt_C0
	move.l %a4,-(%sp)
	pea 1.w
	clr.l -(%sp)
	move.l %d2,-(%sp)
	pea 5.w
	clr.l %d2
	move.l rt_fb,-(%sp)
	move.l #1074505846,-(%sp)
	move.b %d0,rt_s1+1
	jsr 1073821956
	lea (60,%sp),%sp
	lea rt_v,%a6
	move.l %d7,44(%sp)
	jra .Lrt_251
	.align	2
	.globl	rt_key
rt_key:
	move.l %d2,-(%sp)
	moveq #51,%d1
	move.l 8(%sp),%d0
	cmp.l %d0,%d1
	jeq .Lrt_260
	jcs .Lrt_261
	moveq #32,%d2
	cmp.l %d0,%d2
	jeq .Lrt_262
	moveq #33,%d1
	cmp.l %d0,%d1
	jne .Lrt_273
	move.b rt_cx,%d0
	moveq #6,%d2
	mvz.b %d0,%d1
	cmp.l %d1,%d2
	jcs .Lrt_266
	addq.l #1,%d0
	move.b %d0,rt_cx
.Lrt_266:
	moveq #1,%d0
.Lrt_259:
	move.l (%sp)+,%d2
	rts
.Lrt_261:
	moveq #52,%d2
	cmp.l %d0,%d2
	jne .Lrt_273
	move.b rt_cx,%d0
	jeq .Lrt_266
	subq.l #1,%d0
	move.b %d0,rt_cx
	moveq #1,%d0
	jra .Lrt_259
.Lrt_273:
	move.l (%sp)+,%d2
	clr.l %d0
	rts
.Lrt_260:
	move.b rt_cy,%d0
	jeq .Lrt_266
	subq.l #1,%d0
	move.b %d0,rt_cy
	moveq #1,%d0
	jra .Lrt_259
.Lrt_262:
	move.b rt_cy,%d0
	moveq #6,%d2
	mvz.b %d0,%d1
	cmp.l %d1,%d2
	jcs .Lrt_266
	addq.l #1,%d0
	move.b %d0,rt_cy
	moveq #1,%d0
	jra .Lrt_259
	.align	2
	.globl	rt_yes
rt_yes:
	lea (-36,%sp),%sp
	movem.l #15484,(%sp)
	moveq #7,%d2
	lea (rt_ks0),%a0
	move.b -2147483648,%d0
	move.l 1187521622,%a1
	add.l #586338,%a1
	move.b -2147483645,%d1
	and.l %d2,%d0
	moveq #3,%d2
	and.l %d2,%d1
	move.l #6322,%d2
	mulu.w #36,%d0
	muls.l %d2,%d1
	add.l %d1,%a1
	add.l %d0,%a1
.Lrt_278:
	mvz.b (%a0)+,%d1
	move.l %d1,%d0
	add.l #293820205,%d0
	lsl.l #2,%d0
	lea (%a1,%d1.l),%a2
	move.l %d0,%a3
	move.l (%a3),%d1
	move.b (%a2),%d0
	mvz.b %d1,%d1
	mvz.b %d0,%d0
	cmp.l %d1,%d0
	jne .Lrt_282
	cmp.l #rt_ks0+4,%a0
	jne .Lrt_278
	move.b rt_cx,%d4
	move.b rt_cy,%d5
	moveq #7,%d0
	moveq #1,%d3
	lea rt_v,%a0
	and.l %d0,%d4
	and.l %d0,%d5
	move.l (%a0,%d4.l*4),%a3
	lsl.l %d5,%d3
	move.l (%a3),%d6
	mvz.b %d6,%d6
	move.l %d3,%d0
	and.l %d6,%d0
	tst.l %d0
	jeq .Lrt_279
	mvz.b %d4,%d4
	clr.l %d2
	lea rt_on,%a2
	lea rt_osrc,%a5
	lea rt_stop,%a4
.Lrt_281:
	mvz.b (%a2,%d2.l),%d0
	and.l %d3,%d0
	tst.l %d0
	jeq .Lrt_280
	mvz.b (%a5,%d2.l),%d0
	cmp.l %d4,%d0
	jeq .Lrt_293
.Lrt_280:
	addq.l #1,%d2
	cmp.l #2048,%d2
	jne .Lrt_281
.Lrt_279:
	eor.l %d6,%d3
	moveq #1,%d0
	move.l %d3,(%a3)
	movem.l (%sp),#15484
	lea (36,%sp),%sp
	rts
.Lrt_293:
	move.l %d2,-(%sp)
	move.l %d5,-(%sp)
	jsr (%a4)
	addq.l #8,%sp
	addq.l #1,%d2
	cmp.l #2048,%d2
	jne .Lrt_281
	jra .Lrt_279
.Lrt_282:
	movem.l (%sp),#15484
	clr.l %d0
	lea (36,%sp),%sp
	rts
	.align	2
	.globl	rt_knob
rt_knob:
	move.b rt_cx,%d0
	move.l %d2,-(%sp)
	moveq #7,%d2
	move.l 12(%sp),%d1
	lea rt_v,%a0
	and.l %d2,%d0
	moveq #3,%d2
	cmp.l 8(%sp),%d2
	jeq .Lrt_304
	move.l 64(%a0,%d0.l*4),%a0
	add.l %d1,(%a0)
	move.l (%a0),%d0
	moveq #3,%d1
	cmp.l %d0,%d1
	jlt .Lrt_305
.Lrt_299:
	tst.l %d0
	jlt .Lrt_306
	move.l (%sp)+,%d2
	move.l %d0,(%a0)
	rts
.Lrt_306:
	move.l (%sp)+,%d2
	clr.l %d0
	move.l %d0,(%a0)
	rts
.Lrt_305:
	move.l (%sp)+,%d2
	moveq #3,%d0
	move.l %d0,(%a0)
	rts
.Lrt_304:
	move.l 32(%a0,%d0.l*4),%a0
	add.l %d1,(%a0)
	move.l (%a0),%d0
	tst.l %d0
	jle .Lrt_299
	move.l (%sp)+,%d2
	moveq #1,%d0
	move.l %d0,(%a0)
	rts
	.align	2
	.globl	rt_value
rt_value:
	move.b rt_cx,%d0
	moveq #7,%d1
	lea rt_v,%a0
	and.l %d1,%d0
	moveq #3,%d1
	cmp.l 4(%sp),%d1
	jeq .Lrt_312
	move.l 64(%a0,%d0.l*4),%a0
	move.l (%a0),%d0
	rts
.Lrt_312:
	move.l 32(%a0,%d0.l*4),%a0
	move.l (%a0),%d0
	rts
rt_ks0:
	.string	""
	.ascii	"\001\002\004"
	.balign 1
rt_s1:
	.fill 2,1,0
rt_pc2:
	.string	"\t\013"
	.ascii	"\002\004\005\007"
	.balign 2
rt_fb:
	.fill 4,1,0
	.globl	rt_held
rt_held:
	.fill	8,1,0
	.globl	rt_osrc
rt_osrc:
	.fill	2048,1,0
	.globl	rt_on
rt_on:
	.fill	2048,1,0
	.globl	rt_stk
rt_stk:
	.ascii	"\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377"
	.ascii	"\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377"
	.ascii	"\377\377"
	.ascii	"\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377"
	.ascii	"\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377"
	.ascii	"\377\377"
	.ascii	"\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377"
	.ascii	"\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377"
	.ascii	"\377\377"
	.ascii	"\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377"
	.ascii	"\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377"
	.ascii	"\377\377"
	.ascii	"\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377"
	.ascii	"\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377"
	.ascii	"\377\377"
	.ascii	"\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377"
	.ascii	"\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377"
	.ascii	"\377\377"
	.ascii	"\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377"
	.ascii	"\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377"
	.ascii	"\377\377"
	.ascii	"\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377"
	.ascii	"\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377"
	.ascii	"\377\377"
	.globl	rt_cy
rt_cy:
	.fill	1,1,0
	.globl	rt_cx
rt_cx:
	.fill	1,1,0
	.globl	rt_offs
	.align	2
rt_offs:
	.fill	4,1,0
	.globl	rt_notes
	.align	2
rt_notes:
	.fill	4,1,0
	.globl	rt_clock
	.align	2
rt_clock:
	.fill	4,1,0
	.globl	rt_age
	.align	2
rt_age:
	.fill	32,1,0
	.globl	rt_src
rt_src:
	.fill	8,1,0
	.globl	rt_chan
rt_chan:
	.fill	8,1,0
	.globl	rt_note
rt_note:
	.ascii	"\377\377\377\377\377\377\377\377"
	.weak	mu_is_ms
	.weak	mu_note
