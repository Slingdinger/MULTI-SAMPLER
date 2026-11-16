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
rt_locks.part.0:
	lea (-36,%sp),%sp
	movem.l #7420,(%sp)
	move.l #2330,%d2
	move.l 40(%sp),%a4
	move.l %a4,%d1
	muls.l %d2,%d1
	moveq #15,%d2
	move.l #1187521622,%a0
	move.b -2147483644,%d0
	move.l %d1,%a3
	move.l (%a0),%a2
	and.l %d2,%d0
	move.l #36568,%d2
	muls.l %d2,%d0
	moveq #63,%d2
	add.l %d0,%a3
	add.l %a3,%a2
	move.b 80(%a2),%d6
	mvz.b %d6,%d6
	move.l %d6,%d1
	subq.l #1,%d1
	cmp.l %d1,%d2
	jcc .Lrt_61
	move.l (%a0),%a0
	add.l #36435,%a0
	add.l %d0,%a0
	move.b (%a0),%d6
	mvz.b %d6,%d6
	move.l %d6,%d0
	subq.l #1,%d0
	cmp.l %d0,%d2
	jcc .Lrt_61
	moveq #64,%d6
.Lrt_61:
	move.l #-2147457840,%a0
	moveq #7,%d1
	add.l %a4,%a0
	move.b (%a0),%d4
	mvz.b rt_src_now,%d0
	mvz.b %d4,%d4
	cmp.l %d0,%d1
	jcs .Lrt_62
	move.l %d0,%a0
	add.l #-2147457832,%a0
	move.b (%a0),%d0
	move.l %d4,%d1
	addq.l #1,%d1
	mvz.b %d0,%d0
	cmp.l %d0,%d1
	jeq .Lrt_74
	cmp.l %d4,%d6
	jeq .Lrt_90
.Lrt_62:
	tst.l %d4
	jne .Lrt_63
.Lrt_77:
	moveq #1,%d4
.Lrt_64:
	move.l %a2,%d7
	moveq #1,%d5
	clr.l rt_lockstep
	sub.l %a1,%a1
	add.l #32,%d7
.Lrt_70:
	move.l %d4,%d3
	moveq #7,%d0
	subq.l #1,%d3
	and.l %d3,%d0
	move.l %d3,%d2
	lsr.l #3,%d2
	moveq #7,%d1
	sub.l %d2,%d1
	move.l %d5,%d2
	lea (%a2,%d1.l),%a0
	add.l %d7,%d1
	lsl.l %d0,%d2
.Lrt_66:
	move.b (%a0),%d0
	addq.l #8,%a0
	and.l %d2,%d0
	tst.b %d0
	jne .Lrt_65
	cmp.l %d1,%a0
	jne .Lrt_66
	subq.l #1,%d4
	tst.l %d4
	jeq .Lrt_91
	move.l %d3,%d4
	addq.l #1,%a1
	cmp.l %d6,%a1
	jne .Lrt_70
.Lrt_60:
	movem.l (%sp),#7420
	lea (36,%sp),%sp
	rts
.Lrt_91:
	move.l %d6,%d4
	addq.l #1,%a1
	cmp.l %d6,%a1
	jne .Lrt_70
	jra .Lrt_60
.Lrt_65:
	move.l %d4,rt_lockstep
	move.l 1187521622,%a0
	move.l %a4,%d1
	lsl.l #5,%d3
	lsl.l #5,%d1
	lea 120(%a3,%a0.l),%a0
	move.l %a0,%d2
	add.l %d3,%d2
	sub.l %d2,%d1
	move.l %d2,%a0
	add.l #1187504090,%d1
	addq.l #1,%a0
	add.l #31,%d2
.Lrt_68:
	move.b (%a0),%d0
	lea (%a0,%d1.l),%a1
	mvz.b %d0,%d0
	cmp.l #255,%d0
	jeq .Lrt_71
	move.b (%a1),%d0
	mvz.b %d0,%d0
	cmp.l #255,%d0
	jeq .Lrt_92
