#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <unistd.h>
#include <pthread.h>
#include <errno.h>
static void* th(void*a){ *(int*)a=42; return a; }
int main(int argc,char**argv){
  printf("hello %d %s\n",argc,argv[1]);
  char*p=malloc(100); strcpy(p,"heap"); printf("%s %f\n",p,sqrt(2.0)); free(p);
  pthread_t t; int v=0; pthread_create(&t,0,th,&v); pthread_join(t,0); printf("thr %d\n",v);
  qsort(argv,argc,sizeof(char*),(int(*)(const void*,const void*))strcmp);
  struct timespec ts; clock_gettime(CLOCK_MONOTONIC,&ts);
  FILE*f=fopen("/etc/hosts","r"); printf("fopen %d\n",f!=0); if(f)fclose(f);
  printf("getenv HOME=%d pid>0=%d\n",getenv("HOME")!=0,getpid()>0);
  return 0; }
