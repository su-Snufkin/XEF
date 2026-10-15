#include <stdio.h>
#include <math.h>
#include <time.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <stdint.h>
#include <ctype.h>
#include <wchar.h>
int main(void){
  printf("%.6f %.6f %.6f %.6f\n",sin(1.0),cos(1.0),pow(2.5,3.1),log(10.0));
  printf("%f %f %f\n",floor(-2.5),ceil(-2.5),fmod(10.5,3));
  printf("%ld %lld %d\n",strtol("-123",0,10),strtoll("ffff",0,16),atoi("77"));
  printf("%d %d\n",isalpha('a'),isdigit('x')); printf("%c%c\n",toupper('q'),tolower('Q'));
  time_t t=86400*365; struct tm *g=gmtime(&t); char b[64]; strftime(b,64,"%Y-%m-%d %H:%M:%S",g); printf("%s\n",b);
  struct tm tm2; memset(&tm2,0,sizeof tm2); strptime("2024-03-05 10:20:30","%Y-%m-%d %H:%M:%S",&tm2); printf("%d %d\n",tm2.tm_year,tm2.tm_mon);
  printf("%lld %llu %d\n",LLONG_MIN,ULLONG_MAX,INT_MAX);
  printf("%g %g %g\n",1e100,1.5e-7,123456789.0); printf("%e|%10.3f|%-10.1f|\n",12345.678,3.14159,2.0);
  printf("%s\n",isnan(NAN)?"nan":"num"); printf("%f\n",INFINITY); 
  srand(5); int r=rand(); printf("%d\n",r>=0);
  printf("%zu %zu\n",sizeof(long),sizeof(wchar_t)); wchar_t ws[8]=L"hi"; printf("%zu\n",wcslen(ws));
  uint64_t x=0x123456789abcdef0ULL; printf("%llx %d\n",(unsigned long long)__builtin_bswap64(x),__builtin_popcountll(x));
  __int128 big=(__int128)x*x; printf("%llx\n",(unsigned long long)(big>>64)); long double ld=1.5L; printf("%Lf\n",ld*2);
  char *e; double dd=strtod("3.25abc",&e); printf("%f %s\n",dd,e);
  printf("%d\n", abs(-5)); div_t dv=div(17,5); printf("%d %d\n",dv.quot,dv.rem);
  return 0; }
