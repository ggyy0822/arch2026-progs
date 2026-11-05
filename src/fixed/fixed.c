#include "fixed.h"

uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    int passes = 0;
    while (b != 0) {
        uint32_t carry = (a & b) << 1;
        a ^= b;
        b = carry;
        passes++;
    }
    *n = passes;
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

uint32_t op3(uint32_t a, uint32_t b)
{
    return (a & b) + ((a ^ b) >> 1);
}

int32_t q_mul(int32_t a, int32_t b)
{
    uint32_t ma = a < 0 ? 0u - (uint32_t) a : (uint32_t) a;
    uint32_t mb = b < 0 ? 0u - (uint32_t) b : (uint32_t) b;
    uint32_t al = ma & 0xffffu, ah = ma >> 16;
    uint32_t bl = mb & 0xffffu, bh = mb >> 16;
    uint64_t product = (uint64_t) (al * bl);
    product += (uint64_t) (al * bh) << 16;
    product += (uint64_t) (ah * bl) << 16;
    product += (uint64_t) (ah * bh) << 32;
    if ((a < 0) != (b < 0))
        product = 0u - product;
    product += (uint64_t) 1 << 19;
    return (int32_t) (uint32_t) (product >> 20);
}
