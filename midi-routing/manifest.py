"""MIDI ROUTING -- MIDI tracks play audio tracks, set up in NOTE SETUP and saved with the project
(OctaZach 207; it replaces CHORD SPREAD, 206).

NOTE SETUP (FUNC + SRC on a MIDI track): the left box shows the routing, MIDI tracks M1-M8 across,
audio tracks T1-T8 down. The arrows move the cursor (its MIDI track's column inverted, its audio
track's number boxed), YES routes or unroutes that cell (with a CHAN / BANK / PROG / SBNK edit
waiting, YES applies it as stock). D: MODE, F: OUT, for the cursor's MIDI track:
  MODE  ALL: every note on every routed track; SPRD: one note a track (chords)
  OUT   where the routed track's notes also go: OFF, DIN, USB, BOTH
Each routed note plays on its audio track as a CHROMATIC key's live note: the pitch as the track's
PTCH lock (+-12 semitones) and, on a FLEX track whose sample's name holds a note ("MELLO C3.wav"),
the nearest note of the run of slots around it sharing that name, as the sample lock: a multisample.

The sender hook is 303 FOLLOW's (radiohagen's MIDI LOOPBACK operands); the NOTE SETUP D / F entries
are MIDI FOLLOW's RFOL and MIDI HARMONY's F slots.
"""

from remix.schema import (Apply, Category, Detour, Kind, Linked, Module, Number, Option, Poke, Proof,
                          Scope, Setting, Store, SymbolRef)

NOTE_SITES = (0x4009fbae, 0x4009fcf6, 0x4009f8be, 0x4009fc50, 0x4009fcd4, 0x4009f328, 0x400a0020)
P = dict(scope=Scope.PROJECT, apply=Apply.LIVE)
H = bytes.fromhex

MODULE = Module(
    name="midi-routing",
    key="MIDI ROUTING",
    kind=Kind.CF_PATCH,
    category=Category.MIDI_USB,
    author="local",
    author_url="https://github.com/sambanks/octabam",
    proof=Proof.PORT,
    proof_note="the map, cursor, YES, MODE / OUT and routed notes under the port; not on a unit",
    doc="NOTE SETUP shows a MIDI-to-audio routing map (arrows + YES; D MODE ALL/SPRD, F OUT OFF/DIN/USB/BOTH): routed MIDI tracks play audio tracks, multisampled from FLEX slots named by note.",
    requires_brain=True,
    store=Store("octabam.midi-routing"),
    settings=tuple(Setting(m + 1, f"M{m + 1} TRKS", Number(0, 255), default=1 << m, **P,
                           doc=f"the audio tracks MIDI track {m + 1} plays (bit 0 = T1)") for m in range(8))
    + tuple(Setting(m + 9, f"M{m + 1} MODE", Option("ALL", "SPRD"), default="SPRD", **P,
                    doc=f"MIDI track {m + 1}: every note on every routed track, or one note a track") for m in range(8))
    + tuple(Setting(m + 17, f"M{m + 1} OUT", Option("OFF", "DIN", "USB", "BOTH"), default="BOTH", **P,
                    doc=f"where MIDI track {m + 1}'s routed notes also go") for m in range(8)),
    conflicts=(("303 FOLLOW", "the same MIDI-track sender operands and f3_page_send"),
               ("MIDI LOOPBACK", "the same MIDI-track sender operands"),
               ("CHORD SPREAD", "the same MIDI-track sender operands and f3_page_send"),
               ("MIDI FOLLOW", "NOTE SETUP's D slot and its value draw")),
    linked=(Linked("midirouting", "modules/midi-routing/rt.s", cpu="54455", dram=True),),
    pokes=(
        Poke(0x400d3e8a, b"----\0\0", b"MODE\0\0", "NOTE SETUP D label"),
        Poke(0x400d3e96, b"----\0\0", b"OUT\0\0\0", "NOTE SETUP F label"),
        Poke(0x400d3efc, H("00000080"), H("00000002"), "MODE: ALL, SPRD"),
        Poke(0x400d3f04, H("00000080"), H("00000004"), "OUT: OFF, DIN, USB, BOTH"),
        Poke(0x400d3f5c, bytes(4), H("400467a4"), "MODE text widget, like CHAN"),
        Poke(0x400d3f64, bytes(4), H("400467a4"), "OUT text widget"),
        Poke(0x400d3fcb, b"\x01", b"\x11", "enable NOTE SETUP D"),
        Poke(0x400d3fca, b"\x01", b"\x11", "enable NOTE SETUP F"),
    ),
    detours=(
        Detour(0x40036674, H("261524047003"), "midirouting", "rt_dval",
               "NOTE SETUP's D / F values: the cursor's MIDI track's MODE / OUT"),
        Detour(0x4003678a, H("4cd77cfc4fef0034"), "midirouting", "rt_draw",
               "the end of NOTE SETUP's draw: the routing map in the left box", pad_to=8),
        Detour(0x4000b9a2, H("20309c0044c0662a"), "midirouting", "rt_seqtrig",
               "a linked pair: a sound-generator audio track's own trigs carry locks only", pad_to=8),
    ),
    symbol_refs=tuple(SymbolRef(site, 0x40010bc8, "midirouting", "rt_send",
                                "a MIDI-track note can play its routed audio tracks")
                      for site in NOTE_SITES) + (
        SymbolRef(0x4009ea96, 0x40010bc8, "midirouting", "rt_send_live",
                  "a MIDI track's live note-on (CHROMATIC / CHORDS keys) can play its routed audio tracks"),
        SymbolRef(0x4009ea68, 0x40010bc8, "midirouting", "rt_send", "the live note's re-trigger note-off"),
        SymbolRef(0x4009eb50, 0x40010bc8, "midirouting", "rt_send", "the live note-off (key up)"),
        SymbolRef(0x400d3f2c, 0, "midirouting", "rt_fmt_mode", "MODE formatter"),
        SymbolRef(0x400d3f34, 0, "midirouting", "rt_fmt_out", "OUT formatter"),
        SymbolRef(0x400bc64e, 0x4003a8e8, "midirouting", "rt_enc", "NOTE SETUP D encoder: MODE"),
        SymbolRef(0x400bc67a, 0x4003a8e8, "midirouting", "rt_enc", "NOTE SETUP F encoder: OUT"),
        SymbolRef(0x400bc4ba, 0x400321f0, "midirouting", "rt_k_arrow", "NOTE SETUP DOWN: the cursor"),
        SymbolRef(0x400bc4c2, 0x400321f0, "midirouting", "rt_k_arrow", "NOTE SETUP DOWN held"),
        SymbolRef(0x400bc4d4, 0x400321f0, "midirouting", "rt_k_arrow", "NOTE SETUP UP: the cursor"),
        SymbolRef(0x400bc4dc, 0x400321f0, "midirouting", "rt_k_arrow", "NOTE SETUP UP held"),
        SymbolRef(0x400bc4ee, 0x400321f4, "midirouting", "rt_k_arrow", "NOTE SETUP LEFT: the cursor"),
        SymbolRef(0x400bc508, 0x400321f4, "midirouting", "rt_k_arrow", "NOTE SETUP RIGHT: the cursor"),
        SymbolRef(0x400bc522, 0x4004af20, "midirouting", "rt_k_yes", "NOTE SETUP YES: route / unroute the cell"),
        SymbolRef(0x400bc6dc, 0x400597b4, "midirouting", "rt_open", "NOTE SETUP open: the cursor on its track"),
    ),
)
