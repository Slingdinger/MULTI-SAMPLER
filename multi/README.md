# MULTI

A multisampler on one audio track: eight voices, each playing its own sample at its own pitch, with
no timestretch. Forked from repeat98's POLY MACHINE (four voices; source pinned in
`modules/poly-machine/upstream`).

## Set up

1. Load the multisample into FLEX slots in a row, one note a file, named with the note:
   `MELLO C2.wav`, `MELLO C#2.wav` ... (C3 = MIDI 48; `#`, `s` or `b` for sharps and flats). The note
   must not follow another letter (`MELLO C3`, `MELLO_C3`, `M-C3` work; `TONEC3` doesn't).
2. On the audio track: **FUNC + SRC**, the machine list's sixth row **MULTI**, **YES**. Pick any file
   of the set as its sample.

## Play

- **MIDI ROUTING:** route a MIDI track to it (NOTE SETUP, MODE **ALL** for one MULTI track; **LINK**
  fills one MULTI track's eight voices, then the next routed track).
- **CHROMATIC keys** on the track, at stock's pitches: trig 1 is an octave below the chosen file's
  note (at it after FUNC + RIGHT), and each key picks its nearest file.
- **MIDI IN** on the track's channel (AUDIO NOTE IN on): notes 72-96, stock's map.

Each note plays the file with the nearest note among the slots around the track's sample that share
its name, pitched with a PTCH lock (at most 12 semitones from it). A note that has its own file plays
it at its own speed, so the voice is copied straight into the mix (no interpolation): the cheaper
case, and the reason to sample every key.

A ninth note takes over the oldest voice. Every voice plays at -6 dB however many sound, so a note
keeps its level when others start; the mix clips (never wraps) past full scale. A track whose sample has no note in its name plays like POLY:
every voice its own pitch, the same sample.

## Limits

- FLEX only: the set lives in sample RAM (85.5 MB a project, shared).
- POLY's FUNC + LEFT / RIGHT octave walk is left out (SCALE QUANTIZER owns that hook): stock's two
  octaves.
- Not with POLY MACHINE, OCTA303 or SYNTH MACHINE in the same build.
- Measured under the emulator, not on a unit.
