// Games for Windows - LIVE (xlive.dll) offline stubs matching GOG Fallout 3's stub DLL.
// Ordinal disassembly from GOG's 27 KB xlive.dll shows clean offline returns (0 or -1) with
// the exact stdcall argument counts so Fallout 3 1.7.0.3 stays on its local/offline path.
#include "shims.h"

static void xlive_ret0(CPU *c, int args) { RET(c, 0, args); }
static void xlive_fail(CPU *c, int args) { RET(c, 0xFFFFFFFFu, args); }

static void xlive_651(CPU *c) { xlive_fail(c, 4); }
static void xlive_652(CPU *c) { xlive_fail(c, 1); }
static void xlive_1082(CPU *c) { xlive_ret0(c, 1); }
static void xlive_1083(CPU *c) {
    uint32_t out = ARG(c, 1);
    if (out) P32(out, 0);
    RET(c, 0, 3);
}
static void xlive_5001(CPU *c) {
    uint32_t p = ARG(c, 0);
    if (p) P32(p + 0x14, 0);
    RET(c, 0xFFFFFFFFu, 1);
}
static void xlive_5002(CPU *c) { xlive_ret0(c, 0); }
static void xlive_5022(CPU *c) { xlive_fail(c, 1); }
static void xlive_5024(CPU *c) { xlive_fail(c, 1); }
static void xlive_5030(CPU *c) { xlive_ret0(c, 1); }
static void xlive_5215(CPU *c) { xlive_fail(c, 1); }
static void xlive_5250(CPU *c) { xlive_fail(c, 1); }
static void xlive_5251(CPU *c) { xlive_ret0(c, 1); }
static void xlive_5256(CPU *c) { xlive_fail(c, 5); }
static void xlive_5260(CPU *c) { xlive_fail(c, 2); }
static void xlive_5262(CPU *c) { xlive_fail(c, 1); }
static void xlive_5263(CPU *c) { xlive_fail(c, 3); }
static void xlive_5267(CPU *c) {
    uint32_t out = ARG(c, 2);
    if (out) P32(out, 0);
    RET(c, 0, 3);
}
static void xlive_5270(CPU *c) { xlive_fail(c, 2); }
static void xlive_5278(CPU *c) { xlive_fail(c, 3); }
static void xlive_5292(CPU *c) { xlive_fail(c, 4); }
static void xlive_5293(CPU *c) { xlive_fail(c, 5); }
static void xlive_5297(CPU *c) { xlive_fail(c, 2); }
static void xlive_5310(CPU *c) { xlive_ret0(c, 0); }
static void xlive_5355(CPU *c) { xlive_fail(c, 4); }
static void xlive_5356(CPU *c) { xlive_fail(c, 4); }
static void xlive_5360(CPU *c) { xlive_fail(c, 4); }
static void xlive_5361(CPU *c) { xlive_fail(c, 6); }
static void xlive_5365(CPU *c) { xlive_fail(c, 5); }

#define XL(ord) { "xlive#" #ord, xlive_##ord }
const ShimTable xlive_shims = { (const Shim[]){
    XL(651), XL(652), XL(1082), XL(1083), XL(5001), XL(5002), XL(5022), XL(5024),
    XL(5030), XL(5215), XL(5250), XL(5251), XL(5256), XL(5260), XL(5262), XL(5263),
    XL(5267), XL(5270), XL(5278), XL(5292), XL(5293), XL(5297), XL(5310), XL(5355),
    XL(5356), XL(5360), XL(5361), XL(5365),
}, 28 };
