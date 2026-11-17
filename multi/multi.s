| MULTI (OctaZach 208): a one-track eight-voice multisampler, forked from repeat98's POLY MACHINE
| (octamad poly-machine 887a237, image 94; MIT): seven extension voices where POLY had three, the
| extensions mixed one at a time through one scratch buffer, a fast path for a voice at the primary's
| rate (no interpolation: a multisample's own note), and the multisample itself (mu.c: a track whose
| sample is named with a note plays the nearest-note slot of the run sharing its name). POLY's own
| description follows.
|
| POLY MACHINE -- four independent untimestretched playback positions per
| audio track.  The stock voice is always the newest voice.  Immediately
| before stock retriggers it, the active old state is copied into one of
| three rotating extension records.  The stock renderer then renders the
| primary and extension records into one track buffer, before the normal
| per-track FX chain.
|
| Each voice keeps the pitch it was triggered with: the stock renderer only
| fetches raw source frames and the DSP resamples the track by the primary's
| increment, so extensions are resampled here to the primary's source rate
| (.render_ext).  Chromatic presses -- panel keys and MIDI notes alike -- are
| queued so a chord is not collapsed into stock's one-command mailbox, and
| releases address the voice that owns the key.  RATE, sample selection and
| p-locks remain track-wide.
        .text
        .global mu_call
        .global mu_config_type
        .global mu_live_type
        .global mu_stop_voice
        .global mu_voice_trigger
        .global mu_machine_name
        .global mu_src_names
        .global mu_octave_button
        .global mu_sample_ui_init
        .global mu_sample_ui_left
        .global mu_sample_ui_right
        .global mu_src_cursor_scroll
        .global mu_src_cursor_draw
        .global mu_src_cursor_record
        .global mu_src_cursor_updown_old
        .global mu_src_cursor_updown_new
        .global mu_src_cursor_right
        .global mu_src_cursor_commit_list
        .global mu_src_cursor_slot_yes
        .global mu_src_cursor_slot_lookup
        .global mu_config_tstr
        .global mu_increment_shift
        .global mu_chromatic_key
        .global mu_chord_dequeue
        .global mu_midi_note_on
        .global mu_midi_note_off
        .global mu_release_held
        .global mu_kbd_fill
        .global mu_kbd_next
        .global mu_release_note,mu_relpend
        .global voice_pointer
        .global mu_voice_selector
        .global mu_extra_voices
        .global mu_scratch
        .global mu_next
        .global mu_press, mu_release
        .weak   rt_locks

| C ABI wrappers for MIDI ROUTING (mu.c's mu_note): (track, owner).
mu_press:
        move.l  4(%sp),%d0
        move.l  8(%sp),%d1
        bra.w   mu_press_key
mu_release:
        move.l  4(%sp),%d0
        move.l  8(%sp),%d1
        bra.w   mu_release_key

        .equ    VOICES, 0x800049d8
        .equ    STATES, 0x80004898
        .equ    LANES,  0x80000510
        .equ    BANK_PTR, 0x46c82456
        .equ    PART_INDEX, 0x100b14cf
        .equ    PART_STRIDE, 6322
        .equ    PART_MACHINE_OFF, 0x8eda2
        .equ    POLY_TYPE, 5
        .equ    RENDER, 0x40007960
        .equ    CONTINUE_CALLER, 0x400041cc
        .equ    CONTINUE_CONFIG_TYPE, 0x4000c0de
        .equ    CONTINUE_STOP, 0x40006828
        .equ    STOCK_STOP, 0x40006820
        .equ    CONTINUE_POINTER, 0x4000798a
        .equ    CONTINUE_TRIGGER, 0x4000f458
        .equ    CONTINUE_LIVE_TYPE, 0x4000bff0
        .equ    CONTINUE_NAME, 0x400334de
        .equ    CONTINUE_SRC_MACHINE_NAME, 0x4003c95a
        .equ    CONTINUE_OCTAVE_BUTTON, 0x40045920
        .equ    CONTINUE_SAMPLE_UI_INIT, 0x400788d6
        .equ    CONTINUE_SAMPLE_UI_LEFT, 0x40078956
        .equ    CONTINUE_SAMPLE_UI_RIGHT, 0x4007910a
        .equ    SAMPLE_UI_MACHINE, 0x460e738e
        .equ    SAMPLE_UI_PANE, 0x460e739a
        .equ    SRC_CURSOR, 0x460d5c30
        .equ    CONTINUE_CHROMATIC_KEY, 0x4004fb9c
        .equ    CONTINUE_CHORD_DEQUEUE, 0x4000b7c6
        .equ    PENDING_COMMANDS, 0x46c80354
        .equ    LIVE_LOCKS, 0x46c7dfda
        .equ    MIDI_GATES, 0x46c7fb08
        .equ    CONTINUE_MIDI_ON, 0x4000e74e
        .equ    MIDI_ON_HELD, 0x4000e75a
        .equ    MIDI_OFF_MATCH, 0x4000dfdc
        .equ    MIDI_OFF_NEXT, 0x4000dff8
| A voice's owning key: a panel chromatic key 0..135, or MIDI_KEY + note for
| a MIDI note (72..96 reach the chromatic path, so 0xc8..0xe0); 0xff = none.
        .equ    MIDI_KEY, 0x80
        .equ    PANEL_KEYS, 136
        .equ    VOICE_SIZE, 168
        .equ    EXTRA_PER_TRACK, 7
        .equ    EXTRA_TRACK_SIZE, 1176
        .equ    STATE_SIZE, 40
        .equ    MAX_SOURCE_FRAMES, 64
        .equ    FETCH_FRAMES, 96            | >= 16 * 4.0 + a ratio's slack

| MULTI ADSR (222). Detour 0x4004d948 (8 bytes: `link.w %fp,#-152` ; `movem.l %d2-%d7/%a2-%a5,(%sp)`), the
| main view's draw (its page knobs at 0x4004e5..): the AMP page's labels as the active track's machine
| wants them (mu_amp_ui, mu.c).
        .global mu_amp_draw,mu_dsp_hook
mu_amp_draw:
        jsr     mu_amp_ui
        link.w  %fp,#-152
        movem.l %d2-%d7/%a2-%a5,(%sp)
        jmp     (0x4004d950).l

| Detour 0x4000cb9a (6 bytes: `move.l #0x80001658,%d3`), the frame builder just after its copy of the
| tracks' parameter records (ping offset at 106(sp)): a MULTI track's record has no DSP envelope
| (mu_dsp_amp, mu.c).
mu_dsp_hook:
        lea     -16(%sp),%sp
        movem.l %d0-%d1/%a0-%a1,(%sp)
        move.l  122(%sp),-(%sp)
        jsr     mu_dsp_amp
        addq.l  #4,%sp
        movem.l (%sp),%d0-%d1/%a0-%a1
        lea     16(%sp),%sp
        move.l  #0x80001658,%d3
        jmp     (0x4000cba0).l

| d0 = track -> d0 = 1 when the current Part stores raw machine type 5.
| d1/a0 are scratch; all other registers are preserved.
mu_is_track:
        cmpi.l  #7,%d0
        bhi.s   .pit_no
        move.l  %d0,%d1
        movea.l (BANK_PTR).l,%a0
        moveq   #0,%d0
        move.b  (PART_INDEX).l,%d0
        move.l  %d2,-(%sp)
        move.l  #PART_STRIDE,%d2
        mulu.l  %d2,%d0
        move.l  (%sp)+,%d2
        adda.l  %d0,%a0
        adda.l  %d1,%a0
        adda.l  #PART_MACHINE_OFF,%a0
        moveq   #POLY_TYPE,%d0
        cmp.b   (%a0),%d0
        seq     %d0
        andi.l  #1,%d0
        rts
.pit_no:
        moveq   #0,%d0
        rts

| Detour at 0x4000bfe8, immediately after stock publishes the stored machine
| byte to its per-ping operational mirror.  Preserve raw type 5 in the Part
| for UI/persistence, but expose FLEX (1) to the stock builder and common
| voice initializer.  Those paths otherwise reject type 5 and clear playback.
mu_live_type:
        .word   0x7332,0x2800             | displaced mvs.b (a2,d2.l),d1
        cmpi.l  #POLY_TYPE,%d1
        bne.s   .plt_done
        moveq   #1,%d1
        move.b  %d1,(%a2,%d2.l)
.plt_done:
        moveq   #7,%d0                    | displaced instruction
        and.l   %d1,%d0                   | stock builder-table index mask
        jmp     (CONTINUE_LIVE_TYPE).l

| The Part retains raw type 5, but this routine walks machine-specific
| configuration arrays (sample-slot assignment, SRC setup, and attributes).
| Normalize its local machine index to FLEX so POLY consumes the same layout.
| Without this, type 5 indexes past the five stock rows and turns track N into
| sample slot N+1 after a project load.
mu_config_type:
        .word   0x7130,0x0800             | displaced mvs.b (a0,d0.l),d0
        cmpi.l  #POLY_TYPE,%d0
        bne.s   .pct_done
        moveq   #1,%d0
.pct_done:
        movea.l %d0,%a5                   | displaced instructions
        add.l   %d0,%d0
        jmp     (CONTINUE_CONFIG_TYPE).l

| Detour at 0x4000c140, right after the config walk copied the six SRC SETUP
| bytes (LOOP SLIC LEN RATE TSTR TSNS) to 0x80000830 + 72*track, from where
| every ping copies them to lane bytes 24..29.  POLY renders its extension
| voices untimestretched only, and the render hook fell back to one voice
| whenever lane TSTR (byte 28) was non-zero -- which the stock default AUTO
| is, so a new POLY track played mono.  Force the live TSTR to OFF for POLY;
| the Part keeps whatever the user set.
mu_config_tstr:
        move.l  114(%sp),%d2              | displaced: track
        move.l  %d2,%d0
        bsr.w   mu_is_track             | d1/a0 scratch, a0 reloaded below
        tst.l   %d0
        beq.s   .pcts_done
        move.l  %d2,%d0
        moveq   #72,%d1
        mulu.l  %d1,%d0
        lea     (0x80000834).l,%a0
        clr.b   (%a0,%d0.l)               | TSTR OFF in the live config
.pcts_done:
        lsl.l   #3,%d2                    | displaced
        jmp     (0x4000c146).l

| Detour at 0x40004100, where the increment builder recomputes a track's
| increment (only on a retrigger or a pitch change; otherwise it reuses
| STATES+36).  This is the ratio the DSP resamples the track with and the
| rate its source frames are fetched at, so a POLY key's octave shift must
| land HERE; applied anywhere later it reaches neither.  Capped below 4.0:
| the caller masks a chunk's source frames with 63, so 16 samples at 4.0
| would wrap to zero -- octaves beyond the cap are dropped.
        .equ    INCREMENT_CAP, 0x0fc00000
mu_increment_shift:
        .word   0xa1c0                    | displaced movclr.l %acc0,%d0
        asr.l   %d6,%d0                   | displaced
        lea     -12(%sp),%sp
        movem.l %d0-%d1/%a0,(%sp)
        move.l  64(%sp),%d0               | track (builder arg at 52)
        bsr.w   mu_is_track
        tst.l   %d0
        beq.s   .pis_done
        move.l  64(%sp),%d1
        lea     mu_primary_shift(%pc),%a0
        mvs.b   (%a0,%d1.l),%d1
        move.l  (%sp),%d0
        tst.l   %d1
        beq.s   .pis_cap
        bmi.s   .pis_down
.pis_up:
        cmpi.l  #INCREMENT_CAP/2,%d0
        bcc.s   .pis_cap
        add.l   %d0,%d0
        subq.l  #1,%d1
        bne.s   .pis_up
        bra.s   .pis_cap
.pis_down:
        lsr.l   #1,%d0
        addq.l  #1,%d1
        bne.s   .pis_down
.pis_cap:
        cmpi.l  #INCREMENT_CAP,%d0
        bcs.s   .pis_store
        lsr.l   #1,%d0
        bra.s   .pis_cap
.pis_store:
        move.l  %d0,(%sp)
.pis_done:
        movem.l (%sp),%d0-%d1/%a0
        lea     12(%sp),%sp
        move.l  %d0,36(%a3)               | displaced
        jmp     (0x40004108).l

| Stock's stop helper addresses only the primary voice by track. During an
| extension render, redirect that operation to the selected extension and do
| not clear the track's shared increment state. Selector zero is exactly stock.
mu_stop_voice:
        move.l  mu_voice_selector(%pc),%d0
        beq.s   .psv_stock
        move.l  4(%sp),%d1
        cmpi.l  #7,%d1
        bhi.s   .psv_stock
        subq.l  #1,%d0
        move.l  %d1,%a0
        lsl.l   #3,%d1
        sub.l   %a0,%d1                   | track * 7
        add.l   %d0,%d1                   | plus extension slot
        move.l  #VOICE_SIZE,%d0
        mulu.l  %d0,%d1
        lea     mu_extra_voices(%pc),%a0
        clr.b   (%a0,%d1.l)
        rts
.psv_stock:
        move.l  %a2,-(%sp)                | displaced prologue
        move.l  %d2,-(%sp)
        move.l  12(%sp),%d1
        jmp     (CONTINUE_STOP).l

| Detour at 0x4000f450, the shared sample-machine voice initializer.  Its
| first argument is the track at 4(sp).  Preserve the active primary before
| stock overwrites it, rotating through the three extension records.  This
| catches sequencer, manual and MIDI triggers at the common boundary.
mu_voice_trigger:
        lea     -24(%sp),%sp
        movem.l %d0-%d2/%a0-%a2,(%sp)
        move.l  28(%sp),%d2
        move.l  %d2,%d0
        bsr.w   mu_is_track
        tst.l   %d0
        beq.w   .pvt_done

        move.l  %d2,%d0
        move.l  #VOICE_SIZE,%d1
        mulu.l  %d1,%d0
        lea     (VOICES).l,%a0
        adda.l  %d0,%a0
        tst.b   (%a0)
        bne.s   .pvt_active
        lea     mu_prim_ok(%pc),%a2      | the new primary has not rendered
        clr.b   (%a2,%d2.l)
        bsr.w   .pvt_set_primary_note
        bsr.w   .pvt_set_primary_shift
        pea     255.w                    | MULTI ADSR (222): no voice moved
        bsr.w   .pvt_env
        addq.l  #4,%sp
        bra.w   .pvt_done
.pvt_active:

        lea     mu_next(%pc),%a1
        moveq   #0,%d0
        move.b  (%a1,%d2.l),%d0          | extension slot 0..2
        move.l  %d2,%d1
        lsl.l   #3,%d1
        sub.l   %d2,%d1                  | track * 7
        add.l   %d0,%d1                  | flat extension index

        addq.l  #1,%d0
        cmpi.l  #EXTRA_PER_TRACK,%d0
        bcs.s   .pvt_store_next
        moveq   #0,%d0
.pvt_store_next:
        move.b  %d0,(%a1,%d2.l)

| Associate the voice slot with its chromatic pitch so each held panel key
| can release its own voice instead of the stock "last key only" behavior.
        lea     mu_primary_note(%pc),%a2
        move.b  (%a2,%d2.l),%d0
        lea     mu_extra_note(%pc),%a2
        move.b  %d0,(%a2,%d1.l)
        bsr.w   .pvt_set_primary_note

        lea     mu_primary_shift(%pc),%a2
        move.b  (%a2,%d2.l),%d0
        lea     mu_extra_shift(%pc),%a2
        move.b  %d0,(%a2,%d1.l)
        bsr.w   .pvt_set_primary_shift
        move.l  %d1,%d0                  | MULTI ADSR (222): the old primary's envelope to slot d1 - 7 t
        move.l  %d2,-(%sp)
        lsl.l   #3,%d2
        sub.l   (%sp),%d2                | 7 t
        sub.l   %d2,%d0                  | the extension slot 0..6
        move.l  (%sp)+,%d2
        move.l  %d0,-(%sp)
        bsr.w   .pvt_env
        addq.l  #4,%sp

| The extension keeps the old primary's own increment, which the render
| publishes for that voice alone.  Measured order within a frame (octemu,
| 22 Sep 2026): consumer -> this initializer -> increment recompute ->
| render, so STATES+36 here still holds the OLD note's increment.  (Image 92
| took it from the last render instead; with keys pressed together the queue
| triggers the next note before the previous one has been rendered, the saved
| increment was 0, and that voice played DC and never ended.)
| MULTI (209): the increment the old primary was last RENDERED with (mu_call
| records it), when it has rendered since its trigger. STATES+36 here read 0
| or a stale value for a chord's later notes under the port (15 Nov 2026):
| their voices played at a wrong rate, grainy, and the rest fell to the slow
| path. STATES+36 stays the fallback (a trigger before any render).
        lea     mu_prim_ok(%pc),%a2
        tst.b   (%a2,%d2.l)
        beq.s   1f
        clr.b   (%a2,%d2.l)
        lea     mu_prim_inc(%pc),%a2
        move.l  (%a2,%d2.l*4),%d0
        bra.s   2f
