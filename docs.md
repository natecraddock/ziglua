# ziglua Documentation

*To avoid a duplication of efforts, ziglua does not contain full documentation on the Lua C API. Please refer to [the Lua C API Documentation](https://www.lua.org/manual/5.4/manual.html#4) for full details.*

This documentation provides

* An overview of ziglua's structure
* Safety considerations
* API Differences
* Example code

## API Differences

The major differences between the C and Zig Lua APIs are described below. This includes identifier renaming and omissions.

### `lua_tostring` and `lua_tolstring`

These functions have been combined into `Lua.toString()`. The function `lua_tostring` is a macro around `lua_tolstring` and does not return the length of the string.

The length of the returned string is almost always needed, so `Lua.toString() returns a zero-terminated Zig slice of the bytes with the correct length.
