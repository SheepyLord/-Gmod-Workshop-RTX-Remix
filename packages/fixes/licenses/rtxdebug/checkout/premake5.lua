PROJECT_GENERATOR_VERSION = 3

newoption({
    trigger = "gmcommon",
    description = "Path to garrysmod_common",
    value = "../garrysmod_common"
})
newoption({
    trigger = "remixinclude",
    description = "Path to the fork's public/include folder",
    value = "../../public/include"
})

local gmcommon = assert(_OPTIONS.gmcommon or os.getenv("GARRYSMOD_COMMON"),
    "pass --gmcommon=<path to garrysmod_common>")
include(gmcommon)

CreateWorkspace({name = "RTXDebugModule", abi_compatible = false, path = ""})
dofile("premake_project.lua")
CreateRTXDebugProject("source", _OPTIONS.remixinclude or "../../public/include")
