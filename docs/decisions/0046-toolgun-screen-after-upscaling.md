# 0046: Draw the live toolgun screen after upscaling

- Status: Accepted 2026-10-30; its mechanism is superseded by [0057](0057-toolgun-screen-as-2d-overlay.md)
- Decided by: the user's request 22

## Context

Animated text rendered onto the toolgun is reconstructed as scene geometry by temporal upscaling.
Its texture changes independently of the model's motion, producing unreadable trails.

## Decision

The companion captures the toolgun screen mesh, current bone pose, live texture and actual
viewmodel projection. During HUDPaint it draws that screen at output resolution in a private
render target, using a separate depth mask for the gun and hands, then composites the result.
The original tool and screen add-ons continue rendering their textures normally.

The default-on Keep toolgun text sharp setting lives under RTX Remix / Rendering / Toolgun screen,
with all six translations. Unsupported models and auxiliary views keep their original behavior.
Failures restore render state and disable the extra pass until the player toggles it or restarts.
There are no texture-hash categories, changes to upscaler preferences or user.conf writes.

## Consequences

The full-resolution screen needs a private render target for each output size used. Compatibility
is bounded to models exposing the stock toolgun screen material and usable skeletal mesh data.
Tests cover texture animation, bone transforms, view projection, failure cleanup and resize; live
tests include the subscribed Dynamic Toolgun Screen add-on without redistributing its assets.
