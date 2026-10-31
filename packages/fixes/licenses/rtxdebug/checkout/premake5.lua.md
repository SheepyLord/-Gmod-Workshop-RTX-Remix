# premake5.lua

Standalone VS2022 project generator. Pass --gmcommon=<pinned garrysmod_common checkout> and optionally
--remixinclude=<fork>/public/include. Premake 5.0.0-beta2 supports the pinned common generator;
5.0.0 removes its legacy flags API. It writes the solution/projects into the working directory.
Build in an isolated worktree, and override MSBuild IntDir with obj\Release\ when the path contains
an exclamation mark. See README for the parent-workspace build. Exit follows Premake's result.