.Lrt_71:
	addq.l #1,%a0
	cmp.l %a0,%d2
	jne .Lrt_68
.Lrt_93:
	movem.l (%sp),#7420
	lea (36,%sp),%sp
	rts
.Lrt_92:
	move.b (%a0),%d0
	addq.l #1,%a0
	move.b %d0,(%a1)
	cmp.l %a0,%d2
	jne .Lrt_68
	jra .Lrt_93
.Lrt_74:
	move.l %d0,%d4
.Lrt_63:
	cmp.l %d6,%d4
	jls .Lrt_64
	moveq #1,%d4
	jra .Lrt_64
.Lrt_90:
	subq.l #1,%d0
	tst.l %d0
	jeq .Lrt_77
	move.l %a2,%d7
	moveq #1,%d5
	clr.l rt_lockstep
	sub.l %a1,%a1
	add.l #32,%d7
	jra .Lrt_70
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
	jeq .Lrt_95
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
	jeq .Lrt_109
.Lrt_95:
	lea rt_note,%a0
	mvz.b (%a0,%d2.l),%d0
	cmp.l %d0,%d4
	jeq .Lrt_110
.Lrt_99:
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
.Lrt_110:
	lea rt_chan,%a1
	mvz.b (%a1,%d2.l),%d1
	move.l %d3,%d0
	lsr.l #7,%d0
	cmp.l %d1,%d0
	jne .Lrt_99
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
.Lrt_109:
	move.l %d2,-(%sp)
	jsr mu_is_ms
	addq.l #4,%sp
	tst.l %d0
	jne .Lrt_97
	add.l #24,%d4
.Lrt_97:
	clr.l -(%sp)
	move.l %d4,-(%sp)
	move.l %d2,-(%sp)
	jsr (%a2)
	lea (12,%sp),%sp
	lea rt_held,%a0
	move.b (%a0,%d2.l),%d0
	jeq .Lrt_99
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
	lea (-56,%sp),%sp
	movem.l #31996,(%sp)
	move.l 68(%sp),%d2
	lea (75,%sp),%a0
	move.l 64(%sp),%d3
	lsl.l #7,%d2
	move.b (%a0),rt_src_now
	move.l 60(%sp),%d4
	lea mu_note,%a2
	add.l %d3,%d2
	tst.l %a2
	jeq .Lrt_112
	move.l 1187521622,%a0
	moveq #3,%d1
	move.b -2147483645,%d0
	add.l #585122,%a0
	add.l %d4,%a0
	and.l %d1,%d0
	move.l #6322,%d1
	muls.l %d1,%d0
	add.l %d0,%a0
	move.b (%a0),%d0
	mvz.b %d0,%d0
	subq.l #5,%d0
	tst.l %d0
	jeq .Lrt_155
.Lrt_112:
	lea rt_note,%a2
	mvz.b (%a2,%d4.l),%d0
	lea rt_chan,%a3
	cmp.l #255,%d0
	jne .Lrt_115
	move.l 1187521622,%a0
	moveq #3,%d1
	move.b -2147483645,%d0
	move.l %d4,%d6
	lsl.l #5,%d6
	and.l %d1,%d0
	move.l #6322,%d1
	move.l %d6,%a4
	add.l #1187504090,%a4
	muls.l %d1,%d0
	add.l %a0,%d0
	move.l %d4,%a0
	add.l #585122,%a0
	add.l %d0,%a0
	move.b (%a0),%d5
	mvz.b %d5,%d5
	subq.l #1,%d5
	tst.l %d5
	jeq .Lrt_156
.Lrt_119:
	move.l %d3,%d0
	moveq #-12,%d1
	add.l #-60,%d0
	cmp.l %d0,%d1
	jle .Lrt_138
	moveq #-12,%d0
