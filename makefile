.PHONY: docs

test:
	zig build test --summary failures -Dversion=lua51
	zig build test --summary failures -Dversion=lua52
	zig build test --summary failures -Dversion=lua53
	zig build test --summary failures -Dversion=lua54
	zig build test --summary failures -Dversion=luau

	zig build install-example-interpreter
	zig build install-example-zig-function

docs:
	mkdir -p docs
	zig build-lib -femit-docs=docs/lua51 src/ziglua-5.1/lib.zig
	zig build-lib -femit-docs=docs/lua52 src/ziglua-5.2/lib.zig
	zig build-lib -femit-docs=docs/lua53 src/ziglua-5.3/lib.zig
	zig build-lib -femit-docs=docs/lua54 src/ziglua-5.4/lib.zig
	zig build-lib -femit-docs=docs/luau src/zigluau/lib.zig
