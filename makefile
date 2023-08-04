test:
	zig build test --summary failures -Dversion=lua_51
	zig build test --summary failures -Dversion=lua_52
	zig build test --summary failures -Dversion=lua_53
	zig build test --summary failures -Dversion=lua_54

	zig build install-example-interpreter
	zig build install-example-zig-function
