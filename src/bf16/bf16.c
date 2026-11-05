#include "bf16.h"

uint16_t bf16_from_f32(uint32_t f32bits)
{
    uint32_t exponent = (f32bits >> 23) & 0xffu;
    if (exponent == 0xffu)
        return (uint16_t) (f32bits >> 16);
    uint32_t tie_bit = (f32bits >> 16) & 1u;
    return (uint16_t) ((f32bits + 0x7fffu + tie_bit) >> 16);
}

static uint32_t product_u8(uint32_t a, uint32_t b)
{
    uint32_t result = 0;
    while (b != 0) {
        if (b & 1u)
            result += a;
        a <<= 1;
        b >>= 1;
    }
    return result;
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint16_t sign = (uint16_t) ((a ^ b) & 0x8000u);
    uint16_t amag = (uint16_t) (a & 0x7fffu);
    uint16_t bmag = (uint16_t) (b & 0x7fffu);
    int ae = (a >> 7) & 0xff;
    int be = (b >> 7) & 0xff;

    if (ae == 0xff) {
        if (a & 0x7fu)
            return a;
        return bmag == 0 ? 0x7fc0u : (uint16_t) (sign | 0x7f80u);
    }
    if (be == 0xff) {
        if (b & 0x7fu)
            return b;
        return amag == 0 ? 0x7fc0u : (uint16_t) (sign | 0x7f80u);
    }
    if (amag == 0 || bmag == 0)
        return sign;

    uint32_t am = a & 0x7fu;
    uint32_t bm = b & 0x7fu;
    if (ae == 0) {
        ae = 1;
        while (am < 128u) {
            am <<= 1;
            ae--;
        }
    } else {
        am |= 128u;
    }
    if (be == 0) {
        be = 1;
        while (bm < 128u) {
            bm <<= 1;
            be--;
        }
    } else {
        bm |= 128u;
    }

    uint32_t product = product_u8(am, bm);
    int exponent = ae + be - 127;
    if (product >= 32768u) {
        product >>= 1;
        exponent++;
    }
    uint32_t mantissa = product >> 7;
    if (exponent >= 255)
        return (uint16_t) (sign | 0x7f80u);
    if (exponent <= 0) {
        if (exponent < -6)
            return sign;
        return (uint16_t) (sign | ((mantissa & 0x7fu) >> (1 - exponent)));
    }
    return (uint16_t) (sign | ((uint32_t) exponent << 7) | (mantissa & 0x7fu));
}

uint16_t bf16_sqrt(uint16_t a)
{
    int exponent = (a >> 7) & 0xff;
    uint32_t fraction = a & 0x7fu;
    if (exponent == 0xff) {
        if (fraction != 0)
            return a;
        return (a & 0x8000u) ? 0x7fc0u : a;
    }
    if ((a & 0x7fffu) == 0)
        return 0;
    if (a & 0x8000u)
        return 0x7fc0u;
    if (exponent == 0)
        return 0;

    int e = exponent - 127;
    uint32_t m = fraction | 128u;
    if (e & 1) {
        m <<= 1;
        e--;
    }
    uint32_t lo = 90, hi = 256;
    while (lo + 1 < hi) {
        uint32_t mid = (lo + hi) >> 1;
        if ((product_u8(mid, mid) >> 7) <= m)
            lo = mid;
        else
            hi = mid;
    }
    exponent = e / 2 + 127;
    if (lo >= 256) {
        lo >>= 1;
        exponent++;
    }
    if (exponent >= 255)
        return 0x7f80u;
    if (exponent <= 0)
        return 0;
    return (uint16_t) (((uint32_t) exponent << 7) | (lo & 0x7fu));
}
