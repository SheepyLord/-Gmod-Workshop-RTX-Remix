# native_render.lua

Client native-model rendering, material readiness and registration, preview materials, source
shadows, visual proxies and presentation/LOD updates. Native renderer initialization precedes the
cached shader-backend query. Fixed-function Remix reuses public color names in unused depth slots
and skips Source shadow/SSAO depth-view draws; it never creates the unavailable DepthWrite shader.
Programmable Source retains the original depth material, alpha cutout, cull and texture rules.
Cache version 11 refreshes existing material mappings. Model assets, carrier identities and saved
data are unchanged. Existing archived render convars remain. MIT, same license as Model Hotloader.