.Lrt_139:
	muls.w #5,%d0
	add.l #64,%d0
	move.b %d0,(%a4)
.Lrt_123:
	moveq #7,%d1
	cmp.l %d4,%d1
	jcs .Lrt_137
	move.l %d4,-(%sp)
	jsr (rt_locks.part.0)
	addq.l #4,%sp
.Lrt_137:
	pea -1.w
	pea 1.w
	pea 29.w
	move.l %d4,-(%sp)
	jsr 1073762352
	moveq #1,%d0
	lea (87,%sp),%a0
	move.b (%a0),(%a3,%d4.l)
	lea rt_held,%a0
	move.b %d3,(%a2,%d4.l)
	lea (16,%sp),%sp
	move.b %d0,(%a0,%d4.l)
.Lrt_118:
	lea rt_on,%a0
	moveq #1,%d0
	move.b (%a0,%d2.l),%d3
	lsl.l %d4,%d0
	move.l rt_clock,%a1
	addq.l #1,%a1
	lea rt_age,%a2
	move.l %a1,(%a2,%d4.l*4)
	lea (75,%sp),%a3
	lea rt_src,%a2
	move.b (%a3),(%a2,%d4.l)
	lea rt_osrc,%a2
	move.b (%a3),(%a2,%d2.l)
	or.l %d3,%d0
	move.l %a1,rt_clock
	addq.l #1,rt_notes
	move.b %d0,(%a0,%d2.l)
.Lrt_111:
	movem.l (%sp),#31996
	lea (56,%sp),%sp
	rts
.Lrt_115:
	mvz.b (%a3,%d4.l),%d5
	move.l %d4,%d6
	lsl.l #5,%d6
	lsl.l #7,%d5
	move.l %d6,%a4
	add.l #1187504090,%a4
	move.l %d5,%a0
	pea (%a0,%d0.l)
	move.l %d4,-(%sp)
	jsr rt_stop
	addq.l #8,%sp
	move.l 1187521622,%a0
	moveq #3,%d1
	move.b -2147483645,%d0
	and.l %d1,%d0
	move.l #6322,%d1
	muls.l %d1,%d0
	add.l %a0,%d0
	move.l %d4,%a0
	add.l #585122,%a0
	add.l %d0,%a0
	move.b (%a0),%d5
	mvz.b %d5,%d5
	subq.l #1,%d5
	tst.l %d5
	jne .Lrt_119
	jra .Lrt_156
.Lrt_155:
	move.l %d4,-(%sp)
	jsr mu_is_ms
	addq.l #4,%sp
	tst.l %d0
	jeq .Lrt_113
.Lrt_114:
	pea 1.w
	move.l %d3,-(%sp)
	move.l %d4,-(%sp)
	jsr (%a2)
	lea (12,%sp),%sp
	tst.l %d0
	jeq .Lrt_111
	lea rt_held,%a0
	moveq #7,%d1
	move.b (%a0,%d4.l),%d0
	mvz.b %d0,%d3
	cmp.l %d3,%d1
	jcs .Lrt_118
	addq.l #1,%d0
	move.b %d0,(%a0,%d4.l)
	lea rt_on,%a0
	moveq #1,%d0
	move.b (%a0,%d2.l),%d3
	lsl.l %d4,%d0
	move.l rt_clock,%a1
	addq.l #1,%a1
	lea rt_age,%a2
	move.l %a1,(%a2,%d4.l*4)
	lea (75,%sp),%a3
	lea rt_src,%a2
	move.b (%a3),(%a2,%d4.l)
	lea rt_osrc,%a2
	move.b (%a3),(%a2,%d2.l)
	or.l %d3,%d0
	move.l %a1,rt_clock
	addq.l #1,rt_notes
	move.b %d0,(%a0,%d2.l)
	jra .Lrt_111
