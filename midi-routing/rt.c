/* MIDI ROUTING (OctaZach 207): MIDI tracks play audio tracks, set in NOTE SETUP.
 *
 * Per MIDI track (BRAIN PROJECT settings, so saved with the project):
 *   TRKS  the audio tracks it plays (bit k = T(k+1))
 *   MODE  0 ALL (every note on every routed track), 1 SPRD (one note a track)
 *   OUT   where its notes also go: 0 OFF, 1 DIN, 2 USB, 3 BOTH
 * A routed note plays as a CHROMATIC key's live note: the pitch as the track's PTCH lock (5 a semitone,
 * +-12) and, on a FLEX track whose sample is named with a note ("MELLO C3"), the nearest-note slot of
 * the run of slots around it that share its name as the sample lock (a multisample).
 *
 *   staged locks  0x46c7dfda + 32 t: +0 PTCH (raw 64 = 0), +31 the sample slot (0-based)
 *   START         0x40005030(t, 0x1d, 1, -1);  release  0x46c80354 + 4 t |= 0x40
 *   Part          [0x46c82456] + 6322 * part ([0x80000003]): machine +0x8eda2 + t (1 FLEX),
 *                 FLEX slot +0x8f04b + 5 t; MIDI SETUP bytes +586338 + 36 t + knob
 *   FLEX slot     settings record 0x100b14f0 + 0x448 s, the path at +0 */
#define U8(a) (*(volatile unsigned char *)(a))
#define U32(a) (*(volatile unsigned *)(a))
#define STAGED(t) (0x46c7dfdau + 32u * (t))
#define MAILBOX(t) (0x46c80354u + 4u * (t))
#define SETTINGS(s) (0x100b14f0u + 0x448u * (s))
#define PART() (U32(0x46c82456u) + 6322u * (U8(0x80000003u) & 3u))

extern int *const rt_v[24];             /* rt.s: the BRAIN value longs, TRKS M1-M8, MODE, OUT */
#define TRKS(m) (*rt_v[(m)])
#define MODE(m) (*rt_v[8 + (m)])
#define OUTV(m) (*rt_v[16 + (m)])
extern void rt_din(unsigned len, const unsigned char *m);
extern void rt_usb(unsigned len, const unsigned char *m);

unsigned char rt_note[8] = {255, 255, 255, 255, 255, 255, 255, 255};  /* the note audio track k plays */
unsigned char rt_chan[8], rt_src[8];
unsigned rt_age[8], rt_clock, rt_notes, rt_offs;
unsigned char rt_cx, rt_cy;                                            /* NOTE SETUP's cursor */

/* The note in a FLEX slot's file name: the last [A-G][#sb]?-?digit before the extension; -1 none.
 * *pre = the name's length before that note (the multisample's shared name), *nm its start. */
static int rt_name(unsigned slot, const volatile char **nm, int *pre) {
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
        int note = 12 * (oct + 1) + p;                                  /* C3 = 48 */
        if (note >= 0 && note < 128) { found = note; *pre = i; }
    }
    *nm = n;
    return found;
}

static int rt_same(unsigned a, unsigned b) {                             /* one multisample's names */
    const volatile char *na, *nb;
    int pa, pb;
    if (rt_name(a, &na, &pa) < 0 || rt_name(b, &nb, &pb) < 0 || pa != pb) return 0;
    for (int i = 0; i < pa; i++) if (na[i] != nb[i]) return 0;
    return 1;
}

static void rt_off(unsigned k) {
    U32(MAILBOX(k)) = U32(MAILBOX(k)) | 64u;
    rt_note[k] = 255;
    ++rt_offs;
}

/* MULTI (machine type 5, modules/multi): its own voices and multisample; weak, so this unit builds
 * without it. */
extern int mu_note(unsigned t, unsigned n, int on) __attribute__((weak));
extern int mu_is_ms(unsigned t) __attribute__((weak));
static int rt_multi(unsigned k) { return mu_note && U8(PART() + 0x8eda2u + k) == 5; }
static unsigned rt_mnote(unsigned k, unsigned p) { return mu_is_ms(k) ? p : p + 24u; }

/* The audio track's locks as the MIDI notes take them (OctaZach 214): every audio step that fires (a
 * trig, a trigless lock, a linked track's lock step) leaves its 32 lock bytes here (rt_seqtrig copies
 * the step's pending slot), and every MIDI note started on that track takes them -- until the next
 * audio step replaces them (Zach's choice b). PTCH (0) and the sample (31) stay the note's own. */