1:      move.l  %d2,%d0
        lsl.l   #2,%d0
        add.l   %d2,%d0
        lsl.l   #3,%d0                  | track * 40
        lea     (STATES).l,%a2
        move.l  36(%a2,%d0.l),%d0
2:      lea     mu_extra_increment(%pc),%a2
        move.l  %d0,(%a2,%d1.l*4)

        move.l  %d1,%d0
        move.l  #VOICE_SIZE,%d2
        mulu.l  %d2,%d0
        lea     mu_extra_voices(%pc),%a1
        adda.l  %d0,%a1
        moveq   #41,%d0                   | 42 longs = 168 bytes
.pvt_copy:
        move.l  (%a0)+,(%a1)+
        subq.l  #1,%d0
        bpl.s   .pvt_copy
        lea     mu_ext_phase(%pc),%a1   | its resampler starts fresh
        clr.l   (%a1,%d1.l*4)
        lea     mu_ext_carry(%pc),%a1
        clr.l   (%a1,%d1.l*4)
        bra.s   .pvt_done

| A chromatic press leaves its key and octave shift pending; the trigger it
| causes consumes them.  Any other trigger (sequencer, MIDI, a trig key in
| another mode) finds none: no owning key, and no octave shift.
.pvt_set_primary_note:
        lea     mu_pending_key(%pc),%a2
        move.b  (%a2,%d2.l),%d0
        lea     mu_primary_note(%pc),%a2
        move.b  %d0,(%a2,%d2.l)
        moveq   #-1,%d0                   | consumed: 0xff = no key
        lea     mu_pending_key(%pc),%a2
        move.b  %d0,(%a2,%d2.l)
        rts

.pvt_set_primary_shift:
        lea     mu_pending_shift(%pc),%a2
        move.b  (%a2,%d2.l),%d0
        clr.b   (%a2,%d2.l)               | consumed
        lea     mu_primary_shift(%pc),%a2
        move.b  %d0,(%a2,%d2.l)
        rts