.Lrt_156:
	move.l %d4,%d5
	lsl.l #2,%d5
	move.l %d5,%a0
	add.l %d4,%a0
	add.l #585803,%a0
	add.l %d0,%a0
	move.b (%a0),%d0
	mvz.b %d0,%d1
	move.l %d1,%a5
	tst.b %d0
	jlt .Lrt_119
	pea 52(%sp)
	pea 52(%sp)
	move.l %d1,-(%sp)
	jsr rt_name
	lea (12,%sp),%sp
	tst.l %d0
	jlt .Lrt_119
	move.l %a5,%d5
	lea rt_same,%a6
.Lrt_127:
	move.l %d5,%d7
	subq.l #1,%d7
	tst.l %d5
	jeq .Lrt_128
	move.l %a5,-(%sp)
	move.l %d7,-(%sp)
	jsr (%a6)
	addq.l #8,%sp
	tst.l %d0
	jeq .Lrt_128
	move.l %d7,%d5
	jra .Lrt_127
.Lrt_138:
	moveq #12,%d1
	cmp.l %d0,%d1
	jge .Lrt_139
	moveq #12,%d0
	muls.w #5,%d0
	add.l #64,%d0
	move.b %d0,(%a4)
	jra .Lrt_123
.Lrt_113:
	add.l #24,%d3
	jra .Lrt_114
.Lrt_128:
	move.l %a5,%d7
.Lrt_126:
	move.l %d7,%a6
	moveq #127,%d0
	addq.l #1,%a6
	cmp.l %d7,%d0
	jeq .Lrt_130
	move.l %a5,-(%sp)
	move.l %a6,-(%sp)
	jsr rt_same
	addq.l #8,%sp
	tst.l %d0
	jeq .Lrt_157
	move.l %a6,%d7
	jra .Lrt_126
.Lrt_157:
	cmp.l %d7,%d5
	jhi .Lrt_119
.Lrt_130:
	moveq #60,%d1
	move.l %d1,44(%sp)
	move.w #1000,%a6
	pea 52(%sp)
	pea 52(%sp)
	move.l %d5,-(%sp)
	jsr rt_name
	move.w #-1,%a5
	lea (12,%sp),%sp
	move.l %d3,%a0
	move.l %d5,%a1
	sub.l %d0,%a0
	addq.l #1,%a1
	tst.l %a0
	jlt .Lrt_158
.Lrt_132:
	cmp.l %a0,%a6
	jle .Lrt_133
	move.l %d5,%a5
	move.l %a0,%a6
	move.l %d0,44(%sp)
.Lrt_133:
	cmp.l %d5,%d7
	jeq .Lrt_159
	pea 52(%sp)
	move.l %a1,%d5
	pea 52(%sp)
	move.l %d5,-(%sp)
	jsr rt_name
	lea (12,%sp),%sp
	move.l %d3,%a0
	move.l %d5,%a1
	sub.l %d0,%a0
	addq.l #1,%a1
	tst.l %a0
	jge .Lrt_132
.Lrt_158:
	move.l %d0,%a0
	sub.l %d3,%a0
	jra .Lrt_132
.Lrt_159:
	move.l %d3,%d0
	moveq #-12,%d1
	sub.l 44(%sp),%d0
	cmp.l %d0,%d1
	jle .Lrt_135
	moveq #-12,%d0
.Lrt_136:
	muls.w #5,%d0
	add.l #64,%d0
	move.b %d0,(%a4)
	tst.l %a5
	jlt .Lrt_123
	move.w %a5,%d0
	move.l %d6,%a0
	add.l #1187504121,%a0
	move.b %d0,(%a0)
	jra .Lrt_123
.Lrt_135:
	moveq #12,%d1
	cmp.l %d0,%d1
	jge .Lrt_136
	moveq #12,%d0
	jra .Lrt_136
	.align	2
	.globl	rt_locks
rt_locks:
	move.l 4(%sp),%d0
	moveq #7,%d1
	cmp.l %d0,%d1
	jcs .Lrt_160
	move.l %d0,4(%sp)
	jra (rt_locks.part.0)
