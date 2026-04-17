.PHONY: test docs

# A subset of tests that are expected to work also on stable builds of zig
test:
	zig build test --summary failures -Dlang=lua51
	zig build test --summary failures -Dlang=lua52
	zig build test --summary failures -Dlang=lua53
	zig build test --summary failures -Dlang=lua54
	zig build test --summary failures -Dlang=lua55
	zig build test --summary failures -Dlang=luau
	zig build test --summary failures -Dlang=luajit

	zig build install-example-interpreter
	zig build install-example-zig-function
	zig build -Dlang=luau install-example-luau-bytecode

docs:
	zig build docs