unsigned char rt_stk[8][32] = {[0 ... 7] = {[0 ... 31] = 0xff}};
void rt_locks(unsigned t) {
    if (t > 7) return;
    volatile unsigned char *st = (volatile unsigned char *)STAGED(t);
    for (unsigned k = 1; k < 31; k++)
        if (rt_stk[t][k] != 0xff && st[k] == 0xff) st[k] = rt_stk[t][k];
}

unsigned char rt_on[16 * 128], rt_osrc[16 * 128];   /* the tracks a (channel, note) plays, its source */
unsigned char rt_held[8];

static void rt_stop(unsigned k, unsigned idx) {      /* (channel, note) idx ends on track k */
    if (rt_multi(k)) {
        mu_note(k, rt_mnote(k, idx & 127u), 0);
        if (rt_held[k]) rt_held[k]--;
    } else if (rt_note[k] == (idx & 127u) && rt_chan[k] == idx >> 7) {
        rt_off(k);
        rt_held[k] = 0;
    }
    rt_on[idx] &= (unsigned char)~(1u << k);
}

static void rt_play(unsigned k, unsigned p, unsigned ch, unsigned src) {
    unsigned idx = ch * 128u + p;
    if (rt_multi(k)) {
        if (!mu_note(k, rt_mnote(k, p), 1)) return;
        if (rt_held[k] < 8) rt_held[k]++;
    } else {
        if (rt_note[k] != 255) rt_stop(k, rt_chan[k] * 128u + rt_note[k]);
        unsigned part = PART();
        int root = 60, slot = -1;
        if (U8(part + 0x8eda2u + k) == 1) {                                 /* FLEX: a multisample? */
            unsigned s = U8(part + 0x8f04bu + 5u * k);
            const volatile char *nm;
            int pre, r = s < 128 ? rt_name(s, &nm, &pre) : -1;
            if (r >= 0) {
                unsigned lo = s, hi = s;
                while (lo > 0 && rt_same(lo - 1, s)) lo--;
                while (hi < 127 && rt_same(hi + 1, s)) hi++;
                int bd = 1000;
                for (unsigned q = lo; q <= hi; q++) {
                    int rq = rt_name(q, &nm, &pre), d = (int)p - rq;
                    if (d < 0) d = -d;
                    if (d < bd) { bd = d; slot = (int)q; root = rq; }
                }
            }
        }
        int off = (int)p - root;
        if (off > 12) off = 12;
        if (off < -12) off = -12;
        U8(STAGED(k)) = (unsigned char)(64 + 5 * off);
        if (slot >= 0) U8(STAGED(k) + 31u) = (unsigned char)slot;
        rt_locks(k);
        ((int (*)(unsigned, unsigned, unsigned, int))0x40005030u)(k, 0x1du, 1u, -1);
        rt_note[k] = (unsigned char)p;
        rt_chan[k] = (unsigned char)ch;
        rt_held[k] = 1;
    }
    rt_src[k] = (unsigned char)src;
    rt_on[idx] |= (unsigned char)(1u << k);
    rt_osrc[idx] = (unsigned char)src;
    rt_age[k] = ++rt_clock;
    ++rt_notes;
}

/* the message's other outputs; 1 = kept from the stock sender */
static int rt_out(unsigned src, unsigned len, const unsigned char *m) {
    switch ((unsigned)OUTV(src) & 3u) {
    case 0: return 1;
    case 1: rt_din(len, m); return 1;
    case 2: rt_usb(len, m); return 1;
    default: return 0;
    }
}

/* m = (status, note, velocity); ret = the producer's return address (the sequencer's two note-on
 * sites and the live note-on); t = its MIDI track. 1: the stock sender doesn't send it. */
int rt_route(unsigned ret, unsigned t, unsigned len, const unsigned char *m) {
    if (len != 3) return 0;
    unsigned st = m[0] & 0xf0u, ch = m[0] & 15u, p = m[1] & 127u, idx = ch * 128u + p;
    if (st == 0x90u && m[2]) {
        if ((ret != 0x4009fbb2u && ret != 0x4009fcfau && ret != 0x4009ea9au) || t > 7) return 0;
        unsigned mask = (unsigned)TRKS(t) & 255u;
        if (!mask) return 0;
        if (rt_on[idx])                                                 /* the same note again */
            for (unsigned k = 0; k < 8; k++) if (rt_on[idx] >> k & 1) rt_stop(k, idx);
        if (MODE(t) == 0) {
            for (unsigned k = 0; k < 8; k++) if (mask >> k & 1) rt_play(k, p, ch, t);
        } else {                         /* SPRD: the first routed track with a free voice, else the oldest */
            unsigned best = 8, age = 0xffffffffu;
            for (unsigned k = 0; k < 8 && best == 8; k++)
                if ((mask >> k & 1) && rt_held[k] < (rt_multi(k) ? 8u : 1u)) best = k;
            if (best == 8)
                for (unsigned k = 0; k < 8; k++)
                    if ((mask >> k & 1) && rt_age[k] < age) { age = rt_age[k]; best = k; }
            if (best < 8) rt_play(best, p, ch, t);
        }
        return rt_out(t, len, m);
    }
    if (st == 0x80u || st == 0x90u) {
        unsigned on = rt_on[idx];
        if (!on) return 0;
        unsigned src = rt_osrc[idx];
        for (unsigned k = 0; k < 8; k++) if (on >> k & 1) rt_stop(k, idx);
        return rt_out(src, len, m);
    }
    return 0;
}

