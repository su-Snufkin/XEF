#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <zlib.h>
#include <sqlite3.h>
#include <iconv.h>
#include <libxml/parser.h>
#include <libxml/tree.h>
#include <curses.h>
static int cb(void *u, int n, char **v, char **c) { printf("row: %s=%s %s=%s\n", c[0], v[0], c[1], v[1]); return 0; }
int main(void) {
  const char *src = "hello hello hello hello hello zlib"; uLong sl = strlen(src); uLongf dl = compressBound(sl); unsigned char *z = malloc(dl);
  compress(z, &dl, (const Bytef *)src, sl); char out[128] = {0}; uLongf ol = sizeof out; uncompress((Bytef *)out, &ol, z, dl);
  printf("zlib %lu->%lu back=%s crc=%lx\n", sl, dl < sl, out, crc32(0, (const Bytef *)src, sl));
  sqlite3 *db; sqlite3_open(":memory:", &db); sqlite3_exec(db, "create table t(a int, b text); insert into t values (1,'x'),(2,'y');", 0, 0, 0);
  sqlite3_exec(db, "select a,b from t order by a", cb, 0, 0); sqlite3_close(db);
  iconv_t cd = iconv_open("UTF-16LE", "UTF-8"); char in[] = "A\xC3\xA9"; char ob[16]; char *ip = in, *op = ob; size_t il = 3, ol2 = 16; iconv(cd, &ip, &il, &op, &ol2); printf("iconv bytes=%zu\n", 16 - ol2); iconv_close(cd);
  xmlDocPtr d = xmlReadMemory("<r><a x='1'>t</a></r>", 21, NULL, NULL, 0); xmlNodePtr n = xmlDocGetRootElement(d)->children; printf("xml %s %s\n", n->name, xmlNodeGetContent(n)); xmlFreeDoc(d);
  return 0; }
