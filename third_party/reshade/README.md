# third_party/reshade

ReShade's licence, for the ReShade binary the RTX package carries
([ADR 0028](../../docs/decisions/0028-reshade-in-rtx-sessions.md)). No ReShade code is vendored
here and nothing is built from it: [`tools/package_reshade.py`](../../tools/package_reshade.py.md)
takes `ReShade64.dll` unchanged from the official setup and copies this licence beside it.

| | |
|---|---|
| Project | ReShade by crosire (Patrick Mours), <https://reshade.me> |
| Source | <https://github.com/crosire/reshade>, tag `v6.8.0` |
| Licence | BSD 3-clause, [LICENSE.md](LICENSE.md): byte-identical to the tag's `LICENSE.md` |
| Fetched | 2026-10-29 through the GitHub API (`repos/crosire/reshade/contents/LICENSE.md?ref=v6.8.0`) |

| File | SHA-256 |
|---|---|
| `LICENSE.md` | `237DED5B8344F820113EFAB1E65E91E1F159D9202C5B4856606A0590D3FFDAB0` |
| `ReShade_Setup_6.8.0.exe` (reshade.me, not in git) | `207AEA16205FBF952BC8FE1879966672454CF04002E7AD34237C7990A5B3C0B4` |
| `ReShade64.dll` in that setup (not in git) | `B2945C29E7095491A901746B400E58DB9B1592AB092BACF2A888CE37F02D08DA` |

The setup is signed by "ReShade"; its DLL is version 6.8.0.2158. ReShade includes open-source
libraries (MinHook, Dear ImGui, ImGuiColorTextEdit, glad, UTF8-CPP, stb_image, DDS loading from
SOIL, fpng, SPIR-V headers, Vulkan Memory Allocator, OpenVR, OpenXR, Solarized, Fork Awesome, the
libjxl simple lossless encoder). Their licence texts are compiled into the DLL and shown on the
About page of its overlay (`source/runtime_gui.cpp`, `draw_gui_about`), so the unchanged DLL
carries them.
