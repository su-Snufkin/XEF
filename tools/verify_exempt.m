#import <objc/runtime.h>
#import <Cocoa/Cocoa.h>
int main(int argc,char**argv){ @autoreleasepool { [NSApplication sharedApplication];
 FILE *f=fopen(argv[1],"r"); char cls[64],sel[256]; int total=0,resp=0;
 while(fscanf(f,"%63s %255s",cls,sel)==2){ total++; const char *s=sel; BOOL cm=(s[0]=='+'); s++;
  Class c=objc_getClass(cls); BOOL r= cm ? [c respondsToSelector:sel_registerName(s)] : [c instancesRespondToSelector:sel_registerName(s)];
  if(r){ resp++; printf("MAC IMPLEMENTS %s %s\n",cls,sel);} }
 printf("checked %d, mac implements %d\n",total,resp); return 0;}}
