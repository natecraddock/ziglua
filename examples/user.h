#define lua_lock(L) lua_zlock(L)
#define lua_unlock(L) lua_zunlock(L)

void lua_zlock(lua_State* L);
void lua_zunlock(lua_State* L);

