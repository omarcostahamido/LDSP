#include "LDSP.h"

bool setup(LDSPcontext *context, void *userData) {
  printf("Hello world!\n");
  return true;
}

void render(LDSPcontext *context, void *userData) {}

void cleanup(LDSPcontext *context, void *userData) { printf("Goodbye!\n"); }
