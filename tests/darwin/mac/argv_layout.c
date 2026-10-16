// argv/envp strings are contiguous and ascending, as XNU lays them out (libuv's process title relies on it).
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv, char **envp) {
  int ok = 1;
  for (int i = 0; i + 1 < argc; i++) ok &= argv[i + 1] == argv[i] + strlen(argv[i]) + 1;
  printf("argc=%d argv contiguous=%d\n", argc, ok);
  printf("envp after argv=%d\n", envp[0] == argv[argc - 1] + strlen(argv[argc - 1]) + 1);
  int eok = 1;
  for (int i = 0; envp[i] && envp[i + 1]; i++) eok &= envp[i + 1] == envp[i] + strlen(envp[i]) + 1;
  printf("envp contiguous=%d\n", eok);
  char **p = envp; while (*p) p++;
  char **apple = p + 1;
  printf("apple[0] executable_path=%d\n", strncmp(apple[0], "executable_path=", 16) == 0);
  return 0;
}
