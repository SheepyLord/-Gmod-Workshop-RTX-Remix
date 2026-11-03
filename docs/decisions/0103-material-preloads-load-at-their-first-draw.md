# 0103: Material preloads load at their first draw

- Status: Accepted 2026-11-03 (the user accepted the hitch the A/B measured, and again the larger range
  the check sessions found, below; R13-F). Runtime patch 0030.
- Decided by: the user, after the A/B measured in [R13-F](../handover/R13-F-report.md), under their
  rule for R13's memory work, "visible quality unchanged" ([R13-plan.md](../handover/R13-plan.md)); the
  hitch was theirs to weigh.
- Supersedes in part: [0102](0102-character-pbr-maps-stay-preloaded.md), its consequence "Startup
  VRAM and commit keep the preloads" and its open bullet "Load a preload on its first draw (not
  measured yet)". Its decision that rpai, ToPBR and the material editor keep writing
  `preload_textures = 1` stands.
- Builds on: [0100](0100-one-copy-and-idle-release-of-game-textures.md) (patch 0026: undrawn preloads
  give way under real VRAM pressure).

## Context

A USD material with `preload_textures = 1` loaded every mip of every texture when its mod loaded,
drawn or not, and pinned it: 11.05 GB of files in the field at every start, most of them characters
nobody spawns that session (R13-B). R13-P measured streaming those maps instead: 2.23 GB less at idle
in the PoC, the same settled image, but every first appearance showed the maps' smallest mips for
0.15-0.9 s ([ADR 0102](0102-character-pbr-maps-stay-preloaded.md)).

Runtime patch 0030 keeps what a preload looks like and moves its cost: a material's preload starts at
its smallest mips like a streamed texture, and the first frame an instance draws the material pins it
and stages every mip synchronously; the upload goes with that frame's uploads, before the scene is
built and traced, so that frame already samples the whole chain. R13-F ran R13-P's lab with today's
runtime (A) and the patched one (F), three PoC sessions each, both with the preloading character packs.

- **The look is unchanged.** At full resolution, aligned on the hotloader's crossfade, F's first frame
  of each character shows the whole maps, as A's does (Robin's treble-clef emblem, star brooch and
  bodice, which the streamed variant showed grey and smeared). The settled views stay within
  run-to-run noise.
- **Start-up:** 2.39 GB less of replacement textures at idle (2.66 to 0.27 GB), 1.64-1.70 GB less
  driver VRAM and 1.7-2.5 GB less private bytes. The map's load time stayed within run-to-run variation.
- **The hitch:** the frame that first draws a character lasts 0.11-0.32 s instead of today's
  0.04-0.11 s at that moment, about the time the runtime takes to stage 0.3-0.5 GB on one thread
  (0.10-0.20 s with the files in the file cache). Later in the day, in another state of the machine,
  the same staging took 2-3 times as long and the frame 0.20-0.58 s, while today's runtime stayed at
  0.07-0.11 s. The picture stops on the hotloader's stand-in for
  that frame. It comes once per character and session; a respawn costs nothing more. A character's
  first spawn already freezes for 0.8-1.3 s, twice, while the hotloader loads its model, about two
  seconds earlier, with either runtime.

## Decision

- A USD material's `preload_textures` loads at the material's first draw, whole and synchronously,
  instead of when its mod loads (runtime patch 0030). `rtx.texturemanager.preloadOnFirstDraw`
  (default True) turns it off for materials loaded afterwards.
- Unchanged: textures too large to stream, preloads that are not a USD material's (dome lights, the
  Remix API's) and every preload while `rtx.texturemanager.neverDowngradeTextures` is on load whole
  with the mod; after its first draw a preload is pinned as before and patch 0026's pressure rule
  still releases it while undrawn.
- The generators keep writing the flag. It now means "whole from the first frame it is drawn",
  which is what it was for.

## Consequences

- Start-up VRAM and commit drop by what the preloading mods hold for materials not drawn: in the
  field, most of 11 GB. Each character's maps load at its first draw in a session, as one long frame.
- The hitch grows with the character's maps and with the disk: R13-F measured warm files on an NVMe
  drive. A cold start reads the files first: at 0.5 GB/s (SATA SSD) a 0.4 GB character adds about
  0.8 s to that frame, and a hard disk takes seconds. Turning the option off restores today's
  behaviour.
- Map materials with the flag load in the first frames that draw them, so their cost moves from the
  mod's load into the map's first frames.
- A material drawn in the frame its mod loaded is still whole in that frame: the waiting upload of its
  smallest mips is replaced by one of every mip. Only a texture whose load is still on the worker
  thread (after an explicit texture purge) can show its smallest mips for one frame.
- `[RTX Preload]` log lines show each frame's first-draw loads and what still waits.
- It was measured as patch 0029 on 0028; R13-D's option lock merged first as 0029, so it ships as 0030
  on top of it, in a runtime rebuilt with both (which do not share a file).

## Alternatives considered

- **Keep loading preloads with the mod** ([0102](0102-character-pbr-maps-stay-preloaded.md)): no
  hitch, 11 GB of start-up VRAM and commit in the field.
- **Stream the maps** (R13-P): no hitch, but blurry maps for 0.15-0.9 s at every appearance.
- **Stage a frame's first-draw textures on several threads:** one thread stages about 2.5 GB/s;
  several could shorten the hitch to the upload. Not built.
- **Prefetch when the hotloader starts a spawn**, about two seconds before the character is drawn:
  would hide the load behind the stand-in. Needs a Remix API call and a hotloader change. Not built.
