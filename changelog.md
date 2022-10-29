# 0.1.0

This is the first official release of Ziglua supporting Lua 5.1, 5.2, 5.3, and 5.4 and targets Zig 0.10.0. Although incomplete, it is close enough to what I envision for the final library to share.

The API wrappers expose nearly every function and constant from the four Lua APIs, and each wrapper is well tested. I started development with Lua 5.4, and then worked my way backward for the other Lua versions, removing functions that are not supported by the older versions. This means that Lua 5.4 is the most complete of the four, though all should be ready to use.

There is still plenty of work for the future:
* Updating documentation comments. Because I copied the Lua 5.4 wrapper for the other three versions, the comments still point to Lua 5.4's reference manual.
* Updating function signatures. Most of the functions shouldn't change at this point, but there are a few that might as I use Ziglua more. For example, some functions return types that must be discarded with `_ = ` in Zig if the return value is not used. For some functions I have two versions, one that returns the value and another that doesn't. I still haven't decided if the two-function wrapper is the best way yet, but I want the API to be the best it can be.
* Updating the library as Zig inevitably introduces breaking changes going forward.
* Adding LuaJIT support.
* As Zig gains an official package manager, I want to delete the Lua source code from the repo and pull it at build time.

So feel free to use Ziglua at this point! It *will* change, but I will try to keep things documented here as best I can as the project moves forward.
