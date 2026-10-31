# Garry's Mod Lua interface headers

Unmodified include/GarrysMod/Lua headers from
[danielga/garrysmod_common](https://github.com/danielga/garrysmod_common), commit
a854f237b79087826aa9a98a05de5e0d2b4502b6. The local source checkout was the fork's
garrysmod_common submodule; only the public Lua interface headers were copied. The BSD-3-Clause
notice is retained in [LICENSE](LICENSE) and must accompany binary redistribution.

These headers describe the engine's Lua interfaces and module entry ABI; no engine executable,
implementation, SDK import library or third-party module binary is vendored here. The loader/client
module calls the public Lua shared interface and uses the engine's client realm. Header changes
must remain a deliberate upstream update rather than local interface guessing.

| File under include/GarrysMod/Lua | SHA-256 |
|---|---|
| Interface.h | d4ed0c816703f31ce7c629405035ad2a1056d84094751eac7683493fc15a02b1 |
| LuaBase.h | 23736847cd1b80b0bed3e4f2cf0e8ba6262f1e06ef968e545a47f1b400514e03 |
| LuaConVars.h | 5b5d20e80c0af0ffbc0fdca119a432414b4ebdd6485a62781156c363022b99a1 |
| LuaGameCallback.h | 3d59417e8414415696231fa508cb211579995033340b83d64e7015f121a07e84 |
| LuaInterface.h | 07104450152653449d2a78ff5b44013352f1e2ccd8bc2ceeb83878a914173430 |
| LuaObject.h | b55a224240b98e9cce423d2eaa8f3076773d5b65527dacfc63f65dfdda81ad1a |
| LuaShared.h | f43b978607ff0f17057e949425833bbd0ce2bec4de5c5927191bfda0206ca99e |
| SourceCompat.h | ae50fc861511031e27c0908db2525810b6fd50d5836f6343e50ea76a3bf98f27 |
| Types.h | 6c891d60091526700e4df3e58dd3f9a6b90a90422200e50e03ab28806c2251bc |
| UserData.h | db17432eb6b51c8a0e45922de5153f86f065efa5e1c9a38b86dcc72204dca9c6 |
