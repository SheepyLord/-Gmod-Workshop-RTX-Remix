-- MIT. Replicated gameplay convars must exist in both realms to receive server values.
local C = {}
C.Settings = {
    {"rtx_glass_map_kind", "annealed"}, {"rtx_glass_spawn_kind", "annealed"},
    {"rtx_glass_strength", "1", 0.1, 10}, {"rtx_glass_show_cracks", "1", 0, 1},
    {"rtx_glass_piece_size", "8", 4, 64}, {"rtx_glass_velocity_transfer", "1", 0, 3},
    {"rtx_glass_player_break_speed", "250", 0, 1000}, {"rtx_glass_player_mass", "85", 1, 500},
}
C.Debris = {{"rtx_glass_debris_lifetime","120"},{"rtx_glass_debris_budget","2000"},{"rtx_glass_debris_collide","1"},
    {"rtx_glass_debris_interact","1"}}
for _,s in ipairs(C.Settings) do
    CreateConVar(s[1],s[2],FCVAR_ARCHIVE+FCVAR_REPLICATED+FCVAR_NOTIFY,"Native loader glass setting",s[3],s[4])
end
function C.Number(name, default)
    local c=GetConVar(name)
    return c and c:GetFloat() or default
end
function C.Kind(name)
    local c=GetConVar(name)
    return c and c:GetString()=="tempered" and "tempered" or "annealed"
end
return C
