extern void zlua_assert(int e);

#define luai_apicheck(l,e) zlua_assert(e)

