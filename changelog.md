# 0.2.0
With a [Zig release last week](https://ziglang.org/download/0.11.0/release-notes.html), I figured this would be a good time to tag a release. Ziglua version 0.2.0 supports Zig 0.11.0. There have been several changes since the last release, including fixes from several contributors.

The biggest change in this release is officially supporting the new Zig package manager. Goodbye submodules! Instructions are in the readme. There have also been several updates to the Ziglua API. Here is a list of the most important changes:

* Documentation
  * All API functions now have doc comments
  * Auto-generated documentation for each commit. I still need a solution for docs for stable releases, but this is a good step
* Lua 5.4 is updated to 5.4.6
  * The new `closeThread` function is added ([86f234](https://github.com/natecraddock/ziglua/commit/86f234))
* Fixed `argCheck` raising an error on true rather than false ([00abb7](https://github.com/natecraddock/ziglua/commit/00abb7))
* The Lua 5.1 API received several fixes
    * Patched for CVE-2014-5461 ([518e26](https://github.com/natecraddock/ziglua/commit/518e26))
    * Added missing `cProtectedCall` ([2beee5](https://github.com/natecraddock/ziglua/commit/2beee5))
    * Added missing `equal` and `lessThan` comparison functions ([1bfbc5](https://github.com/natecraddock/ziglua/commit/1bfbc5))
    * Added `getFnEnvironment` and `setFnEnvironment` functions ([458ace](https://github.com/natecraddock/ziglua/commit/458ace))
    * Added `objectLen`, `checkInt`, and `optInt` functions ([53fc70](https://github.com/natecraddock/ziglua/commit/53fc70)) ([9b40b9](https://github.com/natecraddock/ziglua/commit/9b40b9))
    * `registerFns` is added ([837048](https://github.com/natecraddock/ziglua/commit/837048))
* Userdata updates
  * Previously the functions returned `*anyopaque` and required casting at the call site. With a type parameter the casting is done internally making the functions much easier to use. ([edf638](https://github.com/natecraddock/ziglua/commit/edf638))
  * Added userdata slice functions to allow allocating slices of custom userdata types. The C API for full userdata allows both single and many-item allocations. This expands the Zig interface to allow for slices of full userdata to be allocated. Also exposes the name of the userdata metatables as strings. ([334821](https://github.com/natecraddock/ziglua/commit/334821))
* `addLString` is renamed to `addBytes` ([5505a3](https://github.com/natecraddock/ziglua/commit/5505a3))
* `gSub` is renamed to `globalSub` ([b6dec0](https://github.com/natecraddock/ziglua/commit/b6dec0))
* All functions ending in Aux are renamed to be more clear. For example, `raiseErrorAux` is now `raiseErrorStr` to indicate that it raises an error with the given string. ([7070be](https://github.com/natecraddock/ziglua/commit/7070be))
* All Ex function variations are removed. Previously some functions were separated like `pushString` and `pushStringEx`, the former returning void and the latter returning a value. For simplicity, the Ex versions are removed and the function always returns a value. This can be ignored with `_ =` at the callsite. ([8cc749](https://github.com/natecraddock/ziglua/commit/8cc749))
* All X function variations are removed. Previously some functions were separated like `loadBuffer` and `loadBufferX`, the former with a default mode and the latter allowing the mode to be set with an argument. The new function always requires an argument. ([29f730](https://github.com/natecraddock/ziglua/commit/29f730))

Thanks to the following individuals who contributed code in this release!
* [DeanoC](https://github.com/DeanoC)
* [efjimm](https://github.com/efjimm)
* [hryx](https://github.com/hryx)
* [NTBBloodbath](https://github.com/NTBBloodbath)
* [ryleelyman](https://github.com/ryleelyman)

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