.Lrt_160:
	rts
	.align	2
	.globl	rt_route
rt_route:
	lea (-44,%sp),%sp
	moveq #3,%d0
	movem.l #15612,(%sp)
	move.l 60(%sp),%a2
	cmp.l 56(%sp),%d0
	jne .Lrt_165
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
	jeq .Lrt_254
	cmp.l #128,%d1
	jeq .Lrt_167
.Lrt_165:
	movem.l (%sp),#15612
	clr.l %d0
	lea (44,%sp),%sp
	rts
.Lrt_167:
	lea rt_on,%a0
	mvz.b (%a0,%d3.l),%d4
	tst.l %d4
	jeq .Lrt_165
	lea rt_osrc,%a0
	clr.l %d2
	mvz.b (%a0,%d3.l),%d5
	lea rt_stop,%a3
.Lrt_188:
	btst %d2,%d4
	jne .Lrt_255
.Lrt_187:
	addq.l #1,%d2
	moveq #8,%d7
	cmp.l %d2,%d7
	jne .Lrt_188
	lea rt_v,%a0
	moveq #3,%d0
	move.l 64(%a0,%d5.l*4),%a0
	moveq #1,%d1
	and.l (%a0),%d0
	cmp.l %d0,%d1
	jeq .Lrt_182
.Lrt_250:
	moveq #2,%d3
	cmp.l %d0,%d3
	jeq .Lrt_183
	tst.l %d0
	jne .Lrt_165
	moveq #1,%d0
.Lrt_258:
	movem.l (%sp),#15612
	lea (44,%sp),%sp
	rts
.Lrt_255:
	move.l %d3,-(%sp)
	move.l %d2,-(%sp)
	jsr (%a3)
	addq.l #8,%sp
	jra .Lrt_187
.Lrt_254:
	tst.b 2(%a2)
	jeq .Lrt_167
	move.l 48(%sp),%d7
	cmp.l #1074396082,%d7
	jeq .Lrt_168
	cmp.l #1074396410,%d7
	jeq .Lrt_168
	cmp.l #1074391706,%d7
	jne .Lrt_165
.Lrt_168:
	moveq #7,%d1
	cmp.l 52(%sp),%d1
	jcs .Lrt_165
	move.l 52(%sp),%d4
	lea rt_v,%a3
	move.l (%a3,%d4.l*4),%a0
	move.l (%a0),%d5
	mvz.b %d5,%d5
	tst.l %d5
	jeq .Lrt_165
	lea rt_on,%a4
	move.b (%a4,%d3.l),%d1
	jeq .Lrt_169
	mvz.b %d1,%d1
	clr.l %d4
	lea rt_stop,%a5
	btst %d4,%d1
	jne .Lrt_256
.Lrt_170:
	addq.l #1,%d4
	moveq #8,%d7
	cmp.l %d4,%d7
	jeq .Lrt_169
	move.b (%a4,%d3.l),%d1
	mvz.b %d1,%d1
	btst %d4,%d1
	jeq .Lrt_170
	jra .Lrt_256
.Lrt_169:
	move.l 52(%sp),%d1
	move.l 32(%a3,%d1.l*4),%a0
	tst.l (%a0)
	jne .Lrt_190
	clr.l %d3
	lea rt_play,%a4
.Lrt_174:
	btst %d3,%d5
	jne .Lrt_257
	addq.l #1,%d3
	moveq #8,%d4
	cmp.l %d3,%d4
	jne .Lrt_174
.Lrt_175:
	move.l 52(%sp),%d0
	moveq #1,%d1
	move.l 64(%a3,%d0.l*4),%a0
	moveq #3,%d0
	and.l (%a0),%d0
	cmp.l %d0,%d1
	jne .Lrt_250
