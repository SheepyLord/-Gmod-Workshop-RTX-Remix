-- Network strings used by the phase-one hit debugger.

BBS = BBS or {}

if SERVER then
	util.AddNetworkString( BBS.NET_HIT )
	util.AddNetworkString( BBS.NET_SET_ENABLED )
	util.AddNetworkString( BBS.NET_SET_DEATH_ONLY )
	util.AddNetworkString( BBS.NET_SET_LIVING_PLAYERS )
	util.AddNetworkString( BBS.NET_SET_LIVING_NPCS )
	util.AddNetworkString( BBS.NET_TRANSFER_DEATH_DAMAGE )
end
