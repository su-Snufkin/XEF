// 64-bit (8B/4H/2S) NEON compares against zero and between registers, read back as one u64 (as hashbrown's Group)
#include <arm_neon.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static uint64_t u64of(uint8x8_t v) { return vget_lane_u64(vreinterpret_u64_u8(v), 0); }

int main(void) {
    const uint8_t pats[][8] = {
        {0xff, 0xff, 0xff, 0xff, 0x12, 0x80, 0x7f, 0x00}, {0x01, 0x80, 0xff, 0x00, 0xff, 0xff, 0xff, 0xff},
        {0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80}, {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01},
        {0x33, 0x44, 0x55, 0x66, 0xff, 0xff, 0xff, 0xff}, {0xfe, 0x01, 0x7e, 0x81, 0x00, 0x7f, 0x80, 0xff}};
    for (unsigned k = 0; k < sizeof pats / sizeof *pats; k++) {
        uint8x8_t v = vld1_u8(pats[k]);
        int8x8_t s = vreinterpret_s8_u8(v);
        uint64_t lt = u64of(vcltz_s8(s)), le = u64of(vclez_s8(s)), gt = u64of(vcgtz_s8(s)), ge = u64of(vcgez_s8(s));
        uint64_t eqz = u64of(vceqz_u8(v)), eq = u64of(vceq_u8(v, vdup_n_u8(0xff))), tst = u64of(vtst_u8(v, vdup_n_u8(0x80)));
        uint64_t lt2 = u64of(vclt_s8(s, vdup_n_s8(0x10))), hi = u64of(vcgt_u8(v, vdup_n_u8(0x7f)));
        uint64_t m = lt & 0x8080808080808080ull;
        printf("%u: ltz %016llx lez %016llx gtz %016llx gez %016llx eqz %016llx eqff %016llx tst %016llx lt %016llx hi %016llx first %d\n",
               k, (unsigned long long)lt, (unsigned long long)le, (unsigned long long)gt, (unsigned long long)ge,
               (unsigned long long)eqz, (unsigned long long)eq, (unsigned long long)tst, (unsigned long long)lt2,
               (unsigned long long)hi, m ? __builtin_ctzll(m) / 8 : -1);
        int16x4_t h = vreinterpret_s16_u8(v);
        int32x2_t w = vreinterpret_s32_u8(v);
        printf("   4h ltz %016llx eqz %016llx  2s ltz %016llx gez %016llx\n",
               (unsigned long long)vget_lane_u64(vreinterpret_u64_u16(vcltz_s16(h)), 0),
               (unsigned long long)vget_lane_u64(vreinterpret_u64_u16(vceqz_s16(h)), 0),
               (unsigned long long)vget_lane_u64(vreinterpret_u64_u32(vcltz_s32(w)), 0),
               (unsigned long long)vget_lane_u64(vreinterpret_u64_u32(vcgez_s32(w)), 0));
    }
    return 0;
}