.Lrt_182:
	move.l %a2,-(%sp)
	pea 3.w
	jsr rt_din
	addq.l #8,%sp
	moveq #1,%d0
	jra .Lrt_258
.Lrt_256:
	move.l %d3,-(%sp)
	move.l %d4,-(%sp)
	move.l %d0,48(%sp)
	jsr (%a5)
	addq.l #8,%sp
	move.l 40(%sp),%d0
	jra .Lrt_170
.Lrt_183:
	move.l %a2,-(%sp)
	pea 3.w
	jsr rt_usb
	addq.l #8,%sp
	moveq #1,%d0
	jra .Lrt_258
.Lrt_257:
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
	jne .Lrt_174
	jra .Lrt_175
.Lrt_190:
	clr.l %d1
	lea rt_held,%a4
	lea mu_note,%a1
.Lrt_172:
	move.l %d5,%d3
	lsr.l %d1,%d3
	moveq #1,%d4
	and.l %d3,%d4
	btst #0,%d3
	jne .Lrt_259
.Lrt_176:
	addq.l #1,%d1
	moveq #8,%d3
	cmp.l %d1,%d3
	jne .Lrt_172
	move.w #-1,%a1
	clr.l %d3
	lea rt_age,%a4
.Lrt_180:
	btst %d3,%d5
	jeq .Lrt_179
	move.l (%a4,%d3.l*4),%a0
	cmp.l %a1,%a0
	jcc .Lrt_179
	move.l %d3,%d1
	move.l %a0,%a1
.Lrt_179:
	addq.l #1,%d3
	moveq #8,%d4
	cmp.l %d3,%d4
	jne .Lrt_180
	moveq #7,%d7
	cmp.l %d1,%d7
	jcs .Lrt_175
	move.l 52(%sp),-(%sp)
	move.l %d0,-(%sp)
	move.l %d2,-(%sp)
	move.l %d1,-(%sp)
	jsr rt_play
	lea (16,%sp),%sp
.Lrt_261:
	moveq #1,%d1
	move.l 52(%sp),%d0
	move.l 64(%a3,%d0.l*4),%a0
	moveq #3,%d0
	and.l (%a0),%d0
	cmp.l %d0,%d1
	jne .Lrt_250
	jra .Lrt_182
.Lrt_259:
	mvz.b (%a4,%d1.l),%d6
	tst.l %a1
	jeq .Lrt_177
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
	jeq .Lrt_260
.Lrt_177:
	cmp.l %d6,%d4
	jls .Lrt_176
.Lrt_253:
	move.l 52(%sp),-(%sp)
	move.l %d0,-(%sp)
	move.l %d2,-(%sp)
	move.l %d1,-(%sp)
	jsr rt_play
	lea (16,%sp),%sp
	jra .Lrt_261
.Lrt_260:
	moveq #8,%d4
	cmp.l %d6,%d4
	jhi .Lrt_253
	jra .Lrt_176
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
.Lrt_268:
	move.l %d7,%d4
	move.l %a3,%d2
	add.l #49,%d4
	move.l rt_fb,%d0
	subq.l #1,%d2
	cmp.l %d7,%a5
	jeq .Lrt_273
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
.Lrt_267:
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
	jeq .Lrt_265
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
	jne .Lrt_267
.Lrt_274:
	move.l 44(%sp),%d7
	subq.l #6,%a3
	addq.l #1,%d7
	subq.l #6,%d6
	subq.l #6,%d3
	tst.l %a3
	jne .Lrt_268
	movem.l (%sp),#31996
	lea (48,%sp),%sp
	rts
.Lrt_265:
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
	jne .Lrt_267
	jra .Lrt_274
.Lrt_273:
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
	jra .Lrt_267
	.align	2
	.globl	rt_key
