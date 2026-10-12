// Call-heavy and indirect-branch-heavy code: recursion, function pointers, a bytecode interpreter.
#include <stdint.h>
#include <stdio.h>
__attribute__((noinline)) static int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
typedef uint64_t (*fn)(uint64_t);
__attribute__((noinline)) static uint64_t f0(uint64_t x) { return x * 3 + 1; }
__attribute__((noinline)) static uint64_t f1(uint64_t x) { return x ^ (x >> 3); }
__attribute__((noinline)) static uint64_t f2(uint64_t x) { return x + 0x9e37; }
__attribute__((noinline)) static uint64_t f3(uint64_t x) { return (x << 1) | (x >> 63); }
enum { OP_PUSH, OP_ADD, OP_SUB, OP_MUL, OP_DUP, OP_SWAP, OP_JNZ, OP_DEC, OP_POP, OP_HALT };
static int64_t run(const int* code) {
    int64_t st[64]; int sp = 0; int pc = 0;
    for (;;) {
        switch (code[pc++]) {
        case OP_PUSH: st[sp++] = code[pc++]; break;
        case OP_ADD: sp--; st[sp - 1] += st[sp]; break;
        case OP_SUB: sp--; st[sp - 1] -= st[sp]; break;
        case OP_MUL: sp--; st[sp - 1] *= st[sp]; break;
        case OP_DUP: st[sp] = st[sp - 1]; sp++; break;
        case OP_SWAP: { int64_t t = st[sp - 1]; st[sp - 1] = st[sp - 2]; st[sp - 2] = t; break; }
        case OP_JNZ: { int t = code[pc++]; if (st[sp - 1]) pc = t; break; }
        case OP_DEC: st[sp - 1]--; break;
        case OP_POP: sp--; break;
        case OP_HALT: return st[0];
        }
    }
}
int main(void) {
    int r = fib(34);
    fn fs[4] = {f0, f1, f2, f3};
    uint64_t x = 1;
    for (uint32_t i = 0; i < 100000000; i++) x = fs[(i ^ (i >> 3)) & 3](x);
    // acc = 0; n = 30000000; loop: acc += n*3; n--; jnz loop
    int code[] = {OP_PUSH, 0, OP_PUSH, 30000000, /*4*/ OP_DUP, OP_PUSH, 3, OP_MUL, OP_SWAP, OP_POP,
                  OP_SWAP, OP_POP, OP_DUP, OP_DEC, OP_JNZ, 4, OP_HALT};
    // simpler well-formed program: sum loop
    int prog[] = {OP_PUSH, 0, OP_PUSH, 40000000, /*4*/ OP_DUP, OP_PUSH, 1, OP_MUL, OP_SWAP, OP_DUP, OP_JNZ, 12, /*12*/
                  OP_POP, OP_SWAP, OP_POP, OP_DEC, OP_JNZ, 4, OP_HALT};
    (void)code; (void)prog;
    int loop[] = {OP_PUSH, 50000000, /*2*/ OP_DEC, OP_DUP, OP_PUSH, 7, OP_MUL, OP_POP, OP_JNZ, 2, OP_HALT};
    int64_t v = run(loop);
    printf("%d %llx %lld\n", r, (unsigned long long)x, (long long)v);
    return 0;
}