| mu_env_press(track d2, the primary's key, the slot at 4(sp)); keeps d1 a0 a2.
.pvt_env:
        lea     -8(%sp),%sp
        movem.l %d1/%a0,(%sp)
        move.l  12(%sp),-(%sp)
        lea     mu_primary_note(%pc),%a1
        moveq   #0,%d0
        move.b  (%a1,%d2.l),%d0
        move.l  %d0,-(%sp)
        move.l  %d2,-(%sp)
        jsr     mu_env_press
        lea     12(%sp),%sp
        movem.l (%sp),%d1/%a0
        lea     8(%sp),%sp
        rts

.pvt_done:
        movem.l (%sp),%d0-%d2/%a0-%a2
        lea     24(%sp),%sp
        lea     -60(%sp),%sp              | displaced initializer prologue
        movem.l %d2-%d7/%a2-%fp,(%sp)
        jmp     (CONTINUE_TRIGGER).l

| Detour at 0x400041c4.  The stock caller has already pushed six arguments:
| output, renderer arg2, track, source frames, output samples, and flags.
| There is no JSR return address because the detour jumps here.  The wrapper
| replays the displaced call cleanup itself.
mu_call:
        lea     -40(%sp),%sp
        movem.l %d2-%d7/%a2-%a5,(%sp)
        movea.l %sp,%a5                   | fixed frame; original args at +40
        move.l  48(%a5),%d2               | track
        cmpi.l  #7,%d2
        bhi.w   .mono
        move.l  %d2,%d0
        bsr.w   mu_is_track
        tst.l   %d0
        beq.w   .reset_mono

        move.l  %d2,%d0
        moveq   #48,%d1
        mulu.l  %d1,%d0
        lea     (LANES).l,%a0
        tst.b   28(%a0,%d0.l)             | POLY is TSTR OFF only
        bne.w   .reset_mono
        move.l  %d2,-(%sp)                | MULTI ADSR (222): ended voices stop, an owed release posts
        jsr     mu_env_pre
        addq.l  #4,%sp
        move.l  52(%a5),%d5               | rendered source frames, stereo
        beq.w   .mono
        cmpi.l  #MAX_SOURCE_FRAMES,%d5
        bhi.w   .reset_mono

        move.l  %d2,%d0
        move.l  #VOICE_SIZE,%d1
        mulu.l  %d1,%d0
        lea     (VOICES).l,%a3
        adda.l  %d0,%a3                   | stock primary voice
        move.l  %d2,%d0
        move.l  #EXTRA_TRACK_SIZE,%d1
        mulu.l  %d1,%d0
        lea     mu_extra_voices(%pc),%a2
        adda.l  %d0,%a2                   | first extension for this track

        moveq   #0,%d4                    | active count before this chunk
        tst.b   (%a3)
        beq.s   .count_ext
        addq.l  #1,%d4
.count_ext:
        movea.l %a2,%a0
        moveq   #EXTRA_PER_TRACK-1,%d0
.count_loop:
        tst.b   (%a0)
        beq.s   .count_next
        addq.l  #1,%d4
.count_next:
        lea     VOICE_SIZE(%a0),%a0
        subq.l  #1,%d0
        bpl.s   .count_loop
        tst.l   %d4
        beq.w   .mono                     | stock call clears the destination

        move.l  %d2,%d0
        move.l  %d0,%d1
        lsl.l   #2,%d0
        add.l   %d1,%d0
        lsl.l   #3,%d0                    | track * 40
        lea     (STATES).l,%a0
        move.l  36(%a0,%d0.l),%d7         | primary increment (octave applied)

| The renderer does not resample: it fetches RAW source frames (d5 of them,
| the count the caller derived from the primary's increment) and the DSP
| resamples the whole track by that one increment.  So the primary renders
| as stock does, and each extension fetches its own frame count and is
| resampled here to the primary's source rate before the mix (.render_ext).
| Gain (210): every voice at -6 dB (a shift by 1), however many sound, so a
| note's level no longer drops when another starts (208/209 scaled the mix
| by the voice count: /2, /4, /8 -- Zach's unit, 15 Nov 2026). The mix
| saturates instead of wrapping when the voices add past full scale.
        moveq   #1,%d6
.gain_done:
        clr.l   mu_voice_selector
        movea.l 40(%a5),%a4
        bsr.w   .render
        lea     mu_prim_inc(%pc),%a0      | the primary's rendered increment
        move.l  %d7,(%a0,%d2.l*4)
        lea     mu_prim_ok(%pc),%a0
        moveq   #1,%d0
        move.b  %d0,(%a0,%d2.l)
        clr.l   -(%sp)                    | MULTI ADSR (222): the primary's envelope, this chunk
        move.l  %d2,-(%sp)
        jsr     mu_env_step
        addq.l  #8,%sp
        movea.l 40(%a5),%a0
        cmpi.l  #65536,%d0
        bcs.s   .scale_env
        move.l  %d5,%d0
        lsl.l   #1,%d0
        subq.l  #1,%d0
.scale:
        move.l  (%a0),%d1
        asr.l   %d6,%d1
        move.l  %d1,(%a0)+
        subq.l  #1,%d0
        bpl.s   .scale
        bra.s   .ext_start
.scale_env:
        move.l  %d7,-(%sp)
        move.l  %d0,%d7
        lsr.l   #1,%d7                    | the gain with the -6 dB, Q16
        move.l  %d5,%d0
        lsl.l   #1,%d0
        subq.l  #1,%d0
1:      move.l  (%a0),%d1
        swap    %d1
        ext.l   %d1
        muls.l  %d7,%d1
        move.l  %d1,(%a0)+
        subq.l  #1,%d0
        bpl.s   1b
        move.l  (%sp)+,%d7
.ext_start:
        moveq   #1,%d3
        moveq   #0,%d4                    | the extension's offset from a2
.ext_loop:
        tst.b   (%a2,%d4.l)
        beq.w   .ext_next
        move.l  %d3,-(%sp)                | MULTI ADSR (222): this voice's envelope, this chunk
        move.l  %d2,-(%sp)
        jsr     mu_env_step
        addq.l  #8,%sp
        tst.l   %d0
        beq.w   .ext_next                 | silent: ends at the next chunk (mu_env_pre)
        move.l  %d0,-(%sp)
        move.l  %d3,mu_voice_selector
        bsr.w   .render_ext
        clr.l   mu_voice_selector
        move.l  (%sp)+,%d0
        movea.l 40(%a5),%a0
        lea     mu_scratch(%pc),%a1
        cmpi.l  #65536,%d0
        bcs.w   .mix_env
        move.l  %d5,%d0
        lsl.l   #1,%d0
        subq.l  #1,%d0
        move.l  %d2,-(%sp)
.mix:
        move.l  (%a1)+,%d1
        asr.l   %d6,%d1
        move.l  (%a0),%d2
        add.l   %d1,%d2
        bvc.s   1f
        move.l  #0x7fff0000,%d2           | past full scale: clip, never wrap
        tst.l   %d1
        bpl.s   1f
        move.l  #0x80000000,%d2
1:      move.l  %d2,(%a0)+
        subq.l  #1,%d0
        bpl.s   .mix
        move.l  (%sp)+,%d2
        bra.s   .ext_next
.mix_env:
        lea     -8(%sp),%sp
        movem.l %d2/%d7,(%sp)
        move.l  %d0,%d7
        lsr.l   #1,%d7                    | the gain with the -6 dB, Q16
        move.l  %d5,%d0
        lsl.l   #1,%d0
        subq.l  #1,%d0
2:      move.l  (%a1)+,%d1
        swap    %d1
        ext.l   %d1
        muls.l  %d7,%d1
        move.l  (%a0),%d2
        add.l   %d1,%d2
        bvc.s   3f
        move.l  #0x7fff0000,%d2
        tst.l   %d1
        bpl.s   3f
        move.l  #0x80000000,%d2
3:      move.l  %d2,(%a0)+
        subq.l  #1,%d0
        bpl.s   2b
        movem.l (%sp),%d2/%d7
        lea     8(%sp),%sp
.ext_next:
        addi.l  #VOICE_SIZE,%d4
        addq.l  #1,%d3
        cmpi.l  #EXTRA_PER_TRACK+1,%d3
        bcs.w   .ext_loop
        clr.l   mu_voice_selector
        bra.s   .done

.reset_mono:
        move.l  %d2,%d0
        move.l  #EXTRA_TRACK_SIZE,%d1
        mulu.l  %d1,%d0
        lea     mu_extra_voices(%pc),%a0
        adda.l  %d0,%a0
        moveq   #EXTRA_PER_TRACK-1,%d0
.rm_clear:
        clr.b   (%a0)
        lea     VOICE_SIZE(%a0),%a0
        subq.l  #1,%d0
        bpl.s   .rm_clear
        lea     mu_next(%pc),%a0
        clr.b   (%a0,%d2.l)
.mono:
        clr.l   mu_voice_selector
        movea.l 40(%a5),%a4
        bsr.s   .render
.done:
        clr.l   mu_voice_selector
        movem.l (%sp),%d2-%d7/%a2-%a5
        lea     40(%sp),%sp
        lea     24(%sp),%sp               | displaced caller cleanup
        jmp     (CONTINUE_CALLER).l

| Call the stock renderer with a fresh copy of the caller's six arguments.
| a5 remains the fixed wrapper frame and a4 selects the output buffer.
.render:
        move.l  60(%a5),-(%sp)
        move.l  56(%a5),-(%sp)
        move.l  52(%a5),-(%sp)
        move.l  48(%a5),-(%sp)
        move.l  44(%a5),-(%sp)
        move.l  %a4,-(%sp)
        jsr     (RENDER).l
        lea     24(%sp),%sp
        rts

| .render with the fetch count in d0 and the destination in a4.
.render_count:
        move.l  60(%a5),-(%sp)
        move.l  56(%a5),-(%sp)
        move.l  %d0,-(%sp)
        move.l  48(%a5),-(%sp)
        move.l  44(%a5),-(%sp)
        move.l  %a4,-(%sp)
        jsr     (RENDER).l
        lea     24(%sp),%sp
        rts

| Render extension d3 (1..3) of track d2 into mu_scratch + (d3-1)*512 as
| d5 stereo frames at the PRIMARY's source rate (d7 = primary increment).
|
| r = inc_ext / inc_primary (Q16).  Output frame j sits at p + j*r in the
| fetch buffer, linearly interpolated.  The renderer advances the voice by
| every frame it fetches, so nothing fetched may be dropped: the frames from
| the next start's floor onward (one or two) are carried to the next chunk,
| and p stays in [0,1) relative to the first carried frame.  A voice fresh
| from mu_voice_trigger has no carried frames and p = 0.
.render_ext:
        lea     -36(%sp),%sp
        movem.l %d2-%d7/%a2-%a4,(%sp)
        move.l  %d2,%d4
        lsl.l   #3,%d4
        sub.l   %d2,%d4                   | track * 7
        add.l   %d3,%d4
        subq.l  #1,%d4                    | d4 = flat extension index
        lea     mu_scratch(%pc),%a3     | a3 = output (the one scratch buffer)
        move.l  %d4,%d0
        move.l  #VOICE_SIZE,%d1
        mulu.l  %d1,%d0
        lea     mu_extra_voices(%pc),%a0
        tst.b   (%a0,%d0.l)
        bne.s   .re_active
        move.l  %d5,%d0                   | idle voice: silence
        bra.s   .re_zero_next
.re_zero:
        clr.l   (%a3)+
        clr.l   (%a3)+
.re_zero_next:
        subq.l  #1,%d0
        bpl.s   .re_zero
        bra.w   .re_out

.re_active:
| r16 = inc_ext * 65536 / inc_primary, with 32-bit divides: both >> 8, then
| the integer part and two 8-bit fraction digits.
        lea     mu_extra_increment(%pc),%a0
        move.l  (%a0,%d4.l*4),%d0
        lsr.l   #8,%d0                    | a
        move.l  %d7,%d1
        lsr.l   #8,%d1                    | b
        bne.s   .re_div
        move.l  #0x10000,%d6
        bra.s   .re_ratio_done
.re_div:
        move.l  %d0,%d3
        divu.l  %d1,%d3                   | q
        move.l  %d3,%d6
        swap    %d6
        clr.w   %d6                       | q << 16
        mulu.l  %d1,%d3
        sub.l   %d3,%d0                   | rem
        lsl.l   #8,%d0
        move.l  %d0,%d3
        divu.l  %d1,%d3                   | first fraction digit
        move.l  %d3,%d2
        lsl.l   #8,%d2
        add.l   %d2,%d6
        mulu.l  %d1,%d3
        sub.l   %d3,%d0
        lsl.l   #8,%d0
        divu.l  %d1,%d0                   | second fraction digit
        add.l   %d0,%d6                   | d6 = r
.re_ratio_done:
        tst.l   %d5
        beq.w   .re_out                   | nothing to produce this chunk

| MULTI's fast path: a voice at the primary's rate (a multisample's own note,
| PTCH 0, as the primary's) with no carried frames fetches its frames straight
| into the output, no interpolation.
        cmpi.l  #0x10000,%d6
        bne.s   .re_slow
        lea     mu_ext_carry(%pc),%a0
        tst.l   (%a0,%d4.l*4)
        bne.s   .re_slow
        lea     mu_ext_phase(%pc),%a0
        tst.l   (%a0,%d4.l*4)
        bne.s   .re_slow
        cmpi.l  #63,%d5
        bhi.s   .re_slow
        movea.l %a3,%a4
        move.l  %d5,%d0
        bsr.w   .render_count
        addq.l  #1,mu_fast
        bra.w   .re_out
.re_slow:
        addq.l  #1,mu_slow

| Carried frames go to the front of the fetch buffer.
        lea     mu_fetch(%pc),%a4
        lea     mu_ext_carry(%pc),%a0
        move.l  (%a0,%d4.l*4),%d2         | carried frames c (0..2)
        move.l  %d4,%d0
        lsl.l   #4,%d0                    | 16 bytes of history per voice
        lea     mu_ext_hist(%pc),%a0
        adda.l  %d0,%a0
        move.l  (%a0)+,(%a4)
        move.l  (%a0)+,4(%a4)
        move.l  (%a0)+,8(%a4)
        move.l  (%a0),12(%a4)

| last = max(floor(p+(N-1)r)+1, floor(p+N*r)); frames needed = last+1.
        lea     mu_ext_phase(%pc),%a0
        move.l  (%a0,%d4.l*4),%d3         | p
        move.l  %d5,%d0
        subq.l  #1,%d0
        mulu.l  %d6,%d0
        add.l   %d3,%d0
        clr.w   %d0
        swap    %d0
        addq.l  #1,%d0                    | m
        move.l  %d5,%d1
        mulu.l  %d6,%d1
        add.l   %d3,%d1
        clr.w   %d1
        swap    %d1                       | k
        cmp.l   %d1,%d0
        bcc.s   .re_last
        move.l  %d1,%d0
.re_last:
        addq.l  #1,%d0                    | total frames in the buffer
        cmpi.l  #FETCH_FRAMES,%d0
        bls.s   .re_total_ok
        move.l  #FETCH_FRAMES,%d0         | out of range: cap, never overrun
.re_total_ok:
        movea.l %d0,%a2                   | a2 = total
        sub.l   %d2,%d0                   | frames to fetch
        ble.s   .re_fetched
        move.l  %d2,%d1
        lsl.l   #3,%d1
        adda.l  %d1,%a4                   | fetch after the carried frames
.re_fetch:
        move.l  %d0,%d1
        cmpi.l  #63,%d1
        bls.s   .re_fetch_n
        moveq   #63,%d1
.re_fetch_n:
        sub.l   %d1,%d0
        move.l  %d0,-(%sp)
        move.l  %d1,-(%sp)
        move.l  %d1,%d0
        bsr.w   .render_count
        move.l  (%sp)+,%d1
        move.l  (%sp)+,%d0
        lsl.l   #3,%d1
        adda.l  %d1,%a4
        tst.l   %d0
        bgt.s   .re_fetch
.re_fetched:

| Interpolate d5 output frames.  Sample words are 16-bit PCM << 16, so the
| difference is taken on the top halves and scaled by a 13-bit fraction.
        lea     mu_fetch(%pc),%a4
        move.l  %d3,%d2                   | pos = p
        move.l  %d5,%d7
        subq.l  #1,%d7
.re_interp:
        move.l  %d2,%d0
        clr.w   %d0
        swap    %d0
        lsl.l   #3,%d0
        lea     (%a4,%d0.l),%a0           | &buf[floor(pos)]
        move.l  %d2,%d1
        andi.l  #0xffff,%d1
        lsr.l   #3,%d1                    | 13-bit fraction
        move.l  (%a0),%d3                 | left a
        move.l  8(%a0),%d0                | left b
        swap    %d0
        ext.l   %d0
        move.l  %d3,%d5
        swap    %d5
        ext.l   %d5
        sub.l   %d5,%d0
        muls.l  %d1,%d0
        asl.l   #3,%d0
        add.l   %d3,%d0
        move.l  %d0,(%a3)+
        move.l  4(%a0),%d3                | right a
        move.l  12(%a0),%d0               | right b
        swap    %d0
        ext.l   %d0
        move.l  %d3,%d5
        swap    %d5
        ext.l   %d5
        sub.l   %d5,%d0
        muls.l  %d1,%d0
        asl.l   #3,%d0
        add.l   %d3,%d0
        move.l  %d0,(%a3)+
        add.l   %d6,%d2
        subq.l  #1,%d7
        bpl.s   .re_interp

| Carry buf[k..total-1] and keep p in [0,1) relative to buf[k].
        move.l  %d2,%d0
        clr.w   %d0
        swap    %d0                       | k
        move.l  %a2,%d1
        subq.l  #1,%d1
        cmp.l   %d1,%d0
        bls.s   .re_k_ok
        move.l  %d1,%d0                   | capped fetch: hold at the end
.re_k_ok:
        andi.l  #0xffff,%d2
        lea     mu_ext_phase(%pc),%a0
        move.l  %d2,(%a0,%d4.l*4)
        move.l  %a2,%d1
        sub.l   %d0,%d1                   | frames carried (1 or 2)
        cmpi.l  #2,%d1
        bls.s   .re_carry_n
        moveq   #2,%d1
.re_carry_n:
        lea     mu_ext_carry(%pc),%a0
        move.l  %d1,(%a0,%d4.l*4)
        lsl.l   #3,%d0
        lea     (%a4,%d0.l),%a1           | &buf[k]
        move.l  %d4,%d0
        lsl.l   #4,%d0
        lea     mu_ext_hist(%pc),%a0
        adda.l  %d0,%a0
        move.l  (%a1)+,(%a0)+
        move.l  (%a1)+,(%a0)+
        move.l  (%a1)+,(%a0)+
        move.l  (%a1),(%a0)
.re_out:
        movem.l (%sp),%d2-%d7/%a2-%a4
        lea     36(%sp),%sp
        rts

| Detour at 0x40007978. d0 contains the track number. Selector zero rebuilds
| the exact stock pointer; 1..3 select that track's extension record.
voice_pointer:
        move.l  mu_voice_selector(%pc),%d1
        tst.l   %d1
        beq.s   .stock_pointer
        subq.l  #1,%d1
        move.l  %d1,%a2                   | selector - 1
        move.l  %d0,%d1
        lsl.l   #3,%d0
        sub.l   %d1,%d0                   | track * 7
        move.l  %a2,%d1
        add.l   %d1,%d0
        move.l  #VOICE_SIZE,%d1
        mulu.l  %d1,%d0
        lea     mu_extra_voices(%pc),%a2
        adda.l  %d0,%a2
        jmp     (CONTINUE_POINTER).l
.stock_pointer:
        move.l  #VOICE_SIZE,%d1            | displaced instruction
        mulu.l  %d1,%d0
        movea.l %d0,%a2
        adda.l  #VOICES,%a2
        jmp     (CONTINUE_POINTER).l

| Detour at 0x400334d8.  Stock's formatter table ends at PICKUP; return the
| runtime string for raw type 5 and replay stock's six displaced bytes for
| every existing value.
mu_machine_name:
        move.l  4(%sp),%d0
        cmpi.l  #POLY_TYPE,%d0
        beq.s   .pmn_poly
        cmpi.l  #1,%d0
        bne.s   .pmn_stock
        move.l  mu_ui_machine(%pc),%d0
        cmpi.l  #POLY_TYPE,%d0
        bne.s   .pmn_stock
.pmn_poly:
        lea     .mu_machine_name(%pc),%a0
        move.l  %a0,%d0
        rts
.pmn_stock:
        move.l  %d2,-(%sp)
        move.l  8(%sp),%d1
        jmp     (CONTINUE_NAME).l
.mu_machine_name:
        .asciz  "MULTI"
        .balign 2

| SRC SETUP normally points a5 at a stock five-entry table.  Repoint that LEA
| to this six-entry clone and widen the inline upper bound from 4 to 5.  This
| avoids running custom code inside the selector's fragile redraw loop.
        .balign 4
mu_src_names:
        .long   0x400b3eac
        .long   0x400b3e98
        .long   0x400b7c67
        .long   0x400b5413
        .long   0x400b7a63
        .long   .mu_machine_name

| Stock audio chromatic mode toggles only octave 0/1.  For POLY the same
| buttons walk 0..POLY_OCTAVE_MAX.  Not further: the chromatic LED routine
| writes two 8-entry stack arrays at 2*octave and 2*octave+1 (0x4004d47e),
| so octave 4 smashed its stack and hung the UI (measured under octemu,
| 22 Sep 2026, images <= 92 walked 0..10); and above octave 2 the keys pass
| the +24-semitone fetch cap and only repeat the top octave.  Other machine
| types retain the exact stock XOR toggle.
        .equ    POLY_OCTAVE_MAX, 2
mu_octave_button:
        move.l  %d0,-(%sp)
        mvz.b   (0x100b14cc).l,%d0
        bsr.w   mu_is_track
        tst.l   %d0
        beq.s   .pob_stock
        move.l  (0x460d16fc).l,%d0
        cmpi.l  #52,%d2                  | down button
        bne.s   .pob_up
        subq.l  #1,%d0
        bpl.s   .pob_store
        moveq   #POLY_OCTAVE_MAX,%d0
        bra.s   .pob_store
.pob_up:
        addq.l  #1,%d0
        cmpi.l  #POLY_OCTAVE_MAX,%d0
        bls.s   .pob_store
        moveq   #0,%d0
.pob_store:
        move.l  %d0,(0x460d16fc).l
        move.l  (%sp)+,%d0
        jmp     (CONTINUE_OCTAVE_BUTTON).l
.pob_stock:
        move.l  (%sp)+,%d0
        moveq   #1,%d2
        eor.l   %d2,(0x460d16fc).l
        jmp     (CONTINUE_OCTAVE_BUTTON).l

| The stock sample chooser uses the machine-selector value itself as its
| STATIC/FLEX discriminator.  Raw POLY (5) therefore falls through to the
| invalid-machine path and draws "Error".  Keep type 5 in the Part, but use
| FLEX (1) in this transient selector only while the sample pane is active.
| mu_ui_machine remembers which machine value LEFT must restore.
mu_sample_ui_init:
        .word   0x7190                    | displaced mvz.b (a0),d0
        clr.l   mu_ui_machine
        cmpi.l  #POLY_TYPE,%d0
        bne.s   .psui_pane
        move.l  %d0,mu_ui_machine
        moveq   #1,%d0
        move.l  %d0,(SAMPLE_UI_MACHINE).l
.psui_pane:
        moveq   #1,%d2
        cmp.l   %d0,%d2
        scs     %d0
        mvs.b   %d0,%d0
        addq.l  #1,%d0
        move.l  %d0,(SAMPLE_UI_PANE).l
        jmp     (CONTINUE_SAMPLE_UI_INIT).l

mu_sample_ui_left:
        move.l  %d0,-(%sp)
        move.l  mu_ui_machine(%pc),%d0
        beq.s   .psul_clear
        move.l  %d0,(SAMPLE_UI_MACHINE).l
        clr.l   mu_ui_machine
.psul_clear:
        move.l  (%sp)+,%d0
        clr.l   (SAMPLE_UI_PANE).l
        jmp     (CONTINUE_SAMPLE_UI_LEFT).l

mu_sample_ui_right:
        move.l  (SAMPLE_UI_MACHINE).l,%d0
        moveq   #1,%d3
        clr.l   mu_ui_machine
        cmpi.l  #POLY_TYPE,%d0
        bne.s   .psur_done
        move.l  %d0,mu_ui_machine
        move.l  %d3,%d0
        move.l  %d0,(SAMPLE_UI_MACHINE).l
.psur_done:
        jmp     (CONTINUE_SAMPLE_UI_RIGHT).l

| SRC SETUP (double-click SRC, FUNC+SRC) is a second copy of the machine/slot
| chooser, with its own state: the machine list object at 0x460d5c28 whose
| cursor is SRC_CURSOR, the pane flag at 0x460d1a48, and the STATIC/FLEX slot
| lists at 0x460d5c3c/0x460d5c50.  Every read of the cursor that picks the
| STATIC or FLEX behaviour tests 0 and 1 only, so on raw POLY (5) RIGHT did
| nothing, the redraw closed the slot pane (cursor > 2), the Part's slot byte
| was indexed at track*5+5 (the next track's STATIC slot), and the slot lookup
| 0x40031d18 returned NULL.  These reads see FLEX instead.  The cursor itself
| stays 5, so the two commit sites (0x4005a616 machine pane YES, 0x4005a850
| slot pane YES) still write POLY into the Part.  Each stub replaces one
| six-byte `move.l SRC_CURSOR,Dn` and ends with `tst.l Dn`, so the flags the
| stock code branches on are those of the value it now holds.
        .macro  SRC_CURSOR_AS_FLEX reg, cont
        move.l  (SRC_CURSOR).l,\reg
        cmpi.l  #POLY_TYPE,\reg
        bne.s   1f
        moveq   #1,\reg
1:      tst.l   \reg
        jmp     (\cont).l
        .endm

mu_src_cursor_scroll:                     | 0x4003a4b4: which slot list turns
        SRC_CURSOR_AS_FLEX %d2, 0x4003a4ba
mu_src_cursor_draw:                       | 0x4003c8c4: pane kept, list drawn
        SRC_CURSOR_AS_FLEX %d6, 0x4003c8ca
mu_src_cursor_record:                     | 0x4003d016: machine/slot load record
        SRC_CURSOR_AS_FLEX %d1, 0x4003d01c
mu_src_cursor_updown_old:                 | 0x4003d07c: slot list UP/DOWN moves
        SRC_CURSOR_AS_FLEX %d3, 0x4003d082
mu_src_cursor_updown_new:                 | 0x4003d0fa: Part slot byte index
        SRC_CURSOR_AS_FLEX %d1, 0x4003d100
mu_src_cursor_right:                      | 0x4003d1da: RIGHT opens the slot pane
        SRC_CURSOR_AS_FLEX %d1, 0x4003d1e0
mu_src_cursor_commit_list:                | 0x4005a67c: list shown after YES
        SRC_CURSOR_AS_FLEX %d0, 0x4005a682
mu_src_cursor_slot_yes:                   | 0x4005a766: slot pane YES
        SRC_CURSOR_AS_FLEX %d4, 0x4005a76c

| 0x4005a806 pushes the cursor as the machine argument of the slot lookup
| 0x40031d18, which answers only 0 (STATIC) and 1/4 (FLEX pool).
mu_src_cursor_slot_lookup:
        subq.l  #4,%sp
        move.l  %d0,-(%sp)
        move.l  (SRC_CURSOR).l,%d0
        cmpi.l  #POLY_TYPE,%d0
        bne.s   1f
        moveq   #1,%d0
1:      move.l  %d0,4(%sp)
        move.l  (%sp)+,%d0
        jmp     (0x4005a80c).l

| ---------------------------------------------------------------------------
| Keys.  A POLY track keeps the set of keys the player holds (panel keys and
| MIDI notes, up to HOLD_SLOTS), queues presses that arrive while stock's
| one-command mailbox is busy, and addresses each release to the voices the
| key owns.  Every change runs with interrupts masked, stock's own idiom
| (0x40006844): the frame ISR drains the queue and promotes the armed key,
| and the MIDI task (priority 6) can preempt the UI task (3) mid-update.
        .equ    HOLD_SLOTS, 8
        .equ    CMD_TRIGGER, 29           | stock's chromatic trigger, 0x1d
        .equ    CMD_RELEASE, 0x40
        .equ    NOTE_OUT, 0x4003f3a8      | AUDIO NOTE OUT: (track, note, velocity)
        .equ    NOTE_OUT_BASE, 72         | stock sends a key as MIDI note key + 72
        .equ    NOTE_CONFIG, 0x8000004c   | bit 0 INT (play the track), bit 1 EXT
        .equ    NOTE_OUT_HOLD, 0x46c7dd26 | stock sends no press note while set
        .equ    STOCK_HELD, 0x460d171d    | stock's held panel key per track, key + 1

| Detour at 0x4004fb94, the panel chromatic key handler (track, key, edge).
| Stock owns one held key per track and one pending command, so a second
| press released the first and two presses in one frame collapsed into one.
| POLY presses and releases each key on its own.  STATIC and FLEX replay the
| exact displaced prologue.
mu_chromatic_key:
        lea     -16(%sp),%sp
        movem.l %d2-%d4/%a2,(%sp)
        move.l  24(%sp),%d1              | chromatic key 0..135
        cmpi.l  #PANEL_KEYS-1,%d1
        bhi.w   .pck_stock
        move.l  20(%sp),%d0              | track
        bsr.w   mu_is_track
        tst.l   %d0
        beq.w   .pck_stock

        move.l  28(%sp),%d0              | edge: 1 press, 0 release
        beq.s   .pck_release
        cmpi.l  #1,%d0
        bne.w   .pck_stock
        pea     1.w                      | MULTI: the multisample map, here in the UI task
        move.l  24(%sp),-(%sp)           | track
        jsr     mu_prep
        addq.l  #8,%sp
        moveq   #127,%d2
        mvs.b   (NOTE_CONFIG).l,%d0
        btst    #0,%d0
        beq.s   .pck_note_out            | INT off: stock plays nothing, sends only
        move.l  20(%sp),%d0
        move.l  24(%sp),%d1
        bsr.w   mu_press_key
        tst.l   (NOTE_OUT_HOLD).l
        bne.s   .pck_done
        bra.s   .pck_note_out
.pck_release:
        move.l  20(%sp),%d0
        move.l  24(%sp),%d1
        bsr.w   mu_release_key
        moveq   #0,%d2
.pck_note_out:
        move.l  %d2,-(%sp)               | velocity
        move.l  28(%sp),%d0              | key
        addi.l  #NOTE_OUT_BASE,%d0
        move.l  %d0,-(%sp)
        move.l  28(%sp),-(%sp)           | track
        jsr     (NOTE_OUT).l
        lea     12(%sp),%sp
.pck_done:
        moveq   #0,%d0
        movem.l (%sp),%d2-%d4/%a2
        lea     16(%sp),%sp
        rts
.pck_stock:
        movem.l (%sp),%d2-%d4/%a2
        lea     16(%sp),%sp
        lea     -16(%sp),%sp              | replay displaced prologue
        movem.l %d2-%d4/%a2,(%sp)
        jmp     (CONTINUE_CHROMATIC_KEY).l

| Detour at 0x4000e746, MIDI chromatic note-on (notes 72..96), once per
| listening track d2; a3 = the message's note.  Stock writes its trigger and
| PTCH lock straight into the one-command mailbox, so the notes of a chord
| that reach the MIDI task within one frame collapsed into one, and its
| note-off matched only the last note.  POLY presses the note like a panel
| key (owner MIDI_KEY + note) and rejoins stock for the held-note byte, the
| gate bit and the recorder event.
mu_midi_note_on:
        move.l  %d2,%d0
        bsr.w   mu_is_track            | d1/a0 scratch
        tst.l   %d0
        beq.s   .pmon_stock
        lea     -8(%sp),%sp              | MULTI: the multisample map, in the MIDI task
        movem.l %a0-%a1,(%sp)
        clr.l   -(%sp)
        move.l  %d2,-(%sp)
        jsr     mu_prep
        addq.l  #8,%sp
        movem.l (%sp),%a0-%a1
        lea     8(%sp),%sp
        mvz.b   (%a3),%d1
        addi.l  #MIDI_KEY,%d1
        move.l  %d2,%d0
        bsr.w   mu_press_key
        jmp     (MIDI_ON_HELD).l
.pmon_stock:
        moveq   #CMD_TRIGGER,%d1          | displaced
        move.l  %d1,(%a5,%d2.l*4)
        mvs.b   (%a3),%d0
        jmp     (CONTINUE_MIDI_ON).l

| Detour at 0x4000dfd4, MIDI chromatic note-off, once per listening track d2;
| a0 = the track's held-note byte (0x400d64c2 + t), a3 = the note, d3 =
| 1 << track.  Stock releases the track only when the note is its one held
| note.  POLY stops the voices this note owns; the gate bit clears (and
| stock's release posts) only when the track holds no key.
mu_midi_note_off:
        move.l  %a0,-(%sp)
        move.l  %d2,%d0
        bsr.w   mu_is_track            | d1/a0 scratch
        movea.l (%sp)+,%a0
        tst.l   %d0
        beq.s   .pmof_stock
        mvz.b   (%a3),%d1
        cmp.b   (%a0),%d1
        bne.s   .pmof_release
        moveq   #-1,%d0
        move.b  %d0,(%a0)                | stock's held-note byte, as stock
.pmof_release:
        addi.l  #MIDI_KEY,%d1
        move.l  %d2,%d0
        move.l  %a0,-(%sp)
        bsr.w   mu_release_key
        movea.l (%sp)+,%a0
        tst.l   %d0
        beq.s   .pmof_next
        move.l  %d3,%d0
        not.l   %d0
        move.b  (MIDI_GATES).l,%d1
        and.l   %d1,%d0
        move.b  %d0,(MIDI_GATES).l
.pmof_next:
        jmp     (MIDI_OFF_NEXT).l
.pmof_stock:
        mvs.b   (%a0),%d1                | displaced compare
        mvs.b   (%a3),%d0
        cmp.l   %d1,%d0
        bne.s   .pmof_next
        jmp     (MIDI_OFF_MATCH).l

| Detour at 0x400437b6: stock's "drop the live-held key" of a chromatic track
| (0x40043728, called by the UI on track and mode changes) looks only at its
| one held-key byte, which POLY never sets, so keys held across a track
| change left their voices ringing.  Release every PANEL key held on a POLY
| track instead; MIDI notes stay held, as stock leaves them.  d3 = track;
| d2/a2/a3 are the function's own and restored by its exit.
mu_release_held:
        move.l  %d3,%d0
        bsr.w   mu_is_track
        tst.l   %d0
        beq.s   .prh_stock
        moveq   #0,%d2
.prh_slot:
        move.l  %d3,%d0
        lsl.l   #3,%d0
        lea     mu_held(%pc),%a2
        adda.l  %d0,%a2
        mvz.b   (%a2,%d2.l),%d1
        cmpi.l  #PANEL_KEYS,%d1
        bcc.s   .prh_next                | empty, or a MIDI note
        move.l  %d1,%a3
        move.l  %d3,%d0
        bsr.w   mu_release_key
        clr.l   -(%sp)                   | note off, as stock's release does
        move.l  %a3,%d0
        addi.l  #NOTE_OUT_BASE,%d0
        move.l  %d0,-(%sp)
        move.l  %d3,-(%sp)
        jsr     (NOTE_OUT).l
        lea     12(%sp),%sp
.prh_next:
        addq.l  #1,%d2
        cmpi.l  #HOLD_SLOTS,%d2
        bcs.s   .prh_slot
        jmp     (0x400438d2).l           | the function's exit
.prh_stock:
        lea     (STOCK_HELD).l,%a0       | displaced
        jmp     (0x400437bc).l

| d0 = track, d1 = owner key.  Adds the key to the held set and presses it:
| straight into stock's mailbox when that is empty, else queued behind it (up
| to three, one per frame after it).  Clobbers d0/d1.
mu_press_key:
        lea     -24(%sp),%sp
        movem.l %d2-%d5/%a0-%a1,(%sp)
        move.w  %sr,%d5
        move.w  #0x2700,%sr
        move.l  %d0,%d4
        move.l  %d1,%d3
        bsr.w   .hold_add
        lea     mu_relpend(%pc),%a0      | a key again: no release owed (222)
        clr.b   (%a0,%d4.l)
        lea     (PENDING_COMMANDS).l,%a0
| A release alone still in the mailbox (the last key let go this very moment) and a key pressed now:
| legato, the release is withdrawn and the key armed. Taken first, it ended the new key before it
| sounded: CHORDS' last-pressed keys let one chord go and press the next together (OctaZach 218).
        moveq   #CMD_RELEASE,%d0
        cmp.l   (%a0,%d4.l*4),%d0
        bne.s   1f
        clr.l   (%a0,%d4.l*4)
1:      tst.l   (%a0,%d4.l*4)
        beq.s   .ppk_arm
        lea     mu_chord_count(%pc),%a0
        mvz.b   (%a0,%d4.l),%d2
        cmpi.l  #EXTRA_PER_TRACK,%d2
        bcc.s   .ppk_done                | queue full: the press is dropped
        move.l  %d4,%d0
        lsl.l   #3,%d0
        sub.l   %d4,%d0                  | track * 7
        add.l   %d2,%d0
        lea     mu_chord_notes(%pc),%a1
        move.b  %d3,(%a1,%d0.l)
        addq.l  #1,%d2
        move.b  %d2,(%a0,%d4.l)
        bra.s   .ppk_done
.ppk_arm:
        bsr.w   .arm_key
.ppk_done:
        move.w  %d5,%sr
        movem.l (%sp),%d2-%d5/%a0-%a1
        lea     24(%sp),%sp
        rts

| d0 = track, d1 = owner key.  Releases the key: a press still queued never
| plays, a press armed but not yet taken is withdrawn, every voice the key
| owns stops, and the key leaves the held set.  When that was the track's
| last held key, posts stock's release (bit 6): it ends the live-played state
| that keeps the sequencer off the track (0x4000b52a) and releases the AMP
| envelope -- without it a POLY track never played the sequencer again after
| a chromatic note (octemu, 22 Sep 2026).  Returns d0 = 1 in that case.
mu_release_key:
        lea     -32(%sp),%sp
        movem.l %d2-%d6/%a0-%a2,(%sp)
        move.w  %sr,%d5
        move.w  #0x2700,%sr
        move.l  %d0,%d4
        move.l  %d1,%d3

        lea     mu_chord_count(%pc),%a2
        mvz.b   (%a2,%d4.l),%d2
        move.l  %d4,%d0
        lsl.l   #3,%d0
        sub.l   %d4,%d0                  | track * 7
        lea     mu_chord_notes(%pc),%a1
        adda.l  %d0,%a1                  | this track's queue
        moveq   #0,%d0                   | read
        moveq   #0,%d1                   | write
.prk_queue:
        cmp.l   %d2,%d0
        bcc.s   .prk_queued
        move.b  (%a1,%d0.l),%d6
        cmp.b   %d6,%d3
        beq.s   .prk_queue_next          | dropped
        move.b  %d6,(%a1,%d1.l)
        addq.l  #1,%d1
.prk_queue_next:
        addq.l  #1,%d0
        bra.s   .prk_queue
.prk_queued:
        move.b  %d1,(%a2,%d4.l)

| Armed and still in the mailbox: withdraw it, as stock's note-off does by
| overwriting the command (0x4000dfde).  The next queued press then takes
| the mailbox here, since no consumer will run to re-arm it.
        lea     mu_armed_key(%pc),%a0
        cmp.b   (%a0,%d4.l),%d3
        bne.s   .prk_voices
        lea     (PENDING_COMMANDS).l,%a1
        moveq   #CMD_TRIGGER,%d0
        cmp.l   (%a1,%d4.l*4),%d0
        bne.s   .prk_voices              | mixed with a release: it plays
        clr.l   (%a1,%d4.l*4)
        moveq   #-1,%d1
        move.b  %d1,(%a0,%d4.l)
        lea     mu_armed_shift(%pc),%a0
        clr.b   (%a0,%d4.l)
        move.l  %d4,%d0
        lsl.l   #5,%d0
        lea     (LIVE_LOCKS).l,%a0
        move.b  %d1,(%a0,%d0.l)          | no PTCH lock, as the consumer leaves it
        move.b  %d1,31(%a0,%d0.l)        | nor a slot lock
        tst.b   (%a2,%d4.l)
        beq.s   .prk_voices
        move.l  %d3,%d6
        bsr.w   .queue_pop
        bsr.w   .arm_key
        move.l  %d6,%d3

.prk_voices:
        move.l  %d4,%d0
        move.l  %d3,%d1
        bsr.w   mu_release_note
        bsr.w   .hold_find
        tst.l   %d0
        bmi.s   .prk_busy                | was not held
        moveq   #-1,%d1
        move.b  %d1,(%a0,%d0.l)
        moveq   #0,%d0
.prk_any:
        cmp.b   (%a0,%d0.l),%d1
        bne.s   .prk_busy
        addq.l  #1,%d0
        cmpi.l  #HOLD_SLOTS,%d0
        bcs.s   .prk_any
| MULTI ADSR (222): the release waits until every voice of the track has ended (mu_call posts it),
| so the AMP release of the last notes is heard.
        lea     mu_relpend(%pc),%a0
        moveq   #1,%d0
        move.b  %d0,(%a0,%d4.l)
        bra.s   .prk_out
.prk_busy:
        moveq   #0,%d0
.prk_out:
        move.w  %d5,%sr
        movem.l (%sp),%d2-%d6/%a0-%a2
        lea     32(%sp),%sp
        rts

| Track d4, owner d3: adds the key to the track's held set (a full set still
| plays the key, it is only not shown).  Clobbers d0/d1/a0.
.hold_add:
        bsr.s   .hold_find
        tst.l   %d0
        bpl.s   .ha_done                 | already held
        moveq   #-1,%d1
        moveq   #0,%d0
.ha_free:
        cmp.b   (%a0,%d0.l),%d1
        beq.s   .ha_store
        addq.l  #1,%d0
        cmpi.l  #HOLD_SLOTS,%d0
        bcs.s   .ha_free
        rts
.ha_store:
        move.b  %d3,(%a0,%d0.l)
.ha_done:
        rts

| a0 = track d4's held set; d0 = the slot holding owner d3, or -1.
.hold_find:
        move.l  %d4,%d0
        lsl.l   #3,%d0
        lea     mu_held(%pc),%a0
        adda.l  %d0,%a0
        moveq   #0,%d0
.hf_loop:
        cmp.b   (%a0,%d0.l),%d3
        beq.s   .hf_done
        addq.l  #1,%d0
        cmpi.l  #HOLD_SLOTS,%d0
        bcs.s   .hf_loop
        moveq   #-1,%d0
.hf_done:
        rts

| Track d4 (queue non-empty): pops the oldest queued owner into d3.
| Clobbers d0-d2/a0-a1.
.queue_pop:
        lea     mu_chord_count(%pc),%a0
        mvz.b   (%a0,%d4.l),%d2
        move.l  %d4,%d0
        lsl.l   #3,%d0
        sub.l   %d4,%d0                  | track * 7
        lea     mu_chord_notes(%pc),%a1
        adda.l  %d0,%a1
        mvz.b   (%a1),%d3
        moveq   #EXTRA_PER_TRACK-2,%d0
1:      move.b  1(%a1),%d1
        move.b  %d1,(%a1)+
        subq.l  #1,%d0
        bpl.s   1b
        subq.l  #1,%d2
        move.b  %d2,(%a0,%d4.l)
        rts

| Track d4, owner d3: arms the key and its octave shift first, then the PTCH
| lock, then stock's trigger command.  The consumer promotes the armed pair
| when it takes the command, so the command is the last write (a frame
| between them would otherwise take a command whose owner is not written
| yet).  Clobbers d0-d2/a0.
.arm_key:
        move.l  %d3,-(%sp)
        move.l  %d3,%d1
        bsr.w   .pck_encode              | d3 = pitch byte, d2 = octave shift
| MULTI: a track whose sample is named with a note plays the multisample: mu_ms
| (mu.c) answers the nearest note's slot and its PTCH byte, no octave shift.
        lea     -16(%sp),%sp
        movem.l %d1-%d3/%a1,(%sp)
        move.l  %d1,-(%sp)               | owner
        move.l  %d4,-(%sp)               | track
        jsr     mu_ms
        addq.l  #8,%sp
        movem.l (%sp),%d1-%d3/%a1
        lea     16(%sp),%sp
        btst    #16,%d0
        beq.s   .ak_plain
        move.l  %d0,%d3
        andi.l  #0xff,%d3
        moveq   #0,%d2
        lsr.l   #8,%d0
        bra.s   .ak_slot
.ak_plain:
        moveq   #-1,%d0
.ak_slot:
        move.b  %d0,mu_armslot
        lea     mu_armed_key(%pc),%a0
        move.b  %d1,(%a0,%d4.l)
        lea     mu_armed_shift(%pc),%a0
        move.b  %d2,(%a0,%d4.l)
        move.l  %d4,%d0
        lsl.l   #5,%d0
        lea     (LIVE_LOCKS).l,%a0
        move.b  %d3,(%a0,%d0.l)
        move.b  mu_armslot,%d1
        cmpi.b  #-1,%d1
        beq.s   .ak_noslot
        move.b  %d1,31(%a0,%d0.l)        | the multisample's slot lock
.ak_noslot:
        lea     rt_locks,%a0             | MIDI ROUTING's audio-step locks for the note (OctaZach 214;
        cmpa.l  #0,%a0                   | weak: MULTI builds without it)
        beq.s   .ak_nolocks
        lea     -8(%sp),%sp
        movem.l %d4/%a1,(%sp)
        move.l  %d4,-(%sp)
        jsr     (%a0)
        addq.l  #4,%sp
        movem.l (%sp),%d4/%a1
        lea     8(%sp),%sp
.ak_nolocks:
        lea     (PENDING_COMMANDS).l,%a0
        moveq   #CMD_TRIGGER,%d0
        move.l  %d0,(%a0,%d4.l*4)
        move.l  (%sp)+,%d3
        rts

| Owner d1 -> d3 = stock's PTCH lock byte, d2 = octave shift; d0 clobbered.
| A panel key k plays pitch k mod 12 of octave k/12 - 1 (the shift reaches
| the increment in mu_increment_shift); a MIDI note n takes stock's own
| MIDI lock, 5n - 100, and no shift.
.pck_encode:
        cmpi.l  #PANEL_KEYS,%d1
        bcs.s   .pcke_panel
        move.l  %d1,%d3
        subi.l  #MIDI_KEY,%d3
        move.l  %d3,%d0
        lsl.l   #2,%d3
        add.l   %d0,%d3
        subi.l  #100,%d3
        moveq   #0,%d2
        rts
.pcke_panel:
        move.l  %d1,%d0
        moveq   #-1,%d2
.pcke_octave:
        cmpi.l  #12,%d0
        bcs.s   .pcke_pitch
        subi.l  #12,%d0
        addq.l  #1,%d2
        bra.s   .pcke_octave
.pcke_pitch:
        addi.l  #12,%d0
        move.l  %d0,%d3
        lsl.l   #2,%d3
        add.l   %d0,%d3
        addq.l  #4,%d3
        rts

| Detour at 0x400449f0 in the keyboard draw (0x40044920).  Its audio branch
| boxes each track's held key from the eight bytes at STOCK_HELD (key + 1,
| 0 = none), which POLY never sets: a POLY chord drew no box at all (octemu,
| 25 Sep 2026).  The loop walks mu_kbd instead, HOLD_SLOTS entries per
| track: stock's byte for any other machine, every held key for POLY (a MIDI
| note n as key n - 72, the key stock's own note-out gives it).
mu_kbd_fill:
        lea     -24(%sp),%sp
        movem.l %d0-%d3/%a0-%a1,(%sp)
        lea     mu_kbd(%pc),%a1
        moveq   #0,%d2
.pkf_track:
        move.l  %d2,%d0
        bsr.w   mu_is_track            | d1/a0 scratch
        tst.l   %d0
        bne.s   .pkf_poly
        lea     (STOCK_HELD).l,%a0
        move.b  (%a0,%d2.l),(%a1)+
        moveq   #HOLD_SLOTS-2,%d0
.pkf_zero:
        clr.b   (%a1)+
        subq.l  #1,%d0
        bpl.s   .pkf_zero
        bra.s   .pkf_next
.pkf_poly:
        move.l  %d2,%d0
        lsl.l   #3,%d0
        lea     mu_held(%pc),%a0
        adda.l  %d0,%a0
        moveq   #HOLD_SLOTS-1,%d3
.pkf_key:
        mvz.b   (%a0)+,%d0
        cmpi.l  #PANEL_KEYS,%d0
        bcs.s   .pkf_value
        cmpi.l  #0xff,%d0
        beq.s   .pkf_none
        subi.l  #MIDI_KEY+NOTE_OUT_BASE,%d0
.pkf_value:
        addq.l  #1,%d0
        bra.s   .pkf_store
.pkf_none:
        moveq   #0,%d0
.pkf_store:
        move.b  %d0,(%a1)+
        subq.l  #1,%d3
        bpl.s   .pkf_key
.pkf_next:
        addq.l  #1,%d2
        moveq   #8,%d0
        cmp.l   %d0,%d2
        bcs.s   .pkf_track
        movem.l (%sp),%d0-%d3/%a0-%a1
        lea     24(%sp),%sp
        lea     mu_kbd(%pc),%a2
        jmp     (0x400449f6).l

| Detour at 0x40044b5c: the draw loop's step and end test, over mu_kbd.
mu_kbd_next:
        addq.l  #1,%a2
        cmpa.l  #mu_kbd_end,%a2
        bne.s   1f
        jmp     (0x40044b68).l
1:      jmp     (0x40044abc).l
| d0=track, d1=owner key. Stop every matching primary or extension record.
| This replaces the stock single-held-note release only for POLY; the same
| key may legitimately own more than one stolen slot.
mu_release_note:
        lea     -20(%sp),%sp
        movem.l %d2-%d3/%a0-%a2,(%sp)
        move.l  %d0,%d2
        move.l  %d1,%d3

| MULTI ADSR (222): a voice let go releases (mu_env_release); mu_call ends it when its envelope does.
| The voice gives up its key here, so a new press of that key takes a new voice.
        lea     mu_primary_note(%pc),%a0
        cmp.b   (%a0,%d2.l),%d3
        bne.s   .prn_extra
        st      %d0
        move.b  %d0,(%a0,%d2.l)          | the voice no longer owns the key
        clr.l   -(%sp)
        move.l  %d2,-(%sp)
        jsr     mu_env_release
        addq.l  #8,%sp
.prn_extra:
        move.l  %d2,%d0
        lsl.l   #3,%d0
        sub.l   %d2,%d0                  | first flat extension index
        movea.l %d0,%a2
        moveq   #0,%d0
.prn_loop:
        lea     mu_extra_note(%pc),%a0
        move.l  %a2,%d1
        add.l   %d0,%d1
        cmp.b   (%a0,%d1.l),%d3
        bne.s   .prn_next
        movea.l %d3,%a1
        moveq   #-1,%d3
        move.b  %d3,(%a0,%d1.l)          | the voice no longer owns the key
        move.l  %a1,%d3
        move.l  %d0,-(%sp)
        addq.l  #1,%d0
        move.l  %d0,-(%sp)
        move.l  %d2,-(%sp)
        jsr     mu_env_release
        addq.l  #8,%sp
        move.l  (%sp)+,%d0
.prn_next:
        addq.l  #1,%d0
        cmpi.l  #EXTRA_PER_TRACK,%d0
        bcs.s   .prn_loop
        movem.l (%sp),%d2-%d3/%a0-%a2
        lea     20(%sp),%sp
        rts

| Called where the frame consumer has finished copying and clearing the live
| lock block.  Re-arm one queued key for the following frame, then replay
| the displaced clear/LEA sequence.  Spreading a chord over adjacent 16-sample
| frames prevents the stock one-command mailbox from collapsing its presses.
| A press (or the re-arm below) leaves its key and octave shift ARMED; the
| consumer taking that track's command promotes them to the pending pair
| the trigger consumes.  One stage was not enough: this hook runs between
| the consumer copying a command and the trigger it causes (measured order:
| here -> initializer -> recompute -> render), so re-arming the next queued
| key overwrote the key of the note about to start -- it played the right
| pitch under the wrong key and octave, and the chord's last voice owned no
| key and never released (octemu, 22 Sep 2026).  d4 = track (stock's).
mu_chord_dequeue:
        lea     -24(%sp),%sp
        movem.l %d0-%d3/%a0-%a1,(%sp)
        move.l  (%a0,%d4.l*4),%d3         | the command being consumed
        clr.l   (%a0,%d4.l*4)             | displaced pending-command clear
        move.l  %d4,%d0
        bsr.w   mu_is_track
        tst.l   %d0
        beq.w   .pcd_done
        tst.l   %d3
        beq.s   .pcd_promoted
        lea     mu_armed_key(%pc),%a0
        move.b  (%a0,%d4.l),%d0
        moveq   #-1,%d1
        move.b  %d1,(%a0,%d4.l)
        lea     mu_pending_key(%pc),%a0
        move.b  %d0,(%a0,%d4.l)
        lea     mu_armed_shift(%pc),%a0
        move.b  (%a0,%d4.l),%d0
        clr.b   (%a0,%d4.l)
        lea     mu_pending_shift(%pc),%a0
        move.b  %d0,(%a0,%d4.l)
.pcd_promoted:
        lea     mu_chord_count(%pc),%a0
        tst.b   (%a0,%d4.l)
        beq.s   .pcd_done
        bsr.w   .queue_pop                | d3 = the oldest queued key
        bsr.w   .arm_key
.pcd_done:
        movem.l (%sp),%d0-%d3/%a0-%a1
        lea     24(%sp),%sp
        lea     0x46c802a6.l,%a0          | displaced instruction
        jmp     (CONTINUE_CHORD_DEQUEUE).l
| Explicit initialization is intentional: this runtime is copied from the
| loader image and is not a zeroed BSS.
        .balign 4
mu_voice_selector:
        .long   0
mu_ui_machine:
        .long   0
mu_chord_count:
        .zero   8
mu_chord_notes:
        .zero   56
mu_pending_key:
        .fill   8,1,0xff                    | 0xff = no pending chromatic key
mu_pending_shift:
        .zero   8
mu_armed_key:
        .fill   8,1,0xff                    | set by a press, promoted by the consumer
mu_armed_shift:
        .zero   8
mu_primary_note:
        .fill   8,1,0xff
mu_extra_note:
        .fill   56,1,0xff
mu_primary_shift:
        .zero   8
mu_extra_shift:
        .zero   56
mu_next:
        .zero   8
mu_held:
        .fill   8*HOLD_SLOTS,1,0xff         | keys held per track, 0xff = none
mu_kbd:
        .zero   8*HOLD_SLOTS                | the keyboard draw's boxes, key + 1
mu_kbd_end:
mu_relpend:
        .zero   8                           | a release owed once the track's voices end (222)
        .balign 4
mu_extra_increment:
        .zero   224                         | 56 saved Q26 increments
mu_ext_phase:
        .zero   224                         | 56 resampler phases, Q16 in [0,1)
mu_ext_carry:
        .zero   224                         | 56 carried-frame counts (0..2)
mu_ext_hist:
        .zero   896                         | 56 * two carried stereo frames
mu_fetch:
        .zero   (FETCH_FRAMES+2)*8          | one extension's raw source frames
mu_extra_voices:
        .zero   9408                        | 8 tracks * 7 * 168 bytes
mu_scratch:
        .zero   512                         | 64 frames * 2 * 4 bytes
        .global mu_fast, mu_slow
mu_fast:
        .long   0
mu_armslot:
        .byte   0xff
        .balign 4
mu_prim_inc:
        .long   0,0,0,0,0,0,0,0
mu_prim_ok:
        .byte   0,0,0,0,0,0,0,0
mu_slow:
        .long   0
| objcopy omits trailing all-zero bytes. Keep all state inside the image.
mu_runtime_end_marker:
        .long   0x504f4c59                  | "POLY"

| MULTI (214): stock's lock restore at a trig (0x4000c458) and the step handler's PLAYBACK lock
| defaults (0x4009d7fe, 0x4009d862) read the Part's PLAYBACK values at machine * 6: type 5 read the
| next track's. MULTI is FLEX there.
        .global mu_restore_type, mu_step_type_a, mu_step_type_b
mu_restore_type:
        .word   0x7330,0x1800             | displaced mvs.b (a0,d1.l),d1
        cmpi.l  #POLY_TYPE,%d1
        bne.s   1f
        moveq   #1,%d1
1:      movea.l %d1,%a5                   | displaced
        jmp     (0x4000c45e).l
mu_step_type_a:
        .word   0x7510                    | displaced mvs.b (a0),d2
        cmpi.l  #POLY_TYPE,%d2
        bne.s   1f
        moveq   #1,%d2
1:      move.l  %d7,%d1                   | displaced
        add.l   %d1,%d1                   | displaced
        jmp     (0x4009d804).l
mu_step_type_b:
        .word   0x7510
        cmpi.l  #POLY_TYPE,%d2
        bne.s   1f
        moveq   #1,%d2
1:      move.l  %d7,%d1
        add.l   %d1,%d1
        jmp     (0x4009d868).l

| ---- mu.c, m68k-linux-gnu-gcc -mcpu=54455 -O2 -fomit-frame-pointer (labels prefixed, sections joined)
#NO_APP
	.align	2
mu_name:
	lea (-40,%sp),%sp
	movem.l #15612,(%sp)
	move.l 44(%sp),%d2
	move.l #1096,%d0
	muls.l %d0,%d2
	move.l %d2,%a0
	add.l #269161712,%a0
	add.l #269161967,%d2
	move.l %a0,%a1
.Lmu_2:
	move.b (%a0),%d0
	move.l %a0,%d1
	addq.l #1,%d1
	tst.b %d0
	jeq .Lmu_6
	move.b (%a0),%d0
	moveq #47,%d3
	mvs.b %d0,%d0
	cmp.l %d0,%d3
	jeq .Lmu_47
	move.l %d1,%a0
	cmp.l %d1,%d2
	jne .Lmu_2
.Lmu_6:
	clr.l %d1
.Lmu_4:
	lea (%a1,%d1.l),%a0
	move.b (%a0),%d0
	jeq .Lmu_8
	move.b (%a0),%d0
	moveq #46,%d2
	mvs.b %d0,%d0
	cmp.l %d0,%d2
	jeq .Lmu_8
	addq.l #1,%d1
	moveq #64,%d7
	cmp.l %d1,%d7
	jne .Lmu_4
.Lmu_7:
	move.w #-1,%a5
	move.l %a1,%d6
	moveq #2,%d5
	moveq #1,%d3
	sub.l %a0,%a0
	subq.l #1,%d6
	lea (mu_pc0),%a3
.Lmu_24:
	lea (%a1,%a0.l),%a2
	moveq #6,%d7
	move.b (%a2),%d4
	move.l %d4,%d2
	add.l #-65,%d2
	mvz.b %d2,%d2
	cmp.l %d2,%d7
	jcs .Lmu_48
	tst.l %a0
	jeq .Lmu_49
	lea (%a0,%d6.l),%a2
	moveq #64,%d0
	move.b (%a2),%d7
	move.l %d3,%d2
	mvs.b %d7,%d7
	cmp.l %d7,%d0
	jge .Lmu_15
	move.b (%a2),%d7
	moveq #90,%d0
	mvs.b %d7,%d7
	cmp.l %d7,%d0
	jge .Lmu_11
.Lmu_15:
	move.b (%a2),%d7
	moveq #96,%d0
	mvs.b %d7,%d7
	cmp.l %d7,%d0
	jge .Lmu_16
	move.b (%a2),%d7
	moveq #122,%d0
	mvs.b %d7,%d7
	cmp.l %d7,%d0
	jge .Lmu_11
.Lmu_16:
	cmp.l %d1,%d3
	jge .Lmu_13
	mvs.b %d4,%d4
	move.l %d3,%a2
	move.l %d3,%a4
	mvs.b -65(%a3,%d4.l),%d7
.Lmu_14:
	add.l %a1,%a2
	move.b (%a2),%d4
	moveq #35,%d0
	mvs.b %d4,%d4
	cmp.l %d4,%d0
	jeq .Lmu_17
	move.b (%a2),%d4
	moveq #115,%d0
	mvs.b %d4,%d4
	cmp.l %d4,%d0
	jeq .Lmu_17
	move.b (%a2),%d4
	moveq #83,%d0
	mvs.b %d4,%d4
	cmp.l %d4,%d0
	jeq .Lmu_17
	move.b (%a2),%d4
	moveq #98,%d0
	mvs.b %d4,%d4
	cmp.l %d4,%d0
	jeq .Lmu_50
	move.b (%a2),%d4
	moveq #45,%d0
	mvs.b %d4,%d4
	cmp.l %d4,%d0
	jeq .Lmu_51
.Lmu_25:
	sub.l %a4,%a4
.Lmu_21:
	move.b (%a2),%d4
	moveq #47,%d0
	mvs.b %d4,%d4
	cmp.l %d4,%d0
	jge .Lmu_11
	move.b (%a2),%d4
	moveq #57,%d0
	mvs.b %d4,%d4
	cmp.l %d4,%d0
	jlt .Lmu_11
	move.b (%a2),%d4
	mvs.b %d4,%d4
	move.l %d4,%a2
	tst.l %a4
	jne .Lmu_22
	add.l #-48,%d4
.Lmu_23:
	addq.l #1,%d4
	moveq #12,%d0
	muls.l %d0,%d4
	add.l %d7,%d4
	cmp.l #128,%d4
	jcc .Lmu_11
	move.l 52(%sp),%a2
	move.l %d4,%a5
	move.l %a0,(%a2)
.Lmu_11:
	addq.l #1,%a0
	addq.l #1,%d3
	addq.l #1,%d5
	cmp.l %d1,%d2
	jlt .Lmu_24
.Lmu_13:
	move.l %a5,%d0
	movem.l (%sp),#15612
	move.l 48(%sp),%a0
	move.l %a1,(%a0)
	lea (40,%sp),%sp
	rts
.Lmu_47:
	lea (1,%a0),%a1
	move.l %a1,%d1
	move.l %d1,%a0
	cmp.l %d1,%d2
	jne .Lmu_2
	jra .Lmu_6
.Lmu_50:
	subq.l #1,%d7
	move.l %d5,%a4
.Lmu_19:
	cmp.l %d5,%d1
	jle .Lmu_11
	lea (%a1,%d5.l),%a2
	moveq #45,%d0
	move.b (%a2),%d4
	mvs.b %d4,%d4
	cmp.l %d4,%d0
	jne .Lmu_25
.Lmu_51:
	addq.l #1,%a4
	cmp.l %a4,%d1
	jle .Lmu_11
	lea (%a1,%a4.l),%a2
	move.w #1,%a4
	jra .Lmu_21
.Lmu_48:
	move.l %d3,%d2
	addq.l #1,%a0
	addq.l #1,%d3
	addq.l #1,%d5
	cmp.l %d1,%d2
	jlt .Lmu_24
	jra .Lmu_13
.Lmu_17:
	addq.l #1,%d7
	move.l %d5,%a4
	jra .Lmu_19
.Lmu_49:
	moveq #1,%d0
	cmp.l %d1,%d0
	jeq .Lmu_13
	mvs.b %d4,%d4
	move.w #1,%a2
	move.w #1,%a4
	move.l %d3,%d2
	mvs.b -65(%a3,%d4.l),%d7
	jra .Lmu_14
.Lmu_8:
	tst.l %d1
	jne .Lmu_7
	move.w #-1,%a5
	move.l 48(%sp),%a0
	move.l %a5,%d0
	movem.l (%sp),#15612
	move.l %a1,(%a0)
	lea (40,%sp),%sp
	rts
.Lmu_22:
	moveq #48,%d4
	sub.l %a2,%d4
	jra .Lmu_23
	.align	2
mu_same:
	link.w %fp,#-16
	move.l %a2,-(%sp)
	move.l %d2,-(%sp)
	pea -8(%fp)
	pea -16(%fp)
	lea mu_name,%a2
	move.l 8(%fp),-(%sp)
	jsr (%a2)
	lea (12,%sp),%sp
	tst.l %d0
	jlt .Lmu_53
	pea -4(%fp)
	pea -12(%fp)
	move.l 12(%fp),-(%sp)
	jsr (%a2)
	lea (12,%sp),%sp
	tst.l %d0
	jlt .Lmu_53
	move.l -8(%fp),%d2
	cmp.l -4(%fp),%d2
	jne .Lmu_53
	tst.l %d2
	jle .Lmu_56
	move.l -12(%fp),%a1
	move.l -16(%fp),%a0
	add.l %a0,%d2
.Lmu_55:
	move.b (%a0),%d1
	move.b (%a1),%d0
	addq.l #1,%a0
	addq.l #1,%a1
	mvs.b %d1,%d1
	mvs.b %d0,%d0
	cmp.l %d1,%d0
	jne .Lmu_53
	cmp.l %a0,%d2
	jne .Lmu_55
.Lmu_56:
	move.l -24(%fp),%d2
	moveq #1,%d0
	move.l -20(%fp),%a2
	unlk %fp
	rts
.Lmu_53:
	move.l -24(%fp),%d2
	clr.l %d0
	move.l -20(%fp),%a2
	unlk %fp
	rts
	.align	2
dec:
	lea (-12,%sp),%sp
	move.l 20(%sp),%d0
	movem.l #28,(%sp)
	move.l 16(%sp),%a0
	tst.l %d0
	jlt .Lmu_68
	moveq #99,%d1
	cmp.l %d0,%d1
	jge .Lmu_62
.Lmu_69:
	move.l %d0,%d1
	moveq #100,%d3
	divs.l %d3,%d1
	add.l #48,%d1
	move.b %d1,(%a0)+
.Lmu_63:
	moveq #10,%d3
	move.l %d0,%d1
	divs.l %d3,%d1
	move.l %d1,%d2
	rems.l %d3,%d4:%d2
	moveq #10,%d2
	move.l %d4,%d1
	add.l #48,%d1
	move.b %d1,(%a0)+
	rems.l %d2,%d1:%d0
	add.l #48,%d1
	move.b %d1,(%a0)+
	movem.l (%sp),#28
	move.l %a0,%d0
	lea (12,%sp),%sp
	rts
.Lmu_68:
	move.b #45,(%a0)+
	neg.l %d0
	moveq #99,%d1
	cmp.l %d0,%d1
	jlt .Lmu_69
.Lmu_62:
	moveq #9,%d4
	cmp.l %d0,%d4
	jlt .Lmu_63
	moveq #10,%d2
	rems.l %d2,%d1:%d0
	add.l #48,%d1
	move.b %d1,(%a0)+
	movem.l (%sp),#28
	move.l %a0,%d0
	lea (12,%sp),%sp
	rts
	.align	2
	.globl	mu_prep
mu_prep:
	lea (-184,%sp),%sp
	moveq #7,%d0
	movem.l #31996,(%sp)
	move.l 188(%sp),%d3
	move.l 192(%sp),%d1
	cmp.l %d3,%d0
	jcs .Lmu_70
	move.l 1187521622,%a0
	moveq #3,%d4
	move.b 269161679,%d2
	move.l %d3,%d0
	add.l #585803,%a0
	lsl.l #2,%d0
	and.l %d4,%d2
	move.l #6322,%d4
	add.l %d3,%d0
	muls.l %d4,%d2
	add.l %d2,%a0
	add.l %d0,%a0
	move.b (%a0),47(%sp)
	mvz.b 47(%sp),%d0
	move.l %d0,%a4
	tst.b 47(%sp)
	jlt .Lmu_117
	move.l %d0,%d2
	move.l #1096,%d0
	muls.l %d0,%d2
	add.l #269161712,%d2
	tst.l %d1
	jeq .Lmu_110
	moveq #24,%d0
	muls.l %d3,%d0
	lea mu_cs,%a3
.Lmu_74:
	move.l %d0,%a1
	clr.l %d0
	addq.l #1,mu_preps
	add.l #mu_cname,%a1
.Lmu_77:
	move.l %d2,%a0
	add.l %d0,%a0
	move.b (%a0),%d1
	move.b %d1,(%a1,%d0.l)
	addq.l #1,%d0
	move.b (%a0),%d1
	jeq .Lmu_76
	moveq #24,%d1
	cmp.l %d0,%d1
	jne .Lmu_77
.Lmu_76:
	move.l %sp,%d5
	add.l #52,%d5
	move.l %d5,-(%sp)
	move.l %sp,%d4
	add.l #52,%d4
	move.l %d4,-(%sp)
	move.l %a4,-(%sp)
	lea (59,%sp),%a0
	move.b (%a0),(%a3,%d3.l)
	lea mu_name,%a2
	jsr (%a2)
	lea (12,%sp),%sp
	lea mu_cms,%a0
	move.l %d0,%a5
	not.l %d0
	add.l %d0,%d0
	subx.l %d0,%d0
	neg.l %d0
	move.b %d0,(%a0,%d3.l)
	tst.l %a5
	jlt .Lmu_70
	move.w %a5,%d0
	lea mu_croot,%a0
	move.l %a4,%d6
	move.l %d6,%d2
	lea mu_same,%a3
	subq.l #1,%d2
	move.b %d0,(%a0,%d3.l)
	tst.l %d6
	jeq .Lmu_81
.Lmu_78:
	move.l %a4,-(%sp)
	move.l %d2,-(%sp)
	jsr (%a3)
	addq.l #8,%sp
	tst.l %d0
	jeq .Lmu_81
	move.l %d2,%d6
	move.l %d6,%d2
	subq.l #1,%d2
	tst.l %d6
	jne .Lmu_78
.Lmu_81:
	move.l %a4,%d7
	moveq #127,%d1
	move.l %d7,%d2
	addq.l #1,%d2
	lea mu_same,%a3
	cmp.l %d7,%d1
	jeq .Lmu_83
.Lmu_82:
	move.l %a4,-(%sp)
	move.l %d2,-(%sp)
	jsr (%a3)
	addq.l #8,%sp
	tst.l %d0
	jeq .Lmu_118
	move.l %d2,%d7
	moveq #127,%d1
	move.l %d7,%d2
	addq.l #1,%d2
	cmp.l %d7,%d1
	jne .Lmu_82
.Lmu_83:
	lea 56(%sp,%d6.l),%a3
	move.l %d6,%d2
.Lmu_87:
	move.l %d5,-(%sp)
	move.l %d4,-(%sp)
	move.l %d2,-(%sp)
	jsr (%a2)
	lea (12,%sp),%sp
	move.l %d2,%d1
	addq.l #1,%d2
	move.b %d0,(%a3)+
	cmp.l %d7,%d1
	jne .Lmu_87
.Lmu_84:
	lsl.l #7,%d3
	lea 57(%sp,%d7.l),%a2
	move.l %sp,%d5
	sub.l %a1,%a1
	add.l #56,%d5
	move.l %d3,%a6
	move.l %d3,%a3
	add.l #mu_mslot,%a6
	add.l #mu_mptch,%a3
.Lmu_86:
	cmp.l %d6,%d7
	jcs .Lmu_96
	move.l %d5,%a0
	move.l %a5,%d4
	add.l %d6,%a0
	move.l %a4,%d2
	move.l #1000,%d3
.Lmu_91:
	mvs.b (%a0)+,%d1
	move.l %a1,%d0
	sub.l %d1,%d0
	jmi .Lmu_119
.Lmu_89:
	cmp.l %d0,%d3
	jle .Lmu_90
	move.l %a0,%d2
	sub.l %d5,%d2
	subq.l #1,%d2
	move.l %d1,%d4
	move.l %d0,%d3
.Lmu_90:
	cmp.l %a0,%a2
	jne .Lmu_91
.Lmu_88:
	move.l %a1,%d0
	sub.l %d4,%d0
	move.b %d2,(%a6,%a1.l)
	moveq #-12,%d4
	cmp.l %d0,%d4
	jle .Lmu_92
	moveq #-12,%d0
.Lmu_93:
	muls.w #5,%d0
	add.l #64,%d0
	move.b %d0,(%a3,%a1.l)
	addq.l #1,%a1
	cmp.l #128,%a1
	jne .Lmu_86
.Lmu_70:
	movem.l (%sp),#31996
	lea (184,%sp),%sp
	rts
.Lmu_117:
	st %d1
	clr.b %d4
	lea mu_cs,%a0
	move.b %d1,(%a0,%d3.l)
	lea mu_cms,%a0
	move.b %d4,(%a0,%d3.l)
	movem.l (%sp),#31996
	lea (184,%sp),%sp
	rts
.Lmu_119:
	move.l %d1,%d0
	sub.l %a1,%d0
	jra .Lmu_89
.Lmu_92:
	moveq #12,%d1
	cmp.l %d0,%d1
	jge .Lmu_93
	moveq #12,%d0
	muls.w #5,%d0
	add.l #64,%d0
	move.b %d0,(%a3,%a1.l)
	addq.l #1,%a1
	cmp.l #128,%a1
	jne .Lmu_86
	jra .Lmu_70
.Lmu_96:
	move.b 47(%sp),%d2
	move.l %a5,%d4
	jra .Lmu_88
.Lmu_110:
	lea mu_cs,%a3
	mvz.b (%a3,%d3.l),%d0
	cmp.l %d0,%a4
	jeq .Lmu_111
	moveq #24,%d0
	muls.l %d3,%d0
	addq.l #1,mu_preps
	move.l %d0,%a1
	clr.l %d0
	add.l #mu_cname,%a1
	jra .Lmu_77
.Lmu_111:
	moveq #24,%d0
	muls.l %d3,%d0
	move.l %d0,%a1
	add.l #mu_cname,%a1
.Lmu_75:
	move.l %d2,%a0
	add.l %d1,%a0
	move.b (%a0),%d4
	mvs.b (%a1,%d1.l),%d5
	addq.l #1,%d1
	mvs.b %d4,%d4
	cmp.l %d5,%d4
	jne .Lmu_74
	move.b (%a0),%d4
	jeq .Lmu_70
	moveq #24,%d4
	cmp.l %d1,%d4
	jne .Lmu_75
	movem.l (%sp),#31996
	lea (184,%sp),%sp
	rts
.Lmu_118:
	cmp.l %d7,%d6
	jhi .Lmu_84
	lea 56(%sp,%d6.l),%a3
	move.l %d6,%d2
	jra .Lmu_87
	.align	2
	.globl	mu_ms
mu_ms:
	lea (-12,%sp),%sp
	moveq #7,%d1
	move.l 16(%sp),%d0
	movem.l #28,(%sp)
	cmp.l %d0,%d1
	jcs .Lmu_123
	move.l 1187521622,%a0
	moveq #3,%d4
	move.b 269161679,%d2
	move.l %d0,%d1
	add.l #585803,%a0
	lsl.l #2,%d1
	lea mu_cs,%a1
	mvz.b (%a1,%d0.l),%d3
	and.l %d4,%d2
	move.l #6322,%d4
	add.l %d0,%d1
	muls.l %d4,%d2
	clr.b %d4
	add.l %d2,%a0
	st %d2
	add.l %d1,%a0
	move.b (%a0),%d1
	lea (23,%sp),%a0
	move.b (%a0),mu_dk
	move.b %d4,mu_do
	move.b %d2,mu_ds
	mvz.b %d1,%d2
	move.b %d1,mu_dt
	cmp.l %d3,%d2
	jne .Lmu_123
	lea mu_cms,%a0
	tst.b (%a0,%d0.l)
	jeq .Lmu_123
	lea mu_croot,%a0
	move.b (%a0,%d0.l),%d1
	move.l 20(%sp),%a0
	addq.l #1,mu_ms_calls
	cmp.l #135,%a0
	jhi .Lmu_124
	mvz.b %d1,%d1
	lea -12(%a0,%d1.l),%a1
	cmp.l #128,%a1
	jlt .Lmu_126
.Lmu_130:
	move.w #127,%a1
.Lmu_127:
	lsl.l #7,%d0
	moveq #5,%d4
	move.l %d0,%a0
	add.l #mu_mptch,%a0
	mvz.b (%a0,%a1.l),%d2
	move.l %d0,%a0
	add.l #mu_mslot,%a0
	move.b (%a0,%a1.l),%d3
	move.l %d2,%d1
	add.l #-64,%d1
	divs.l %d4,%d1
	move.b %d3,mu_ds
	mvz.b %d3,%d0
	lsl.l #8,%d0
	move.b %d1,mu_do
	or.l %d2,%d0
	bset #16,%d0
.Lmu_120:
	movem.l (%sp),#28
	lea (12,%sp),%sp
	rts
.Lmu_123:
	movem.l (%sp),#28
	clr.l %d0
	lea (12,%sp),%sp
	rts
.Lmu_124:
	move.l 20(%sp),%a1
	lea (-128,%a1),%a1
	cmp.l #128,%a1
	jge .Lmu_130
.Lmu_126:
	tst.l %a1
	jge .Lmu_127
	lsl.l #7,%d0
	sub.l %a1,%a1
	moveq #5,%d4
	move.l %d0,%a0
	add.l #mu_mptch,%a0
	mvz.b (%a0,%a1.l),%d2
	move.l %d0,%a0
	add.l #mu_mslot,%a0
	move.b (%a0,%a1.l),%d3
	move.l %d2,%d1
	add.l #-64,%d1
	divs.l %d4,%d1
	move.b %d3,mu_ds
	mvz.b %d3,%d0
	lsl.l #8,%d0
	move.b %d1,mu_do
	or.l %d2,%d0
	bset #16,%d0
	jra .Lmu_120
	.align	2
	.globl	mu_note
mu_note:
	move.l %d3,-(%sp)
	moveq #7,%d0
	move.l %d2,-(%sp)
	move.l 12(%sp),%d3
	cmp.l %d3,%d0
	jcs .Lmu_136
	move.l 16(%sp),%d0
	moveq #118,%d1
	subq.l #8,%d0
	cmp.l %d0,%d1
	jcs .Lmu_136
	move.l 16(%sp),%d2
	add.l #128,%d2
	tst.l 20(%sp)
	jeq .Lmu_139
	clr.l -(%sp)
	move.l %d3,-(%sp)
	jsr mu_prep
	move.l %d2,-(%sp)
	move.l %d3,-(%sp)
	jsr mu_press
	lea (16,%sp),%sp
	moveq #1,%d0
.Lmu_131:
	move.l (%sp)+,%d2
	move.l (%sp)+,%d3
	rts
.Lmu_136:
	move.l (%sp)+,%d2
	clr.l %d0
	move.l (%sp)+,%d3
	rts
.Lmu_139:
	move.l %d2,-(%sp)
	move.l %d3,-(%sp)
	jsr mu_release
	addq.l #8,%sp
	moveq #1,%d0
	jra .Lmu_131
	.align	2
	.globl	mu_is_ms
mu_is_ms:
	move.l %d2,-(%sp)
	moveq #7,%d0
	move.l 8(%sp),%d2
	cmp.l %d2,%d0
	jcc .Lmu_145
	move.l (%sp)+,%d2
	clr.l %d0
	rts
.Lmu_145:
	clr.l -(%sp)
	move.l %d2,-(%sp)
	jsr mu_prep
	addq.l #8,%sp
	lea mu_cms,%a0
	mvz.b (%a0,%d2.l),%d0
	move.l (%sp)+,%d2
	rts
.Lmu_C0:
	.string	"MULTI"
	.align	2
	.globl	mu_dbgname
mu_dbgname:
	lea (-12,%sp),%sp
	movem.l #1036,(%sp)
	mvz.b mu_dk,%d3
	cmp.l #255,%d3
	jeq .Lmu_153
	move.b -2147483648,%d0
	moveq #7,%d1
	move.l #1176,%d2
	and.l %d1,%d0
	move.w %d0,%d1
	muls.l %d2,%d0
	move.l %d0,%a0
	add.l #mu_extra_voices+1176,%d0
	add.l #mu_extra_voices,%a0
	mulu.w #168,%d1
	move.l %d1,%a1
	add.l #-2147464744,%a1
	move.b (%a1),%d2
	sne %d2
	mvs.b %d2,%d2
	neg.l %d2
.Lmu_149:
	tst.b (%a0)
	jeq .Lmu_148
	addq.l #1,%d2
.Lmu_148:
	lea (168,%a0),%a0
	cmp.l %a0,%d0
	jne .Lmu_149
	moveq #75,%d0
	move.l %d3,-(%sp)
	pea mu_dbuf+1
	lea dec,%a2
	move.b %d0,mu_dbuf
	jsr (%a2)
	mvz.b mu_ds,%d0
	addq.l #8,%sp
	cmp.l #255,%d0
	jeq .Lmu_157
	move.b #83,(%a0)+
	mvz.b mu_ds,%d0
	move.l %d0,%a1
	pea 1(%a1)
	move.l %a0,-(%sp)
	jsr (%a2)
	move.b mu_do,%d0
	addq.l #8,%sp
	tst.b %d0
	jlt .Lmu_152
	move.b #43,(%a0)+
	move.b mu_do,%d0
.Lmu_152:
	mvs.b %d0,%d0
	move.l %d0,-(%sp)
	move.l %a0,-(%sp)
	jsr (%a2)
	addq.l #8,%sp
	move.b #86,(%a0)+
	move.l %d2,-(%sp)
	move.l %a0,-(%sp)
	jsr (%a2)
	addq.l #8,%sp
	clr.b (%a0)
	lea mu_dbuf,%a0
.Lmu_146:
	movem.l (%sp),#1036
	move.l %a0,%d0
	lea (12,%sp),%sp
	rts
.Lmu_157:
	move.b #84,(%a0)+
	mvz.b mu_dt,%d0
	move.l %d0,%a1
	pea 1(%a1)
	move.l %a0,-(%sp)
	jsr (%a2)
	addq.l #8,%sp
	move.b #86,(%a0)+
	move.l %d2,-(%sp)
	move.l %a0,-(%sp)
	jsr (%a2)
	addq.l #8,%sp
	clr.b (%a0)
	lea mu_dbuf,%a0
	jra .Lmu_146
.Lmu_153:
	movem.l (%sp),#1036
	lea .Lmu_C0,%a0
	move.l %a0,%d0
	lea (12,%sp),%sp
	rts
	.align	2
	.globl	mu_env_press
mu_env_press:
	lea (-28,%sp),%sp
	moveq #6,%d0
	move.l 32(%sp),%d1
	move.l 40(%sp),%a0
	movem.l #31756,(%sp)
	lsl.l #3,%d1
	move.l 36(%sp),%d2
	cmp.l %a0,%d0
	jcc .Lmu_171
	lea mu_env_lvl,%a1
	lea mu_env_st,%a4
	lea mu_env_note,%a3
	lea mu_env_fast,%a2
.Lmu_159:
	cmp.l #255,%d2
	jeq .Lmu_160
	move.l %d1,%a0
	move.l %d1,%a5
	move.l %d1,%a6
	add.l #mu_env_st+1,%a0
	add.l #mu_env_note,%a5
	add.l #mu_env_fast,%a6
	moveq #1,%d0
.Lmu_162:
	tst.b (%a0)+
	jeq .Lmu_161
	mvz.b (%a5,%d0.l),%d3
	cmp.l %d3,%d2
	jeq .Lmu_174
.Lmu_161:
	addq.l #1,%d0
	moveq #8,%d3
	cmp.l %d0,%d3
	jne .Lmu_162
.Lmu_160:
	moveq #1,%d0
	clr.b %d3
	move.b %d2,(%a3,%d1.l)
	clr.l (%a1,%d1.l*4)
	move.b %d0,(%a4,%d1.l)
	move.b %d3,(%a2,%d1.l)
	movem.l (%sp),#31756
	lea (28,%sp),%sp
	rts
.Lmu_174:
	moveq #1,%d3
	move.b %d3,(%a6,%d0.l)
	moveq #4,%d3
	addq.l #1,%d0
	move.b %d3,-1(%a0)
	moveq #8,%d3
	cmp.l %d0,%d3
	jne .Lmu_162
	jra .Lmu_160
.Lmu_171:
	lea 1(%a0,%d1.l),%a0
	lea mu_env_st,%a4
	lea (%a4,%d1.l),%a5
	lea mu_env_note,%a3
	lea mu_env_fast,%a2
	lea mu_env_lvl,%a1
	move.b (%a5),(%a4,%a0.l)
	lea (%a3,%d1.l),%a5
	move.b (%a5),(%a3,%a0.l)
	lea (%a2,%d1.l),%a5
	move.b (%a5),(%a2,%a0.l)
	lea (%a1,%d1.l*4),%a5
	move.l (%a5),(%a1,%a0.l*4)
	jra .Lmu_159
	.align	2
	.globl	mu_env_release
mu_env_release:
	move.l 4(%sp),%d0
	lea mu_env_st,%a0
	lsl.l #3,%d0
	add.l 8(%sp),%d0
	tst.b (%a0,%d0.l)
	jeq .Lmu_175
	moveq #4,%d1
	move.b %d1,(%a0,%d0.l)
.Lmu_175:
	rts
	.align	2
	.globl	mu_env_step
mu_env_step:
	lea (-28,%sp),%sp
	move.l 32(%sp),%d1
	movem.l #3196,(%sp)
	moveq #72,%d4
	moveq #127,%d2
	muls.l %d1,%d4
	moveq #127,%d5
	lsl.l #3,%d1
	lea mu_env_st,%a2
	lea mu_env_lvl,%a1
	move.l %d4,%a0
	add.l #-2147481570,%a0
	move.b (%a0),%d0
	add.l 36(%sp),%d1
	mvz.b (%a2,%d1.l),%d3
	and.l %d2,%d0
	swap %d0
	clr.w %d0
	move.l %d0,%d2
	divu.l %d5,%d2
	moveq #3,%d5
	move.l %d2,%d0
	cmp.l %d3,%d5
	jeq .Lmu_187
	move.l (%a1,%d1.l*4),%d5
	moveq #3,%d6
	cmp.l %d3,%d6
	jcs .Lmu_181
	moveq #1,%d6
	cmp.l %d3,%d6
	jeq .Lmu_182
	subq.l #2,%d3
	tst.l %d3
	jne .Lmu_184
	move.l %d4,%a3
	add.l #-2147481571,%a3
	move.b (%a3),%d3
	moveq #127,%d4
	move.l #65536,%a0
	and.l %d4,%d3
	tst.l %d3
	jeq .Lmu_188
	muls.l %d3,%d3
	move.l #8268,%d6
	muls.l %d6,%d3
	move.l #10000,%d6
	divu.l %d6,%d3
	move.l %a0,%d4
	addq.l #3,%d3
	divu.l %d3,%d4
	move.l %d4,%a0
	addq.l #1,%a0
.Lmu_188:
	add.l %a0,%d2
	cmp.l %d2,%d5
	jhi .Lmu_189
	lea mu_env_note,%a0
	mvz.b (%a0,%d1.l),%d2
	cmp.l #255,%d2
	jeq .Lmu_206
	moveq #3,%d2
	move.b %d2,(%a2,%d1.l)
.Lmu_187:
	movem.l (%sp),#3196
	move.l %d0,(%a1,%d1.l*4)
	lea (28,%sp),%sp
	rts
.Lmu_181:
	subq.l #4,%d3
	tst.l %d3
	jne .Lmu_184
	lea mu_env_fast,%a0
	move.l #13107,%d2
	tst.b (%a0,%d1.l)
	jne .Lmu_191
	move.l %d4,%a0
	add.l #-2147481567,%a0
	move.b (%a0),%d0
	moveq #127,%d3
	moveq #1,%d2
	swap %d2
	and.l %d3,%d0
	tst.l %d0
	jeq .Lmu_191
	muls.l %d0,%d0
	move.l #8268,%d4
	move.l #10000,%d6
	muls.l %d4,%d0
	divu.l %d6,%d0
	moveq #1,%d2
	swap %d2
	addq.l #3,%d0
	divu.l %d0,%d2
	addq.l #1,%d2
.Lmu_191:
	cmp.l %d2,%d5
	jhi .Lmu_192
	clr.b %d0
	move.b %d0,(%a2,%d1.l)
.Lmu_184:
	movem.l (%sp),#3196
	clr.l %d0
	move.l %d0,(%a1,%d1.l*4)
	lea (28,%sp),%sp
	rts
.Lmu_182:
	move.l %d4,%a0
	add.l #-2147481572,%a0
	move.b (%a0),%d2
	moveq #127,%d3
	moveq #1,%d0
	swap %d0
	and.l %d3,%d2
	tst.l %d2
	jeq .Lmu_186
	muls.l %d2,%d2
	move.l #8268,%d4
	move.l #10000,%d6
	muls.l %d4,%d2
	divu.l %d6,%d2
	moveq #1,%d0
	swap %d0
	addq.l #3,%d2
	divu.l %d2,%d0
	addq.l #1,%d0
.Lmu_186:
	add.l %d5,%d0
	cmp.l #65536,%d0
	jcs .Lmu_187
	moveq #2,%d0
	move.b %d0,(%a2,%d1.l)
	moveq #1,%d0
	swap %d0
	movem.l (%sp),#3196
	move.l %d0,(%a1,%d1.l*4)
	lea (28,%sp),%sp
	rts
.Lmu_189:
	move.l %d5,%d0
	sub.l %a0,%d0
	movem.l (%sp),#3196
	move.l %d0,(%a1,%d1.l*4)
	lea (28,%sp),%sp
	rts
.Lmu_192:
	move.l %d5,%d0
	sub.l %d2,%d0
	movem.l (%sp),#3196
	move.l %d0,(%a1,%d1.l*4)
	lea (28,%sp),%sp
	rts
.Lmu_206:
	moveq #4,%d2
	move.b %d2,(%a2,%d1.l)
	jra .Lmu_187
	.align	2
	.globl	mu_env_off
mu_env_off:
	move.l 4(%sp),%d0
	move.l 8(%sp),%a1
	lsl.l #3,%d0
	move.l %d0,%a0
	add.l #mu_env_st,%a0
	tst.b (%a0,%a1.l)
	seq %d0
	mvs.b %d0,%d0
	neg.l %d0
	rts
	.align	2
	.globl	mu_amp_ui
mu_amp_ui:
	lea (-32,%sp),%sp
	movem.l #7292,(%sp)
	move.b 269161676,%d2
	move.l 1187521622,%d0
	move.b 269161679,%d1
	move.l -2147483630,%a0
	tst.l %a0
	jne .Lmu_219
	moveq #3,%d3
	and.l %d3,%d1
	moveq #7,%d3
	and.l %d3,%d2
	move.l %d0,%a0
	move.l #6322,%d0
	add.l #585122,%a0
	muls.l %d0,%d1
	add.l %d2,%a0
	moveq #5,%d2
	add.l %d1,%a0
	move.b (%a0),%d3
	eor.l %d2,%d3
	tst.b %d3
	seq %d3
	neg.l %d3
	mvz.b %d3,%d3
	move.l %d3,%d0
.Lmu_210:
	mvz.b mu_amp_shown,%d1
	cmp.l %d1,%d0
	jeq .Lmu_209
	move.b %d3,mu_amp_shown
	lea fmt_at,%a4
	clr.l %d4
	lea fmt_stock,%a2
	lea lab_at,%a3
.Lmu_216:
	move.l %d4,%d1
	tst.l %d3
	jeq .Lmu_212
	add.l #lab_multi,%d1
	move.l (%a3)+,%d2
	sub.l %d1,%d2
	move.l %d1,%a0
	addq.l #6,%d1
.Lmu_214:
	lea (%a0,%d2.l),%a1
	move.b (%a0)+,%d0
	move.b %d0,(%a1)
	cmp.l %d1,%a0
	jne .Lmu_214
	tst.l %d3
	jne .Lmu_220
	moveq #24,%d0
	addq.l #4,%a2
	move.l -4(%a2),%d1
	move.l %d1,%d6
	lsr.l %d0,%d6
	move.l (%a4)+,%d0
	move.l %d1,%d5
	move.l %d0,%a0
	move.l %d1,%d2
	clr.w %d5
	swap %d5
	move.b %d6,(%a0)+
	lsr.l #8,%d2
	move.l %d0,%a1
	addq.l #3,%d0
	addq.l #2,%a1
	addq.l #6,%d4
	move.b %d5,(%a0)
	move.l %d0,%a0
	moveq #18,%d0
	move.b %d2,(%a1)
	move.b %d1,(%a0)
	cmp.l %d4,%d0
	jne .Lmu_216
.Lmu_225:
	tst.l %d3
	jeq .Lmu_217
	moveq #17,%d2
	moveq #3,%d3
	moveq #40,%d1
	moveq #20,%d0
	move.b %d2,1074608919
	moveq #64,%d2
	move.b %d2,1074608838
	move.b %d3,1074608839
	move.b %d1,1074608840
	move.b %d0,1074608841
.Lmu_209:
	movem.l (%sp),#7292
	lea (32,%sp),%sp
	rts
.Lmu_220:
	clr.b %d6
	move.l (%a4)+,%d0
	move.l %d0,%a0
	clr.b %d5
	clr.b %d2
	clr.b %d1
	move.l %d0,%a1
	addq.l #3,%d0
	addq.l #2,%a1
	addq.l #4,%a2
	addq.l #6,%d4
	move.b %d6,(%a0)+
	move.b %d5,(%a0)
	move.l %d0,%a0
	moveq #18,%d0
	move.b %d2,(%a1)
	move.b %d1,(%a0)
	cmp.l %d4,%d0
	jne .Lmu_216
	jra .Lmu_225
.Lmu_212:
	add.l #lab_stock,%d1
	move.l (%a3)+,%d2
	sub.l %d1,%d2
	move.l %d1,%a0
	addq.l #6,%d1
	jra .Lmu_214
.Lmu_219:
	clr.l %d0
	clr.l %d3
	jra .Lmu_210
.Lmu_217:
	moveq #-127,%d3
	moveq #64,%d2
	moveq #43,%d1
	moveq #-92,%d0
	move.b %d3,1074608919
	moveq #3,%d3
	move.b %d2,1074608838
	move.b %d3,1074608839
	move.b %d1,1074608840
	move.b %d0,1074608841
	jra .Lmu_209
	.align	2
	.globl	mu_dsp_amp
mu_dsp_amp:
	move.l %d2,-(%sp)
	moveq #3,%d2
	move.l 1187521622,%a1
	move.b 269161679,%d0
	move.l 8(%sp),%d1
	move.l %d1,%a0
	add.l #-2147482864,%d1
	add.l #-2147483376,%a0
	and.l %d2,%d0
	move.l #6322,%d2
	muls.l %d2,%d0
	add.l %d0,%a1
	add.l #585122,%a1
.Lmu_228:
	move.b (%a1),%d0
	addq.l #1,%a1
	mvz.b %d0,%d0
	subq.l #5,%d0
	tst.l %d0
	jne .Lmu_227
	move.w #32512,%d0
	clr.w (%a0)
	move.w %d0,2(%a0)
	move.w %d0,4(%a0)
	move.w %d0,10(%a0)
.Lmu_227:
	lea (64,%a0),%a0
	cmp.l %a0,%d1
	jne .Lmu_228
	move.l (%sp)+,%d2
	rts
	.align	2
	.globl	mu_env_pre
mu_env_pre:
	lea (-12,%sp),%sp
	movem.l #28,(%sp)
	move.l 16(%sp),%d3
	move.l #168,%d0
	move.l %d3,%d2
	lsl.l #3,%d2
	muls.l %d3,%d0
	move.l %d0,%a0
	add.l #-2147464744,%a0
	move.b (%a0),%d0
	jeq .Lmu_233
	lea mu_env_st,%a0
	tst.b (%a0,%d2.l)
	jne .Lmu_239
	move.l %d3,-(%sp)
	jsr 1073768480
	addq.l #4,%sp
.Lmu_233:
	move.l #1176,%d1
	clr.l %d4
	muls.l %d3,%d1
	move.l %d2,%a1
	moveq #1,%d0
	add.l #mu_env_st,%a1
	lea mu_extra_voices,%a0
.Lmu_237:
	move.b (%a0,%d1.l),%d2
	jeq .Lmu_236
	tst.b (%a1,%d0.l)
	jne .Lmu_240
	clr.b %d2
	move.b %d2,(%a0,%d1.l)
.Lmu_236:
	addq.l #1,%d0
	add.l #168,%d1
	moveq #8,%d2
	cmp.l %d0,%d2
	jne .Lmu_237
.Lmu_251:
	tst.l %d4
	jeq .Lmu_250
.Lmu_232:
	movem.l (%sp),#28
	lea (12,%sp),%sp
	rts
.Lmu_250:
	lea mu_relpend,%a0
	tst.b (%a0,%d3.l)
	jeq .Lmu_232
	clr.b %d1
	move.l %d3,%d0
	add.l #296878293,%d0
	lsl.l #2,%d0
	moveq #64,%d2
	move.b %d1,(%a0,%d3.l)
	move.l %d0,%a0
	move.l (%a0),%d0
	or.l %d2,%d0
	movem.l (%sp),#28
	move.l %d0,(%a0)
	lea (12,%sp),%sp
	rts
.Lmu_239:
	move.l #1176,%d1
	moveq #1,%d4
	move.l %d2,%a1
	moveq #1,%d0
	muls.l %d3,%d1
	add.l #mu_env_st,%a1
	lea mu_extra_voices,%a0
	jra .Lmu_237
.Lmu_240:
	moveq #1,%d4
	addq.l #1,%d0
	add.l #168,%d1
	moveq #8,%d2
	cmp.l %d0,%d2
	jne .Lmu_237
	jra .Lmu_251
mu_pc0:
	.string	"\t\013"
	.ascii	"\002\004\005\007"
	.globl	mu_amp_shown
mu_amp_shown:
	.fill	1,1,0
	.align	2
fmt_stock:
	.long	1073984464
	.long	1073984520
	.long	1073984644
	.align	2
fmt_at:
	.long	1074608726
	.long	1074608730
	.long	1074608742
	.align	2
lab_at:
	.long	1074608548
	.long	1074608554
	.long	1074608572
lab_stock:
	.string	"HOLD"
	.fill	1,1,0
	.string	"REL"
	.fill	2,1,0
	.string	"XVOL"
	.fill	1,1,0
lab_multi:
	.string	"DEC"
	.fill	2,1,0
	.string	"SUS"
	.fill	2,1,0
	.string	"REL"
	.fill	2,1,0
	.globl	mu_env_fast
mu_env_fast:
	.fill	64,1,0
	.globl	mu_env_note
mu_env_note:
	.fill	64,1,0
	.globl	mu_env_st
mu_env_st:
	.fill	64,1,0
	.globl	mu_env_lvl
	.align	2
mu_env_lvl:
	.fill	256,1,0
	.balign 1
mu_dbuf:
	.fill 24,1,0
	.balign 1
mu_mptch:
	.fill 1024,1,0
	.balign 1
mu_mslot:
	.fill 1024,1,0
	.balign 1
mu_cname:
	.fill 192,1,0
	.balign 1
mu_croot:
	.fill 8,1,0
	.balign 1
mu_cms:
	.fill 8,1,0
mu_cs:
	.ascii	"\377\377\377\377\377\377\377\377"
	.globl	mu_do
mu_do:
	.fill	1,1,0
	.globl	mu_dt
mu_dt:
	.byte	-1
	.globl	mu_ds
mu_ds:
	.byte	-1
	.globl	mu_dk
mu_dk:
	.byte	-1
	.globl	mu_preps
	.align	2
mu_preps:
	.fill	4,1,0
	.globl	mu_ms_calls
	.align	2
mu_ms_calls:
	.fill	4,1,0
| objcopy omits trailing all-zero bytes: end on a nonzero word.
        .balign 4
        .long   0x4d554c54                  | "MULT"
