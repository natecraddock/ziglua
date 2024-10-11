# Ziglua Documentation

*To avoid a duplication of efforts, Ziglua does not contain full documentation on the Lua C API. Please refer to the Lua C API Documentation for full details.*

This documentation provides

* `build.zig` documentation
* An overview of Ziglua's structure and changes from the C API
* Safety considerations

Documentation on each individual function is found in the source code.

## Moving from the C API to Zig

While efforts have been made to keep the Ziglua API similar to the C API, many changes have been made including:

* Renaming or omitting functions
* Modifying parameters (names and types) and return values
* Additional helper functions have been added

With this in mind, here are some general guidelines to help when moving from the C to Zig APIs

### Naming

In general, most functions are named similarly to the original C functions. The `lua_` and `luaL_` prefixes have been removed, because all functions are in the `Lua` struct namespace. Additionally, all functions are in `camelCase` to match Zig naming style.

In the few cases when the [auxiliary library](https://www.lua.org/manual/5.4/manual.html#5) functions have the same name as a normal C API function, the auxlib function is given a more descriptive name.

For example, the functions `lua_newstate` and `luaL_newstate` are translated to `Lua.newState` and `Lua.newStateLibc` respectively.

Because Zig best practice is to communicate intent precisely, some abbreviations are expanded to make names more clear, like renaming `pcall` to `protectedCall`.

### Lua Initialization

In the C API, there are two functions provided to initialize the main Lua state: `lua_newstate` and `luaL_newstate`. The former requires passing an allocator function to be used by Lua for all memory allocations, while the latter uses the default libc allocator.

Ziglua provides a third option with the `Lua.init(Allocator)` function, which accepts a Zig allocator. All three functions are available depending on your needs, but most likely you will want to use the `Lua.init(Allocator)` function. If you have special requirements for allocation, then `Lua.newState` would be useful. `Lua.newStateLibc` is available if you wish to use the default libc allocator.

## Safety

The Ziglua API aims to be safer than the traditional C API. That said, the way that Lua operates means that Zig cannot protect you from all errors due to the use of `longjmp` in C.

Here is a list of the features Ziglua uses for greater safety:

### Errors

Many functions now return Zig errors rather than an integer code. The Zig compiler will then ensure that the error is handled, or ignored. There are specific error types like `ziglua.error.LuaRuntime` for errors that have a specific meaning.

On the other hand, many functions either succeed or return an error. Rather than returning a boolean success code, these functions return the generic `ziglua.Error.LuaError` to indicate failure. The type of failure can be determined in the context of the function called.

### Booleans

Functions that return or accept C boolean integers now use the Zig `bool` type.

### Slices

In cases where C functions use separate pointers and ints to keep track of strings, Ziglua uses a Zig slice to keep the data together.

The slices are typed to indicate the contents (zero-terminated, raw bytes, etc.)

### Enums

Ziglua uses enums instead of integer codes or strings to prevent passing an invalid value to a function.

### Optionals

Any value that can be `NULL` in the C API is marked as optional in Zig to enforce null checking.

## API Differences

The major differences between the C and Zig Lua APIs are described below. This includes identifier renaming and omissions.

### Continuations

All functions and types that deal with continuations have been renamed. For example, `KFunction` is now `LuaContFn`, and `lua_yieldk` is now `yieldCont`. One exception is the `KContext` type which has been simply renamed to `Context`. This is only ever used in continuation functions, so the `K` doesn't add much detail.

In general, just replace the "k" with the word "cont". This is just to make the API more clear and Zig-like.

### `lua_error` and `luaL_error`

Because `error` is a reserved word in Zig, these functions have been renamed to `raiseError` and `raiseErrorStr` respectively.

### `string` vs `lstring`

The "string" variant functions vs the "lstring" functions only differ by returning the length of the string. In Ziglua, the lstring functions are all named "bytes" instead. For example, `lua_tolstring` is `Lua.toBytes`. This is because these functions are typically used in cases when the string _might_ contain zeros before the null-terminating zero.

The "string" variant functions are safe to use when the string is known to be null terminated without inner zeros.

The length of the returned string is almost always needed, so `Lua.toString() returns a zero-terminated Zig slice of the bytes with the correct length.

### `lua_pushvfstring`

This function has been omitted because Zig does not have a va_list type, and `Lua.pushFString` works well enough for string formatting if variadic args are really needed.

### `lua_tointegerx` and `lua_tonumberx`

Both of these functions accept an `isnum` return parameter to indicate if the conversion to number was successful. In the Zig version, both functions return either the number, or an error indicating the conversion was unsuccessful, and the `isnum` parameter is omitted.

### `lua_pushliteral`

This is a macro for `lua_pushstring`, so use `Lua.pushString()` instead.

### `pcall`

Both `lua_pcall` and `lua_pcallk` are expanded to `protectedCall` and `protectedCallCont` for readability.
