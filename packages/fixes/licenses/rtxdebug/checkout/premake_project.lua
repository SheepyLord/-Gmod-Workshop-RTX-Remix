-- Included by the parent RTXFixesBinary workspace and by this module's own
-- premake5.lua. Keep the debug DLL independent of the shipping renderer DLL.
function CreateRTXDebugProject(sourcePath, remixIncludePath)
    filter({})
    CreateProject({
        serverside = false,
        name = "rtxdebug",
        source_path = sourcePath,
        manual_files = true
    })
        -- The Remix headers and the memory tools are 64-bit only. Without this
        -- the parent workspace's Win32 build fails on this project.
        removeplatforms({"x86"})

        IncludeLuaShared()
        IncludeScanning()
        IncludeDetouring()
        IncludeSDKCommon()
        IncludeSDKTier0()
        IncludeSDKTier1()
        IncludeSDKMathlib()
        IncludeHelpersExtended()

        cppdialect("C++17")
        exceptionhandling("On")
        includedirs({sourcePath, remixIncludePath})
        files({
            sourcePath .. "/*.cpp",
            sourcePath .. "/*.h",
            sourcePath .. "/engine/*.cpp",
            sourcePath .. "/engine/*.h",
            sourcePath .. "/lua_bridge/*.cpp",
            sourcePath .. "/lua_bridge/*.h",
            sourcePath .. "/memory/*.cpp",
            sourcePath .. "/memory/*.h",
            sourcePath .. "/remix/*.cpp",
            sourcePath .. "/remix/*.h",
            sourcePath .. "/transport/*.cpp",
            sourcePath .. "/transport/*.h",
            sourcePath .. "/detours/*.cpp",
            sourcePath .. "/detours/*.h"
        })
    filter({})
end
