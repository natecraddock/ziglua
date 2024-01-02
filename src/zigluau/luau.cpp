#include "Luau/Common.h"

#include <cstdio>
#include <cstdlib>

static int assertionHandler(const char* expr, const char* file, int line, const char* function)
{
    printf("%s(%d): ASSERTION FAILED: %s\n", file, line, expr);
    return 1;
}

extern "C" void zig_registerAssertionHandler() {
    Luau::assertHandler() = assertionHandler;
}

extern "C" void zig_luau_free(void *ptr) {
    free(ptr);
}
