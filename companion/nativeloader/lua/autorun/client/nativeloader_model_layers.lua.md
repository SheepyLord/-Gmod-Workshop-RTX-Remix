# nativeloader_model_layers.lua

RTX-only client outline suppression. `nativeloader_ignore_outlines` defaults to 1. The Model
outlines panel controls it; layered facial cutouts are corrected automatically in the runtime.

Discovers explicit outline material names and the dedicated hei/touming materials in the MMD
template family. Model/skin metadata is cached; entity creation, submaterial changes, native
registry bindings and private local-body proxy entries are handled. Material names normalize
parenthesized source suffixes. Procedural proxies are queried after real draws without filesystem
lookups. All native hashes are tracked, including readiness changes without a binding revision.
Shared images used by ordinary model materials are protected from global hiding.

Think publishes only two owned, nonpersistent native options: the front-culled outline switch
and its sorted texture hash list. Original materials, other categories, entity overrides, Steam
files and user.conf are not modified. The native runtime hides matching geometry from primary,
shadow and reflection rays. Opt-out clears the owned list and switch. Failed writes retry.

Resources are client-local tables and native lookups; no server or network messages. The command
`nativeloader_model_layers_status` prints the switch and current texture list. No process exit code.
