#include "../source/render_policy.h"
#include <iostream>

int main() {
    using namespace RTXDebug::Policy;
    if (!CanConfigureRendering(true, false, true, true)) return 1;
    if (CanConfigureRendering(false, false, true, true) || CanConfigureRendering(true, true, true, true)
        || CanConfigureRendering(true, false, false, true) || CanConfigureRendering(true, false, true, false)) return 1;
    for (const auto key : {"rtx.pathMaxBounces", "rtx.showUI", "rtx.debugView.debugViewIdx"})
        if (!CanSetConfig(false, true, key)) return 1;
    for (const auto key : {"sv_cheats", "sv_allowcslua", "dxvk.foo", "rtx.", "rtx.foo;exec", "rtx.foo\nbar"})
        if (CanSetConfig(false, true, key)) return 1;
    if (CanSetConfig(false, false, "rtx.pathMaxBounces")) return 1;
    if (!CanSetConfig(true, false, "existing_single_player_option")) return 1;
    // The rendering-convar allowlist for Engine.GetConVar outside local single-player.
    for (const auto name : {"r_drawworld", "mat_queue_mode", "rtx_conf", "rtxSomething",
                            "cl_drawhud", "cl_drawviewmodel", "R_SHADOWS", "Mat_Fullbright"})
        if (!IsRenderingConVar(name)) return 1;
    for (const auto name : {"sv_cheats", "sv_allowcslua", "rcon_password", "cl_name", "net_graph",
                            "", "mat_x;quit", "mat x", "server_rtx", "notrtx"})
        if (IsRenderingConVar(name)) return 1;
    std::cout << "Rendering policy tests passed\n";
    return 0;
}
