// This will be included when <assert.h> is included when LUA_USE_APICHECK is
// defined. Undefines any assert that may have already been defined, and then
// defines assert to be the zlua_assert function that shows a stack trace.
#undef assert
extern void zlua_assert(int e);
#define assert(e) zlua_assert((e) ? 1 : 0)
