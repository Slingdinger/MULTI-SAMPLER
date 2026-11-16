# MIDI ROUTING

MIDI tracks play audio tracks, set up in NOTE SETUP and saved with the project. A MIDI track can
play one audio track, layer several, or spread chords over several (one note a track): a
polyphonic instrument from the Octatrack's own sample machines, multisampled from FLEX slots.

## NOTE SETUP

Open NOTE SETUP on a MIDI track (**FUNC + SRC**). The left box is the routing map: MIDI tracks
M1-M8 across, audio tracks T1-T8 down. A filled square is a route.

| Control | What it does |
|---|---|
| Arrows | Move the cursor: its MIDI track's column is inverted, its audio track's number boxed. It opens on the track you opened NOTE SETUP from. |
| YES | Route or unroute the cell. With a CHAN / BANK / PROG / SBNK edit waiting, YES applies it, as stock. |
| D: MODE | For the cursor's MIDI track. **SPRD**: one note a track (chords; a note past the last free track takes the one sounding longest). **ALL**: every note on every routed track. |
| F: OUT | Where the cursor's MIDI track's routed notes also go: **OFF**, **DIN**, **USB**, **BOTH**. |

A new project starts with each MIDI track routed to its own audio track (M1 to T1 ... M8 to T8),
OUT BOTH, so the MIDI tracks still play external gear; untick a cell to stop it. A MIDI track with
no routes is stock. The MIDI track needs a CHAN for its notes to play.

## Multisamples

1. Load the samples into FLEX slots in a row, one note a file, named with the note:
   `MELLO C2.wav`, `MELLO F#2.wav`, `MELLO C3.wav` (C3 = MIDI 48, as the MIDI tracks show it;
   `#`, `s` or `b` for sharps and flats).
2. Put a FLEX machine on each routed audio track, with any file of the set as its sample.

A note plays the file with the nearest note among the slots around the track's sample that share
its name, pitched with a PTCH lock (at most 12 semitones). A sample with no note in its name plays
as itself, pitched from C4 (MIDI 60). The tracks' own AMP, FX, levels and scenes apply; nothing is
written to their sequencers.

## Machines

FLEX and STATIC tracks play routed notes as above. A **MULTI** track (modules/multi) takes them
as its own notes: up to eight at once on the one track, its multisample choosing the files; SPRD
fills a MULTI track's eight voices before the next routed track. Other machines (303, FM, POLY8)
need their adapters, not built yet.

## Linked pairs

An audio track playing a sound generator (MULTI) is linked to its MIDI track (T1 with M1 ...): its
notes come from MIDI only. Its own trigs act as trigless locks (their p-locks and sample locks
apply, no note starts), and TRACKS / CHROMATIC / QUICK MUTE set on one side are set on the other
(TRIG MODES). FLEX and STATIC tracks stay independent.

## What plays

The MIDI track's sequenced notes, its CHROMATIC keys, CHORDS mode and the CHORDS FACTORY page.
Arpeggiator notes: not checked yet.
