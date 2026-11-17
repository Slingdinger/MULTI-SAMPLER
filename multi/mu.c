/* MULTI's multisample (mu_ms): a MULTI track whose FLEX sample is named with a note ("MELLO C3.wav")
 * plays the run of slots around it that share that name, each note on the slot with the nearest note,
 * pitched from there with the PTCH lock (5 a semitone, +-12; at the slot's own note PTCH is 0 and the
 * voice takes the render's fast path). C3 = MIDI 48.
 *   Part      [0x46c82456] + 6322 * [0x100b14cf]: FLEX slot +0x8f04b + 5 t
 *   FLEX slot settings record 0x100b14f0 + 0x448 s, the path at +0 */
#define U8(a) (*(volatile unsigned char *)(a))
#define U32(a) (*(volatile unsigned *)(a))
#define SETTINGS(s) (0x100b14f0u + 0x448u * (s))

static int mu_name(unsigned slot, const volatile char **nm, int *pre) {
    const volatile char *s = (const volatile char *)SETTINGS(slot), *n = s;
    int i, len = 0, found = -1;
    for (i = 0; i < 255 && s[i]; i++) if (s[i] == '/') n = s + i + 1;
    while (len < 64 && n[len] && n[len] != '.') len++;
    static const signed char pc[7] = {9, 11, 0, 2, 4, 5, 7};
    for (i = 0; i < len; i++) {
        char c = n[i];
        if (c < 'A' || c > 'G') continue;
        if (i > 0 && ((n[i - 1] >= 'A' && n[i - 1] <= 'Z') || (n[i - 1] >= 'a' && n[i - 1] <= 'z'))) continue;
        int j = i + 1, p = pc[c - 'A'], neg = 0;
        if (j < len && (n[j] == '#' || n[j] == 's' || n[j] == 'S')) { p++; j++; }
        else if (j < len && n[j] == 'b') { p--; j++; }
        if (j < len && n[j] == '-') { neg = 1; j++; }
        if (j >= len || n[j] < '0' || n[j] > '9') continue;
        int oct = n[j] - '0';
        if (neg) oct = -oct;
        int note = 12 * (oct + 1) + p;
        if (note >= 0 && note < 128) { found = note; *pre = i; }
    }
    *nm = n;
    return found;
}

static int mu_same(unsigned a, unsigned b) {
    const volatile char *na, *nb;
    int pa, pb;
    if (mu_name(a, &na, &pa) < 0 || mu_name(b, &nb, &pb) < 0 || pa != pb) return 0;
    for (int i = 0; i < pa; i++) if (na[i] != nb[i]) return 0;
    return 1;
}

unsigned mu_ms_calls, mu_preps;
/* DEBUG (208b): the last key's numbers, shown as the machine name (footer / track box). */
unsigned char mu_dk = 255, mu_ds = 255, mu_dt = 255;
signed char mu_do;

/* The multisample map, per track, built outside the audio path (mu_prep: a CHROMATIC key's press in
 * the UI task, MIDI ROUTING's note, a MIDI IN note) and only read in it (mu_ms: the frame interrupt's
 * queue re-arms a chord's later notes, interrupts masked). 208 parsed the slot names there, ~100
 * names for 35 slots, and the audio dropped out and the unit froze (Zach's MKI, 15 Nov 2026). */
static unsigned char mu_cs[8] = {255, 255, 255, 255, 255, 255, 255, 255};   /* the slot it was built for */
static unsigned char mu_cms[8], mu_croot[8];                              /* 1: a multisample; its own note */
static char mu_cname[8][24];                                              /* its name's start, to see a reload */
static unsigned char mu_mslot[8][128], mu_mptch[8][128];

static unsigned mu_slot_of(unsigned t) {
    unsigned part = U32(0x46c82456u) + 6322u * (U8(0x100b14cfu) & 3u);
    return U8(part + 0x8f04bu + 5u * t);
}

/* force: rebuild even when the slot and its name are unchanged (a UI key press: another slot of the
 * run may have been reloaded). */
