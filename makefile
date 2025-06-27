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

	zig build -Dlang=luajit

test_cross:
	zig build -Dlang=lua51 -Dtarget=aarch64-linux
	zig build -Dlang=lua51 -Dtarget=aarch64-linux-gnu
	zig build -Dlang=luajit -Dtarget=aarch64-linux
	zig build -Dlang=luajit -Dtarget=aarch64-linux-gnu

docs:
	zig build docs
