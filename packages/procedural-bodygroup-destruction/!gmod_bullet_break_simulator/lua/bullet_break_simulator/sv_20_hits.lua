-- Detect bullet damage on enabled server-side model targets and broadcast it.

BBS = BBS or {}
BBS.ServerHitSerial = BBS.ServerHitSerial or 0
BBS.DeathTransferSerial = BBS.DeathTransferSerial or 0
BBS.DeathRagdolls = BBS.DeathRagdolls or setmetatable( {}, { __mode = "k" } )

hook.Add( "CreateEntityRagdoll", "BBS.MarkNPCPlayerDeathRagdoll",
	function( owner, ragdoll )
		if not IsValid( owner ) or not IsValid( ragdoll ) then return end
		if not BBS.IsLivingDamageTarget( owner ) then return end
		BBS.DeathRagdolls[ ragdoll ] = true
		ragdoll.BBSDeathRagdoll = true
		ragdoll:SetNW2Bool( "BBS.DeathRagdoll", true )

		-- Entity references can arrive before the client has created the ragdoll,
		-- so transmit stable indices/model metadata and let the client resolve it.
		BBS.DeathTransferSerial = ( BBS.DeathTransferSerial + 1 ) % 65536
		local transferSerial = BBS.DeathTransferSerial
		local sourceIndex = owner:EntIndex()
		local ragdollIndex = ragdoll:EntIndex()
		local sourceModel = string.lower( owner:GetModel() or "" )
		ragdoll:SetNW2Int( "BBS.DamageSourceEntIndex", sourceIndex )
		ragdoll:SetNW2Int( "BBS.DamageTransferSerial", transferSerial )
		ragdoll:SetNW2String( "BBS.DamageSourceModel", sourceModel )

		timer.Simple( 0, function()
			if not IsValid( ragdoll ) then return end
			net.Start( BBS.NET_TRANSFER_DEATH_DAMAGE )
				net.WriteUInt( transferSerial, 16 )
				net.WriteUInt( sourceIndex, 16 )
				net.WriteUInt( ragdollIndex, 16 )
				net.WriteString( sourceModel )
			net.Broadcast()
		end )
	end )

local function DamageDirection( damageInfo )
	local direction = damageInfo:GetDamageForce()
	if not direction:IsZero() then return direction:GetNormalized() end

	local attacker = damageInfo:GetAttacker()
	if IsValid( attacker ) and attacker.GetAimVector then
		direction = attacker:GetAimVector()
		if not direction:IsZero() then return direction:GetNormalized() end
	end

	return nil
end

-- The previous ragdoll-only hook name survives Lua auto-refresh unless it is
-- removed explicitly, which would otherwise broadcast every ragdoll hit twice.
hook.Remove( "EntityTakeDamage", "BBS.CaptureRagdollBulletHit" )
hook.Add( "EntityTakeDamage", "BBS.CaptureModelBulletHit", function( entity, damageInfo )
	if not GetConVar( "bbs_enabled" ):GetBool() then return end
	local targetEnabled, targetKind = BBS.IsDamageTargetEnabled( entity )
	if not targetEnabled then return end
	if targetKind == "ragdoll"
	and GetConVar( "bbs_death_ragdolls_only" ):GetBool()
	and not BBS.DeathRagdolls[ entity ]
	and not entity.BBSDeathRagdoll
	and not entity:GetNW2Bool( "BBS.DeathRagdoll", false ) then return end
	if not damageInfo:IsDamageType( DMG_BULLET ) then return end

	local position = damageInfo:GetDamagePosition()
	local direction = DamageDirection( damageInfo )
	if not position or position:IsZero() then
		if GetConVar( "bbs_server_logging" ):GetBool() then
			BBS.Log( "ignored bullet damage on %s: damage position was zero", tostring( entity ) )
		end
		return
	end
	if not direction then
		if GetConVar( "bbs_server_logging" ):GetBool() then
			BBS.Log( "ignored bullet damage on %s: no usable direction", tostring( entity ) )
		end
		return
	end

	BBS.ServerHitSerial = ( BBS.ServerHitSerial + 1 ) % 65536
	local attacker = damageInfo:GetAttacker()

	if GetConVar( "bbs_server_logging" ):GetBool() then
		BBS.Log( "SV hit #%d ent=%d model=%s pos=[%s] dir=[%s] damage=%.2f attacker=%s",
			BBS.ServerHitSerial, entity:EntIndex(), entity:GetModel() or "<none>",
			BBS.FormatVector( position ), BBS.FormatVector( direction ),
			damageInfo:GetDamage(), tostring( attacker ) )
	end

	net.Start( BBS.NET_HIT )
		net.WriteUInt( BBS.ServerHitSerial, 16 )
		net.WriteEntity( entity )
		net.WriteVector( position )
		net.WriteNormal( direction )
		net.WriteFloat( damageInfo:GetDamage() )
		net.WriteEntity( IsValid( attacker ) and attacker or NULL )
	net.Broadcast()
end )

local function CanChangeServerSetting( player, name )
	if not IsValid( player ) then return false end
	if game.SinglePlayer() or player:IsAdmin() then return true end
	BBS.Log( "%s tried to change %s without admin access",
		tostring( player ), tostring( name ) )
	return false
end

net.Receive( BBS.NET_SET_ENABLED, function( _, player )
	if not CanChangeServerSetting( player, "bbs_enabled" ) then return end

	local enabled = net.ReadBool()
	GetConVar( "bbs_enabled" ):SetBool( enabled )
	BBS.Log( "%s set bbs_enabled to %s", tostring( player ), tostring( enabled ) )
end )

net.Receive( BBS.NET_SET_DEATH_ONLY, function( _, player )
	if not CanChangeServerSetting( player, "bbs_death_ragdolls_only" ) then return end
	local enabled = net.ReadBool()
	GetConVar( "bbs_death_ragdolls_only" ):SetBool( enabled )
	BBS.Log( "%s set bbs_death_ragdolls_only to %s",
		tostring( player ), tostring( enabled ) )
end )

local function ReceiveTargetSetting( player, convarName, label )
	if not CanChangeServerSetting( player, convarName ) then return end
	local enabled = net.ReadBool()
	GetConVar( convarName ):SetBool( enabled )
	BBS.Log( "%s set %s to %s", tostring( player ), label, tostring( enabled ) )
end

net.Receive( BBS.NET_SET_LIVING_PLAYERS, function( _, player )
	ReceiveTargetSetting( player, "bbs_damage_living_players",
		"living-player effects" )
end )

net.Receive( BBS.NET_SET_LIVING_NPCS, function( _, player )
	ReceiveTargetSetting( player, "bbs_damage_living_npcs",
		"living-NPC effects" )
end )