void mu_prep(unsigned t, int force) {
    if (t > 7) return;
    unsigned s = mu_slot_of(t);
    if (s > 127) { mu_cs[t] = 255; mu_cms[t] = 0; return; }
    const volatile char *nm0 = (const volatile char *)SETTINGS(s);
    if (!force && mu_cs[t] == s) {
        int same = 1;
        for (int i = 0; i < 24; i++) { if (mu_cname[t][i] != nm0[i]) { same = 0; break; } if (!nm0[i]) break; }
        if (same) return;
    }
    ++mu_preps;
    for (int i = 0; i < 24; i++) { mu_cname[t][i] = nm0[i]; if (!nm0[i]) break; }
    mu_cs[t] = (unsigned char)s;
    const volatile char *nm;
    int pre, r = mu_name(s, &nm, &pre);
    mu_cms[t] = r >= 0;
    if (r < 0) return;
    mu_croot[t] = (unsigned char)r;
    unsigned lo = s, hi = s;
    while (lo > 0 && mu_same(lo - 1, s)) lo--;
    while (hi < 127 && mu_same(hi + 1, s)) hi++;
    signed char root[128];
    for (unsigned q = lo; q <= hi; q++) root[q] = (signed char)mu_name(q, &nm, &pre);
    for (int n = 0; n < 128; n++) {
        int bd = 1000, slot = (int)s, rt = r;
        for (unsigned q = lo; q <= hi; q++) {
            int d = n - root[q];
            if (d < 0) d = -d;
            if (d < bd) { bd = d; slot = (int)q; rt = root[q]; }
        }
        int off = n - rt;
        if (off > 12) off = 12;
        if (off < -12) off = -12;
        mu_mslot[t][n] = (unsigned char)slot;
        mu_mptch[t][n] = (unsigned char)(64 + 5 * off);
    }
}

/* owner: a panel chromatic key 0..135 (key 12 = the sample's own note) or 0x80 + a MIDI note.
 * 0: not a multisample (the POLY encoding stands); else 0x10000 | slot << 8 | PTCH byte. A table read
 * only: safe in the frame interrupt. */
unsigned mu_ms(unsigned t, unsigned owner) {
    if (t > 7) return 0;
    unsigned s = mu_slot_of(t);
    mu_dk = (unsigned char)owner; mu_ds = 255; mu_do = 0; mu_dt = (unsigned char)s;
    if (mu_cs[t] != s || !mu_cms[t]) return 0;
    ++mu_ms_calls;
    int r = mu_croot[t];
    int n = owner < 136u ? r + (int)owner - 12 : (int)owner - 0x80;
    if (n < 0) n = 0;
    if (n > 127) n = 127;
    mu_ds = mu_mslot[t][n]; mu_do = (signed char)(((int)mu_mptch[t][n] - 64) / 5);
    return 0x10000u | (unsigned)mu_mslot[t][n] << 8 | mu_mptch[t][n];
}

/* MIDI ROUTING's adapter: a note on / off on MULTI track t as a MIDI note's owner (0x80 + n, n 8..126,
 * clear of the panel keys 0..135 and of 0xff). poly_press_key / poly_release_key: (d0 track, d1 owner). */
extern void mu_press(unsigned t, unsigned owner);
extern void mu_release(unsigned t, unsigned owner);
int mu_note(unsigned t, unsigned n, int on) {
    if (t > 7 || n < 8 || n > 126) return 0;
    if (on) mu_prep(t, 0);
    if (on) mu_press(t, 0x80u + n); else mu_release(t, 0x80u + n);
    return 1;
}

/* 1: track t's sample is named with a note (MIDI ROUTING sends it the note as played; else as the
 * stock MIDI map's, 84 = the sample's own pitch, so C4 = 60 is moved up two octaves). */
int mu_is_ms(unsigned t) {
    if (t > 7) return 0;
    mu_prep(t, 0);
    return mu_cms[t];
}

/* A diagnostic, not called (209): "K<key>S<slot+1>+<semitones>V<voices>" (S- when the track's sample s has no note:
 * "T<slot+1>" then), for the active track. */
extern unsigned char mu_extra_voices[];
static char mu_dbuf[24];
static char *dec(char *o, int v) {
    if (v < 0) { *o++ = '-'; v = -v; }
    if (v >= 100) *o++ = (char)('0' + v / 100);
    if (v >= 10) *o++ = (char)('0' + v / 10 % 10);
    *o++ = (char)('0' + v % 10);
    return o;
}
const char *mu_dbgname(void) {
    if (mu_dk == 255) return "MULTI";
    unsigned t = U8(0x80000000u) & 7u, v = U8(0x800049d8u + 168u * t) ? 1u : 0u;
    for (unsigned e = 0; e < 7; e++) if (mu_extra_voices[(t * 7u + e) * 168u]) v++;
    char *o = mu_dbuf;
    *o++ = 'K'; o = dec(o, mu_dk);
    if (mu_ds == 255) { *o++ = 'T'; o = dec(o, mu_dt + 1); }
    else { *o++ = 'S'; o = dec(o, mu_ds + 1); if (mu_do >= 0) *o++ = '+'; o = dec(o, mu_do); }
    *o++ = 'V'; o = dec(o, (int)v);
    *o = 0;
    return mu_dbuf;
}