rt_key:
	move.l %d2,-(%sp)
	moveq #51,%d1
	move.l 8(%sp),%d0
	cmp.l %d0,%d1
	jeq .Lrt_276
	jcs .Lrt_277
	moveq #32,%d2
	cmp.l %d0,%d2
	jeq .Lrt_278
	moveq #33,%d1
	cmp.l %d0,%d1
	jne .Lrt_289
	move.b rt_cx,%d0
	moveq #6,%d2
	mvz.b %d0,%d1
	cmp.l %d1,%d2
	jcs .Lrt_282
	addq.l #1,%d0
	move.b %d0,rt_cx
.Lrt_282:
	moveq #1,%d0
.Lrt_275:
	move.l (%sp)+,%d2
	rts
.Lrt_277:
	moveq #52,%d2
	cmp.l %d0,%d2
	jne .Lrt_289
	move.b rt_cx,%d0
	jeq .Lrt_282
	subq.l #1,%d0
	move.b %d0,rt_cx
	moveq #1,%d0
	jra .Lrt_275
.Lrt_289:
	move.l (%sp)+,%d2
	clr.l %d0
	rts
.Lrt_276:
	move.b rt_cy,%d0
	jeq .Lrt_282
	subq.l #1,%d0
	move.b %d0,rt_cy
	moveq #1,%d0
	jra .Lrt_275
.Lrt_278:
	move.b rt_cy,%d0
	moveq #6,%d2
	mvz.b %d0,%d1
	cmp.l %d1,%d2
	jcs .Lrt_282
	addq.l #1,%d0
	move.b %d0,rt_cy
	moveq #1,%d0
	jra .Lrt_275
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
.Lrt_294:
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
	jne .Lrt_298
	cmp.l #rt_ks0+4,%a0
	jne .Lrt_294
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
	jeq .Lrt_295
	mvz.b %d4,%d4
	clr.l %d2
	lea rt_on,%a2
	lea rt_osrc,%a5
	lea rt_stop,%a4
.Lrt_297:
	mvz.b (%a2,%d2.l),%d0
	and.l %d3,%d0
	tst.l %d0
	jeq .Lrt_296
	mvz.b (%a5,%d2.l),%d0
	cmp.l %d4,%d0
	jeq .Lrt_309
.Lrt_296:
	addq.l #1,%d2
	cmp.l #2048,%d2
	jne .Lrt_297
.Lrt_295:
	eor.l %d6,%d3
	moveq #1,%d0
	move.l %d3,(%a3)
	movem.l (%sp),#15484
	lea (36,%sp),%sp
	rts
.Lrt_309:
	move.l %d2,-(%sp)
	move.l %d5,-(%sp)
	jsr (%a4)
	addq.l #8,%sp
	addq.l #1,%d2
	cmp.l #2048,%d2
	jne .Lrt_297
	jra .Lrt_295
.Lrt_298:
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
	jeq .Lrt_320
	move.l 64(%a0,%d0.l*4),%a0
	add.l %d1,(%a0)
	move.l (%a0),%d0
	moveq #3,%d1
	cmp.l %d0,%d1
	jlt .Lrt_321
.Lrt_315:
	tst.l %d0
	jlt .Lrt_322
	move.l (%sp)+,%d2
	move.l %d0,(%a0)
	rts
.Lrt_322:
	move.l (%sp)+,%d2
	clr.l %d0
	move.l %d0,(%a0)
	rts
.Lrt_321:
	move.l (%sp)+,%d2
	moveq #3,%d0
	move.l %d0,(%a0)
	rts
.Lrt_320:
	move.l 32(%a0,%d0.l*4),%a0
	add.l %d1,(%a0)
	move.l (%a0),%d0
	tst.l %d0
	jle .Lrt_315
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
	jeq .Lrt_328
	move.l 64(%a0,%d0.l*4),%a0
	move.l (%a0),%d0
	rts
.Lrt_328:
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
	.globl	rt_lockstep
	.align	2
rt_lockstep:
	.fill	4,1,0
	.globl	rt_src_now
rt_src_now:
	.byte	-1
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
