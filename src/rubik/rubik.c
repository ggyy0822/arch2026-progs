#include "rubik.h"

#include <stdint.h>

enum { PERM_COUNT = 5040, ORIENT_COUNT = 729, MAX_DEPTH = 11 };

extern const uint16_t c_perm[3 * PERM_COUNT];
extern const uint16_t c_orient[3 * ORIENT_COUNT];
extern const uint8_t c_pd[PERM_COUNT], c_od[ORIENT_COUNT];

struct frame {
    uint16_t p, o, child_p, child_o;
    uint8_t next_move, previous_face;
};

static const uint16_t *const perm_rows[3] = {c_perm, c_perm + PERM_COUNT,
                                             c_perm + 2 * PERM_COUNT};
static const uint16_t *const orient_rows[3] = {
    c_orient, c_orient + ORIENT_COUNT, c_orient + 2 * ORIENT_COUNT};
static const uint8_t face_of[9] = {0, 0, 0, 1, 1, 1, 2, 2, 2};
static const uint8_t first_turn[9] = {1, 0, 0, 1, 0, 0, 1, 0, 0};
static const char *const move_name[9] = {"R",  "R2", "R'", "B", "B2",
                                         "B'", "D",  "D2", "D'"};

static unsigned estimate(unsigned p, unsigned o)
{
    return c_pd[p] > c_od[o] ? c_pd[p] : c_od[o];
}

static int parse_state(const char *s, unsigned *prank, unsigned *orank)
{
    uint8_t p[7];
    unsigned seen = 0, sum = 0;
    for (unsigned i = 0; i < 7; ++i) {
        unsigned digit = (unsigned) (uint8_t) s[i] - '1';
        if (digit >= 7)
            return 0;
        unsigned bit = 1u << digit;
        if (seen & bit)
            return 0;
        seen |= bit;
        p[i] = (uint8_t) digit;
    }
    unsigned o = 0;
    for (unsigned i = 0; i < 7; ++i) {
        unsigned digit = (unsigned) (uint8_t) s[i + 7] - '1';
        if (digit >= 3)
            return 0;
        sum += digit;
        if (i < 6)
            o = (o << 1) + o + digit;
    }
    if (s[14] != 0)
        return 0;
    while (sum >= 3)
        sum -= 3;
    if (sum != 0)
        return 0;
    unsigned rank = 0;
    for (unsigned i = 0; i < 7; ++i) {
        unsigned smaller = 0;
        for (unsigned j = i + 1; j < 7; ++j)
            smaller += p[j] < p[i];
        rank = rank * (7 - i) + smaller;
    }
    *prank = rank;
    *orank = o;
    return 1;
}

static void init_frame(struct frame *f, unsigned p, unsigned o, unsigned face)
{
    f->p = f->child_p = (uint16_t) p;
    f->o = f->child_o = (uint16_t) o;
    f->next_move = 0;
    f->previous_face = (uint8_t) face;
}

static int search(unsigned p, unsigned o, uint8_t path[MAX_DEPTH])
{
    struct frame frames[MAX_DEPTH + 1];
    for (unsigned bound = estimate(p, o); bound <= MAX_DEPTH; ++bound) {
        int depth = 0;
        init_frame(&frames[0], p, o, 3);
        while (depth >= 0) {
            struct frame *f = &frames[depth];
            if (f->p == 0 && f->o == 0)
                return depth;
            if ((unsigned) depth == bound || f->next_move == 9) {
                depth--;
                continue;
            }
            unsigned move = f->next_move++;
            unsigned face = face_of[move];
            if (face == f->previous_face)
                continue;
            if (first_turn[move]) {
                f->child_p = f->p;
                f->child_o = f->o;
            }
            f->child_p = perm_rows[face][f->child_p];
            f->child_o = orient_rows[face][f->child_o];
            if ((unsigned) depth + 1 + estimate(f->child_p, f->child_o) > bound)
                continue;
            path[depth] = (uint8_t) move;
            init_frame(&frames[depth + 1], f->child_p, f->child_o, face);
            depth++;
        }
    }
    return -1;
}

int rubik_solve(const char *state, char *out, size_t cap)
{
    unsigned p, o;
    if (!parse_state(state, &p, &o))
        return -1;
    uint8_t path[MAX_DEPTH];
    int length = search(p, o, path);
    if (length < 0)
        return -1;
    size_t needed = 1;
    for (int i = 0; i < length; ++i) {
        unsigned move = path[i];
        needed += 1 + (move_name[move][1] != 0);
        if (i != 0)
            needed++;
    }
    if (cap < needed) {
        if (cap != 0)
            out[0] = '\0';
        return -2;
    }
    size_t pos = 0;
    for (int i = 0; i < length; ++i) {
        if (i != 0)
            out[pos++] = ' ';
        const char *name = move_name[path[i]];
        out[pos++] = name[0];
        if (name[1] != 0)
            out[pos++] = name[1];
    }
    out[pos] = '\0';
    return length;
}