/* ---- MULTI ADSR (OctaZach 222): every voice its own envelope, the track's AMP page as ATK DEC SUS / VOL
 * BAL REL (stock's ATK HOLD REL and the slot after BAL, stock's XVOL, which the track's DSP record no
 * longer sees on a MULTI track: mu_dsp_amp sets its ATK 0, HOLD and REL 127 and XVOL 127 there).
 * Values from the live lane (locks included): 0x80000810 + 72 t + 12 ATK, 13 DEC, 14 SUS, 17 REL.
 * Times: 0 instant, else 0.3 v^2 + 1 ms over the full range (127: ~4.8 s); SUS v/127.
 * One step a render chunk (16 output samples, ~2756 a second). Voice 0 is the primary (the newest
 * note), 1..7 the extensions. A voice let go releases; at 0 it ends (mu_call stops it). A same note
 * pressed again releases its old voice in ~2 ms instead (no two copies of one note). A voice with no
 * key (a sequencer trig) releases once its decay ends. */
enum { E_OFF, E_ATK, E_DEC, E_SUS, E_REL };
unsigned mu_env_lvl[64];                       /* Q16, 65536 = full */
unsigned char mu_env_st[64], mu_env_note[64], mu_env_fast[64];

#define LANE(t, k) U8(0x80000810u + 72u * (t) + (k))

static unsigned mu_step(unsigned v) {          /* the full range over 0.3 v^2 + 1 ms */
    if (!v) return 65536u;
    unsigned chunks = (v * v * 3u * 2756u) / 10000u + 3u;
    return 65536u / chunks + 1u;
}

/* a new primary on track t (owner: its key, 0xff none); old primary moved to extension slot e (0..6),
 * or e = 255 when there was none */
void mu_env_press(unsigned t, unsigned owner, unsigned e) {
    unsigned b = t * 8u;
    if (e < 7u) {
        unsigned x = b + 1u + e;
        mu_env_lvl[x] = mu_env_lvl[b]; mu_env_st[x] = mu_env_st[b];
        mu_env_note[x] = mu_env_note[b]; mu_env_fast[x] = mu_env_fast[b];
    }
    if (owner != 0xffu)
        for (unsigned v = 1; v < 8; v++)
            if (mu_env_st[b + v] != E_OFF && mu_env_note[b + v] == owner) {
                mu_env_st[b + v] = E_REL; mu_env_fast[b + v] = 1;
            }
    mu_env_lvl[b] = 0; mu_env_st[b] = E_ATK; mu_env_note[b] = (unsigned char)owner; mu_env_fast[b] = 0;
}

/* voice v (0 primary, 1..7 extension) of track t let go */
void mu_env_release(unsigned t, unsigned v) {
    unsigned x = t * 8u + v;
    if (mu_env_st[x] != E_OFF) mu_env_st[x] = E_REL;
}

/* one chunk of voice v of track t: its gain (Q16), 0 and E_OFF when it has ended */
unsigned mu_env_step(unsigned t, unsigned v) {
    unsigned x = t * 8u + v, l = mu_env_lvl[x];
    unsigned sus = (LANE(t, 14) & 127u) * 65536u / 127u;
    switch (mu_env_st[x]) {
    case E_ATK: {
        unsigned s = mu_step(LANE(t, 12) & 127u);
        l = l + s >= 65536u ? 65536u : l + s;
        if (l >= 65536u) mu_env_st[x] = E_DEC;
        break;
    }
    case E_DEC: {
        unsigned s = mu_step(LANE(t, 13) & 127u);
        if (l <= sus + s) {
            l = sus;
            mu_env_st[x] = mu_env_note[x] == 0xffu ? E_REL : E_SUS;
        } else l -= s;
        break;
    }
    case E_SUS:
        l = sus;
        break;
    case E_REL: {
        unsigned s = mu_env_fast[x] ? 65536u / 5u : mu_step(LANE(t, 17) & 127u);
        if (l <= s) { l = 0; mu_env_st[x] = E_OFF; } else l -= s;
        break;
    }
    default:
        l = 0;
    }
    mu_env_lvl[x] = l;
    return l;
}

unsigned mu_env_off(unsigned t, unsigned v) { return mu_env_st[t * 8u + v] == E_OFF; }

/* MULTI's AMP page: on a MULTI track ATK DEC SUS / VOL BAL REL, plain numbers, the sixth knob drawn
 * (stock's XVOL slot); else stock's. Called at the main view's draw (0x4004d948). The AMP descriptor
 * 0x400d3950: labels 6 bytes from 0x400d399e, formatters from 0x400d3a52, enable nibbles 0x400d3b14. */
