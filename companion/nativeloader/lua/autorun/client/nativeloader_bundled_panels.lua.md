# nativeloader_bundled_panels.lua

R20-C client fallback for the screen part built without the complete companion (including RTX-off
component testing). With the package marker it moves the actual tracking tool/full settings into
RTX Remix / Rendering and suppresses the duplicate dts_settings Utilities shortcut. It forwards
all other registrations unchanged. The tool's own thirteen-language title is used without the
companion catalog; otherwise the existing six-catalog title/category are used.

Returns when the full nativeloader_menu.lua exists, so the combined package has its original single
wrapper/category owner. Idempotent; no settings, files, network or native preferences are changed.
No process exit code. The packager attaches this maintained source to the independent screen part.
