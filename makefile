.PHONY: test docs

test_zig_nightly:
	# FIXME: reenable after resolution of https://codeberg.org/ziglang/translate-c/issues/282
	# zig build test --summary failures -Dlang=lua51
	zig build test --summary failures -Dlang=lua52
	zig build test --summary failures -Dlang=lua53
	zig build test --summary failures -Dlang=lua54
	zig build test --summary failures -Dlang=lua55
	zig build test --summary failures -Dlang=luau

	zig build install-example-interpreter
	zig build install-example-zig-function
	zig build -Dlang=luau install-example-luau-bytecode

	# FIXME: reenable after resolution of https://codeberg.org/ziglang/translate-c/issues/282
	# zig build -Dlang=luajit

# A subset of tests that are expected to work also on stable builds of zig
test_zig_stable:
	zig build test --summary failures -Dlang=lua51
	zig build test --summary failures -Dlang=lua52
	zig build test --summary failures -Dlang=lua53
	zig build test --summary failures -Dlang=lua54
	zig build test --summary failures -Dlang=lua55
	zig build test --summary failures -Dlang=luau

	zig build install-example-interpreter
	zig build install-example-zig-function
	zig build -Dlang=luau install-example-luau-bytecode

test_cross:
# TODO: audit this; is it expected that cross-compilation should be an issue?
# FIXME: reenable after resolution of https://codeberg.org/ziglang/translate-c/issues/282
# 	zig build -Dlang=lua51 -Dtarget=aarch64-linux
# 	zig build -Dlang=lua51 -Dtarget=aarch64-linux-gnu
# 	zig build -Dlang=luajit -Dtarget=aarch64-linux
# 	zig build -Dlang=luajit -Dtarget=aarch64-linux-gnu
# 
# 	zig build -Dlang=lua51 -Dtarget=x86_64-linux
# 	zig build -Dlang=lua51 -Dtarget=x86_64-linux-gnu
# 	zig build -Dlang=luajit -Dtarget=x86_64-linux
# 	zig build -Dlang=luajit -Dtarget=x86_64-linux-gnu
# 
# 	zig build -Dlang=luajit -Dtarget=aarch64-macos

docs:
	zig build docs