static const unsigned char lab_multi[3][6] = {"DEC", "SUS", "REL"}, lab_stock[3][6] = {"HOLD", "REL", "XVOL"};
static const unsigned lab_at[3] = {0x400d39a4u, 0x400d39aau, 0x400d39bcu};
static const unsigned fmt_at[3] = {0x400d3a56u, 0x400d3a5au, 0x400d3a66u};
static const unsigned fmt_stock[3] = {0x4003b3d0u, 0x4003b408u, 0x4003b484u};
unsigned char mu_amp_shown = 0;
void mu_amp_ui(void) {
    unsigned t = U8(0x100b14ccu) & 7u;
    unsigned part = U32(0x46c82456u) + 6322u * (U8(0x100b14cfu) & 3u);
    unsigned m = !U32(0x80000012u) && U8(part + 0x8eda2u + t) == 5u;
    if (m == mu_amp_shown) return;
    mu_amp_shown = (unsigned char)m;
    for (unsigned i = 0; i < 3; i++) {
        const unsigned char *l = m ? lab_multi[i] : lab_stock[i];
        for (unsigned k = 0; k < 6; k++) U8(lab_at[i] + k) = l[k];
        unsigned f = m ? 0u : fmt_stock[i];
        U8(fmt_at[i]) = (unsigned char)(f >> 24); U8(fmt_at[i] + 1u) = (unsigned char)(f >> 16);
        U8(fmt_at[i] + 2u) = (unsigned char)(f >> 8); U8(fmt_at[i] + 3u) = (unsigned char)f;
    }
    U8(0x400d3b17u) = m ? 0x11u : 0x81u;          /* p5's nibble: 1 drawn, 8 (stock) scene-only */
    /* p5's knob handler (E+0x12a, E = 0x400d3988): stock's XVOL handler 0x40032ba4 does not step 0-127;
     * ATK's 0x40032814 does */
    unsigned h = m ? 0x40032814u : 0x40032ba4u;
    U8(0x400d3ac6u) = (unsigned char)(h >> 24); U8(0x400d3ac7u) = (unsigned char)(h >> 16);
    U8(0x400d3ac8u) = (unsigned char)(h >> 8); U8(0x400d3ac9u) = (unsigned char)h;
    /* p5's widget (E+0xfa): stock's XVOL dial 0x400475f8 (striped) on stock tracks, the plain knob
     * (0: the default) on MULTI */
    unsigned w = m ? 0u : 0x400475f8u;
    U8(0x400d3a96u) = (unsigned char)(w >> 24); U8(0x400d3a97u) = (unsigned char)(w >> 16);
    U8(0x400d3a98u) = (unsigned char)(w >> 8); U8(0x400d3a99u) = (unsigned char)w;
}

/* After the frame builder's copy (0x4000cb9a): a MULTI track's DSP record shows the DSP no envelope of
 * its own and full XVOL (the slot is MULTI's REL). rec = 0x80000110 + ping + 0x40 t: +0 ATK, +2 HOLD,
 * +4 REL, +0xa XVOL, value << 8. */
void mu_dsp_amp(unsigned ping) {
    unsigned part = U32(0x46c82456u) + 6322u * (U8(0x100b14cfu) & 3u);
    for (unsigned t = 0; t < 8; t++) {
        if (U8(part + 0x8eda2u + t) != 5u) continue;
        volatile unsigned short *r = (volatile unsigned short *)(0x80000110u + ping + 0x40u * t);
        r[0] = 0; r[1] = 127u << 8; r[2] = 127u << 8; r[5] = 127u << 8;
    }
}

/* At the start of track t's render (mu_call, MULTI tracks): voices whose envelope ended stop (the
 * primary through stock's stop, as its sample's end does), and the release a let-go track owes is
 * posted once nothing sounds (mu_release_key leaves it in mu_relpend). */
extern unsigned char mu_relpend[8];
void mu_env_pre(unsigned t) {
    unsigned any = 0;
    volatile unsigned char *p = (volatile unsigned char *)(0x800049d8u + 168u * t);
    if (*p) {
        if (mu_env_off(t, 0)) ((void (*)(unsigned))0x40006820u)(t);
        else any = 1;
    }
    for (unsigned e = 0; e < 7; e++) {
        volatile unsigned char *x = &mu_extra_voices[(t * 7u + e) * 168u];
        if (!*x) continue;
        if (mu_env_off(t, e + 1u)) *x = 0; else any = 1;
    }
    if (!any && mu_relpend[t]) {
        mu_relpend[t] = 0;
        U32(0x46c80354u + 4u * t) |= 0x40u;
    }
}
