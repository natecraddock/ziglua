test:
	zig build test --summary failures -Dversion=lua_51
	zig build test --summary failures -Dversion=lua_52
	zig build test --summary failures -Dversion=lua_53
	zig build test --summary failures -Dversion=lua_54