/* ---- NOTE SETUP: the routing map in the left box (window x = screen x - 7, y = 63 - screen row) */
#define FILL ((void (*)(void *, int, int, int, int, int))0x40012254u)
#define TEXT ((void (*)(const void *, void *, int, int, int, int, const char *, const char *, const char *))0x40013904u)
static void *rt_fb;
static void box(int x0, int top, int x1, int bot, int c) { FILL(rt_fb, x0 - 7, 63 - bot, x1 - 7, 63 - top, c); }
static void digit(int d, int x, int top, int inv) {
    static char s[2];
    s[0] = (char)('0' + d); s[1] = 0;
    TEXT((const void *)0x400ba876u, rt_fb, x - 7, 63 - (top + 4), 0, inv, s, "%s", s);
}

void rt_map(void *fb) {
    rt_fb = fb;
    unsigned cx = rt_cx & 7u, cy = rt_cy & 7u;
    box(17 + 5 * (int)cx, 12, 21 + 5 * (int)cx, 58, 1);                /* the cursor's MIDI track */
    for (unsigned j = 0; j < 8; j++) {
        int top = 12 + 6 * (int)j;
        if (j == cy) { box(11, top - 1, 15, top + 5, 1); digit((int)j + 1, 12, top, 1); }
        else digit((int)j + 1, 12, top, 0);
        for (unsigned i = 0; i < 8; i++) {
            int x = 18 + 5 * (int)i, y = top + 1, c = i == cx ? 0 : 1;
            if ((unsigned)TRKS(i) >> j & 1) box(x, y, x + 2, y + 2, c);
            else box(x + 1, y + 1, x + 1, y + 1, c);
        }
    }
}

/* key handlers' work: 1 = redraw */
int rt_key(unsigned key) {
    switch (key) {
    case 0x33: if (rt_cy > 0) rt_cy--; return 1;                       /* UP */
    case 0x20: if (rt_cy < 7) rt_cy++; return 1;                       /* DOWN */
    case 0x34: if (rt_cx > 0) rt_cx--; return 1;                       /* LEFT */
    case 0x21: if (rt_cx < 7) rt_cx++; return 1;                       /* RIGHT */
    }
    return 0;
}

/* YES: 1 = handled (a cell toggled); 0 = a CHAN/BANK/PROG/SBNK edit is waiting: the stock YES */
int rt_yes(void) {
    unsigned t = U8(0x80000000u) & 7u;
    unsigned a = PART() + 586338u + 36u * t;
    static const unsigned char ks[4] = {0, 1, 2, 4};
    for (unsigned i = 0; i < 4; i++)
        if ((U32(0x460d5cb4u + 4u * ks[i]) & 255u) != U8(a + ks[i])) return 0;
    unsigned cx = rt_cx & 7u, bit = 1u << (rt_cy & 7u);
    unsigned v = (unsigned)TRKS(cx) & 255u;
    if (v & bit) {                                                      /* unrouted: its notes end */
        unsigned k = rt_cy & 7u;
        for (unsigned idx = 0; idx < 16 * 128; idx++)
            if ((rt_on[idx] >> k & 1) && rt_osrc[idx] == cx) rt_stop(k, idx);
    }
    TRKS(cx) = (int)(v ^ bit);
    return 1;
}

/* D (MODE) and F (OUT) turned by n choices, for the cursor's MIDI track */
void rt_knob(unsigned knob, int n) {
    unsigned cx = rt_cx & 7u;
    if (knob == 3) { int v = MODE(cx) + n; MODE(cx) = v < 0 ? 0 : v > 1 ? 1 : v; }
    else { int v = OUTV(cx) + n; OUTV(cx) = v < 0 ? 0 : v > 3 ? 3 : v; }
}
int rt_value(unsigned knob) { return knob == 3 ? MODE(rt_cx & 7u) : OUTV(rt_cx & 7u); }
