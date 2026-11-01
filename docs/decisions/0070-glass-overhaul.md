# 0070: A glass system of our own; broken glass in a dedicated Jolt world on each client

- Status: Accepted 2026-10-31 (G1). Supersedes, when G1 ships, the glass behaviour of
  [0040](0040-native-map-glass-debris.md) and [0061](0061-loose-glass-breaks-again-and-expires.md)
  (server-side pieces, their interactions and the 256-piece budget).
- Decided by: the user, choosing among the options of the [G1 plan](../handover/G1-plan.md).

## Context

The user called the shipped glass (Glass-Rewrite-Remix, GPL-2.0, from `garrys-mod-rtx-remixed`) a proof
of concept and asked for an overhaul that simulates real glass: every cause of a break scatters glass,
the break follows the point of impact, damage short of a break shows cracks, and many broken panes and
piles of pieces no longer make the game lag. Every piece is a server entity with Source physics and a
networked mesh today; the plan lists why each reported point happens.

## Decision

1. **A new glass system, MIT, in this repository** (`glass/`), written from scratch; the RTX package
   stops shipping Glass-Rewrite-Remix. Spawn-menu glass, the tool and the settings carry over.
2. **Panes are server-authoritative.** One damage entry point turns every cause (bullets, melee,
   explosions, crush, physics objects with their real mass, players, NPCs and vehicles moving into a
   pane, scripted breaks, native `func_breakable` glass) into an impact with a point, a direction, an
   energy and a kind. Impacts below the breaking energy crack the pane; the server sends each pane's
   impacts so every player sees the same cracks. A pane always breaks into pieces.
3. **The fracture is deterministic and follows the impact**, computed from the pane, the impact and a
   seed on the server (for the glass that stays in the frame) and on each client (for the pieces).
4. **Both glass kinds, chosen in the Lua menu**: annealed (radial and concentric cracks from the
   impact, the region around it breaks out, the rest stays cracked) and tempered (the whole pane turns
   into small cubes). The menu sets the kind for map windows and for spawned glass; the tool sets it per
   pane.
5. **Broken glass is cosmetic and simulated on each client**, colliding only with the map and with
   other pieces: nothing per piece on the server or the network, no pickup, props and players pass
   through it, explosions push it. Pieces may differ slightly between players.
6. **A dedicated Jolt world** in our own client module (`gmcl_nlglass_win64.dll`, MIT; Jolt Physics,
   MIT, vendored under `third_party/jolt`) simulates the pieces against the static map imported once per
   map. A fallback without the module uses a few client-side Source physics pieces.

## Consequences

- The RTX package gains a native client module; it ships only in the allowlisted package (rule 4).
- Broken glass no longer takes part in gameplay (ADR 0061's pickup, pushing and shooting of pieces go).
- The budget and lifetime of broken glass become per-player settings, since each client simulates it.
- Map logic attached to a replaced `func_breakable_surf` keeps working only where the engine allows the
  new pane to trigger it; G1 documents what remains.

## Alternatives considered

- **Reworking the GPL add-on**: keeps its one-entity design, which causes points 1 and 4.
- **Client-side Source physics only**: no native code, but the same physics limits at a lower count.
- **VPhysics-Jolt as the game's physics engine**: its README says its authors cannot redistribute the
  code and headers needed to build it for Garry's Mod; it replaces all of the game's physics (missing
  breakable constraints and airboat-style vehicles); and replacing `vphysics.dll` on disk breaks rule 2.
- **Server-side pieces with interactions (ADR 0061)**: the cost the user reported; not needed, per the
  request.
