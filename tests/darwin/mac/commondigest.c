// CommonDigest: one-shot and streaming MD5/SHA1/SHA224/SHA256/SHA384/SHA512, odd chunk sizes across block boundaries.
#include <CommonCrypto/CommonDigest.h>
#include <stdio.h>
#include <string.h>
static void hex(const char *tag, const unsigned char *d, int n) { printf("%s ", tag); for (int i = 0; i < n; i++) printf("%02x", d[i]); printf("\n"); }
int main(void) {
  unsigned char md[64]; const char *abc = "abc";
  hex("md5", CC_MD5(abc, 3, md), 16); hex("sha1", CC_SHA1(abc, 3, md), 20); hex("sha224", CC_SHA224(abc, 3, md), 28);
  hex("sha256", CC_SHA256(abc, 3, md), 32); hex("sha384", CC_SHA384(abc, 3, md), 48); hex("sha512", CC_SHA512(abc, 3, md), 64);
  hex("sha256-empty", CC_SHA256("", 0, md), 32);
  unsigned char big[1000]; for (int i = 0; i < 1000; i++) big[i] = (unsigned char)(i * 7 + 3);
  CC_SHA256_CTX c; CC_SHA256_Init(&c); for (int off = 0, k = 1; off < 1000; off += k, k = k * 3 % 97 + 1) CC_SHA256_Update(&c, big + off, (off + k > 1000 ? 1000 - off : k));
  CC_SHA256_Final(md, &c); hex("sha256-chunks", md, 32); hex("sha256-whole", CC_SHA256(big, 1000, md), 32);
  CC_SHA512_CTX e; CC_SHA512_Init(&e); CC_SHA512_Update(&e, big, 111); CC_SHA512_Update(&e, big + 111, 889); CC_SHA512_Final(md, &e); hex("sha512-2", md, 64);
  CC_MD5_CTX m; CC_MD5_Init(&m); for (int i = 0; i < 1000; i++) CC_MD5_Update(&m, big + i, 1); CC_MD5_Final(md, &m); hex("md5-bytes", md, 16);
  CC_SHA1_CTX s; CC_SHA1_Init(&s); CC_SHA1_Update(&s, big, 64); CC_SHA1_Update(&s, big + 64, 56); CC_SHA1_Final(md, &s); hex("sha1-120", md, 20);
  printf("ctx sizes %zu %zu %zu %zu\n", sizeof(CC_MD5_CTX), sizeof(CC_SHA1_CTX), sizeof(CC_SHA256_CTX), sizeof(CC_SHA512_CTX));
  return 0;
}
