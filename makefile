.PHONY: test docs

test:
	zig build test --summary failures -Dlang=lua51
	zig build test --summary failures -Dlang=lua52
	zig build test --summary failures -Dlang=lua53
	zig build test --summary failures -Dlang=lua54
	zig build test --summary failures -Dlang=luau

	zig build install-example-interpreter
	zig build install-example-zig-function
	zig build -Dlang=luau install-example-luau-bytecode

docs:
	zig build docs -Dlang=lua51
	zig build docs -Dlang=lua52
	zig build docs -Dlang=lua53
	zig build docs -Dlang=lua54
	zig build docs -Dlang=luau
