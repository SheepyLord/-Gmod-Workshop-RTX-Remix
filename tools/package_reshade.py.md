# package_reshade.py

Builds the ReShade part of the RTX package
([ADR 0028](../docs/decisions/0028-reshade-in-rtx-sessions.md)): ReShade's 64-bit DLL, unchanged,
from the official setup, as a Vulkan layer that the loader enables in RTX sessions. The publisher
([`publish_workshop.py`](publish_workshop.py.md)) builds it as the `reshade` part of
[`workshop.json`](workshop.json), and [`package_workshop.py`](package_workshop.py.md) merges it into
the combined package.

```powershell
python tools\package_reshade.py --setup out\packages\reshade\ReShade_Setup_6.8.0.exe --out out\packages\reshade\part
python tools\package_reshade.py --setup <setup> --gma out\packages\reshade\reshade-6.8.0.gma --json
```

| Option | Meaning |
|---|---|
| `--setup FILE` | ReShade's official setup from <https://reshade.me>, `ReShade_Setup_<version>.exe`. Read as a ZIP; never run |
| `--version V` | The ReShade version it is (default `6.8.0`). Only pinned versions are accepted |
| `--out DIR` | Package folder to write |
| `--gma FILE` | `.gma` archive to write (gmapack, the setup's time as the archive time) |
| `--no-validate` | Skip the `nlctl manifest` check (done when a loader 0.5.0 or later is built) |
| `--force` | Replace an earlier folder or archive |
| `--json` | Print the summary as JSON |

## What it checks

`PINNED` in the script holds, per version, the SHA-256 of the setup, of the `ReShade64.dll` inside
it (and its size), and of ReShade's `LICENSE.md` at that version's tag. A setup, DLL or licence
with another hash is refused. To package a new ReShade: download its setup from reshade.me, check
its signature ("ReShade"), fetch `LICENSE.md` at its tag into
[`third_party/reshade/`](../third_party/reshade/README.md), and add the version's hashes.

## Output

```
native/manifest.json                                 id reshade, kind reshade, requires_loader >=0.5.0,
                                                     "reshade": {"layer": "reshade/VkLayer_nativeloader_reshade.json"}
native/payload/reshade/ReShade64.dll                 unchanged, from the setup
native/payload/reshade/VkLayer_nativeloader_reshade.json
native/payload/reshade/LICENSE.md                    third_party/reshade/LICENSE.md (BSD 3-clause)
native/payload/reshade/README.md                     what it is, where it comes from, the libraries ReShade includes
addon.json                                           for a .gma of the part alone
```

The layer manifest is upstream's `ReShade64.json` with the layer named
`VK_LAYER_nativeloader_reshade`, and without the implicit-layer switch (`disable_environment`): the
loader enables the layer by name (`VK_INSTANCE_LAYERS`), and a ReShade the setup registered for
every Vulkan application (`VK_LAYER_reshade`) stays a separate layer.

## Exit codes

0 on success; 1 when the setup, DLL or licence does not match its pinned hash, the version is not
pinned, a target exists without `--force`, or `nlctl` or gmapack refuses the result.

Side effects: the folder or archive it writes (through a `.partial-<pid>` work folder beside it).
Tests: [tests/test_package_reshade.py](tests/test_package_reshade.py.md).
