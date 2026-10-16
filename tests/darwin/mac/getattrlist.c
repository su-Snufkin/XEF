// getattrlist/fgetattrlist/getattrlistat subset: ATTR_CMN_NAME (attrreference), ATTR_CMN_OBJTYPE, volume capabilities
// query succeeds with FORMAT bits valid (whether the volume is case-sensitive differs between APFS and Linux).
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/attr.h>
#include <sys/vnode.h>
#include <unistd.h>
struct nameattr { uint32_t len; attrreference_t name; uint32_t type; } __attribute__((packed, aligned(4)));
int main(void) {
  char dir[] = "/tmp/xef_ga_XXXXXX"; mkdtemp(dir);
  char file[256]; snprintf(file, sizeof file, "%s/Some File.txt", dir); close(open(file, O_CREAT | O_WRONLY, 0644));
  char link[256]; snprintf(link, sizeof link, "%s/lnk", dir); symlink("Some File.txt", link);
  struct attrlist al = {ATTR_BIT_MAP_COUNT, 0, ATTR_CMN_NAME | ATTR_CMN_OBJTYPE, 0, 0, 0, 0};
  char buf[512]; struct nameattr *a = (struct nameattr *)buf;
  int r = getattrlist(file, &al, buf, sizeof buf, 0);
  printf("file r=%d len=%u name=%s namelen=%u type=%u\n", r, a->len, (char *)&a->name + a->name.attr_dataoffset, a->name.attr_length, a->type);
  r = getattrlist(link, &al, buf, sizeof buf, FSOPT_NOFOLLOW); printf("link nofollow r=%d type=%u\n", r, a->type);
  r = getattrlist(link, &al, buf, sizeof buf, 0); printf("link follow r=%d type=%u name=%s\n", r, a->type, (char *)&a->name + a->name.attr_dataoffset);
  int d = open(dir, O_RDONLY); r = fgetattrlist(d, &al, buf, sizeof buf, 0); printf("dir r=%d type=%u\n", r, a->type);
  r = getattrlistat(d, "Some File.txt", &al, buf, sizeof buf, 0); printf("at r=%d type=%u name=%s\n", r, a->type, (char *)&a->name + a->name.attr_dataoffset);
  struct attrlist vl = {ATTR_BIT_MAP_COUNT, 0, 0, ATTR_VOL_INFO | ATTR_VOL_CAPABILITIES, 0, 0, 0};
  struct { uint32_t len; vol_capabilities_attr_t c; } __attribute__((packed, aligned(4))) vb;
  r = fgetattrlist(d, &vl, &vb, sizeof vb, 0);
  printf("vol r=%d len=%u case_bits_valid=%d symlinks=%d\n", r, vb.len, (vb.c.valid[VOL_CAPABILITIES_FORMAT] & (VOL_CAP_FMT_CASE_SENSITIVE | VOL_CAP_FMT_CASE_PRESERVING)) != 0,
         !!(vb.c.capabilities[VOL_CAPABILITIES_FORMAT] & VOL_CAP_FMT_SYMBOLICLINKS));
  unlink(link); unlink(file); rmdir(dir);
  return 0;
}
