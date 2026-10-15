#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <dirent.h>
#include <errno.h>
int main(void){
  char path[]="/tmp/xefXXXXXX"; int fd=mkstemp(path); if(fd<0){perror("mkstemp");return 1;}
  const char*msg="line1\nline2 42 3.5\n"; write(fd,msg,strlen(msg)); close(fd);
  FILE*f=fopen(path,"r"); char l[64]; fgets(l,64,f); printf("[%s]",l);
  int a; double d; char w[16]; fscanf(f,"%15s %d %lf",w,&a,&d); printf("%s %d %.2f\n",w,a,d); fclose(f);
  struct stat st; stat(path,&st); printf("size=%lld mode=%o reg=%d\n",(long long)st.st_size,st.st_mode&0777,S_ISREG(st.st_mode));
  f=fopen(path,"a+"); fprintf(f,"more %s %5d|%-5d|%05.1f|%x|%c|%lu\n","x",7,8,2.5,255,'z',123456789012UL); fflush(f); fseek(f,0,SEEK_SET);
  while(fgets(l,64,f)) fputs(l,stdout); fclose(f);
  char buf[64]; snprintf(buf,sizeof buf,"%s-%d-%g",path+5,1,0.1); printf("%d\n",(int)strlen(buf));
  int x,y; sscanf("10 20","%d %d",&x,&y); printf("%d\n",x+y);
  unlink(path); printf("unlink then stat=%d errno=%d(%s)\n",stat(path,&st),errno,strerror(errno));
  DIR*d2=opendir("/"); int n=0; struct dirent*e; while((e=readdir(d2))) n++; closedir(d2); printf("root has entries: %d\n",n>=2);
  char cwd[256]; printf("cwd ok=%d\n",getcwd(cwd,256)!=0);
  printf("%s %s\n", strerror(ENOENT), strerror(EACCES));
  printf("fork-less ok\n"); return 0; }
