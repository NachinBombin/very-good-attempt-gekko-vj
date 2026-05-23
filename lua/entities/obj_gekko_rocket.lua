/*-----------------------------------------------
	*** Copyright (c) 2012-2026 by DrVrej, All rights reserved. ***
	No parts of this code or any of its contents may be reproduced, copied, modified or adapted,
	without the prior written consent of the author, unless otherwise indicated for stand-alone materials.
-----------------------------------------------*/
-- Standalone copy of obj_vj_rocket for the Gekko NPC.
-- Originally authored by DrVrej. Forked here for Gekko-specific customization.
-- Replace references to "obj_vj_rocket" in the Gekko NPC with "obj_gekko_rocket".
AddCSLuaFile()

ENT.Type 			= "anim"
ENT.Base 			= "obj_vj_projectile_base"
ENT.PrintName		= "Gekko Rocket"
ENT.Author 			= "DrVrej (forked for Gekko by NachinBombin)"
ENT.Contact 		= "http://steamcommunity.com/groups/vrejgaming"
ENT.Category		= "VJ Base"

ENT.VJ_ID_Danger = true

-- =========================================================================
-- Shared gib configuration (mirrors Bushmaster logic, always fires x3)
-- =========================================================================
local GIB_LIFETIME = 3.5
local GIB_MODELS = {
    "models/props_junk/CinderBlock01a.mdl",
    "models/props_mining/rock_caves01a.mdl",
    "models/props_mining/rock_caves01b.mdl",
    "models/props_mining/rock_caves01c.mdl",
    "models/props_debris/concrete_spawnchunk001b.mdl",
    "models/props_debris/concrete_spawnchunk001d.mdl",
    "models/props_debris/concrete_spawnchunk001g.mdl",
    "models/props_debris/concrete_spawnchunk001i.mdl",
    "models/props_debris/concrete_spawnchunk001k.mdl",
    "models/props_debris/concrete_spawnchunk001j.mdl",
    "models/props_debris/prison_wallchunk001f.mdl",
    "models/props_debris/concrete_chunk09a.mdl",
    "models/props_debris/concrete_chunk03a.mdl",
    "models/props_debris/concrete_chunk04a.mdl",
    "models/props_debris/concrete_chunk05g.mdl",
    "models/props_debris/concrete_chunk02a.mdl",
    "models/props_debris/tile_wall001a_chunk02.mdl",
    "models/props_debris/tile_wall001a_chunk09.mdl",
    "models/props_debris/tile_wall001a_chunk06.mdl",
    "models/props_debris/tile_wall001a_chunk05.mdl",
    "models/props_debris/rebar001a_32.mdl",
    "models/props_debris/rebar003a_32.mdl",
}

local function SpawnIgnitedGib( hitPos, hitNormal )
    local mdl = GIB_MODELS[ math.random( #GIB_MODELS ) ]
    local gib = ents.Create( "prop_physics" )
    if not IsValid( gib ) then return end
    gib:SetModel( mdl )
    gib:SetPos( hitPos + hitNormal * 4 )
    gib:SetCollisionGroup( COLLISION_GROUP_DEBRIS )
    gib:Spawn()
    gib:Activate()
    gib:DrawShadow( false )
    timer.Simple( GIB_LIFETIME, function()
        if IsValid( gib ) then gib:Remove() end
    end )
    local phys = gib:GetPhysicsObject()
    if not IsValid( phys ) then gib:Remove() return end
    -- hemisphere impulse aligned to surface normal
    local helper
    if math.abs( hitNormal.z ) < 0.9 then
        helper = Vector( 0, 0, 1 )
    else
        helper = Vector( 1, 0, 0 )
    end
    local tangent   = hitNormal:Cross( helper )  tangent:Normalize()
    local bitangent = hitNormal:Cross( tangent ) bitangent:Normalize()
    local cos_theta = math.random()
    local sin_theta = math.sqrt( 1 - cos_theta * cos_theta )
    local phi       = math.random() * ( 2 * math.pi )
    local cp        = math.cos( phi )
    local sp        = math.sin( phi )
    local nx, ny, nz = hitNormal.x, hitNormal.y, hitNormal.z
    local dx = nx * cos_theta + tangent.x * ( sin_theta * cp ) + bitangent.x * ( sin_theta * sp )
    local dy = ny * cos_theta + tangent.y * ( sin_theta * cp ) + bitangent.y * ( sin_theta * sp )
    local dz = nz * cos_theta + tangent.z * ( sin_theta * cp ) + bitangent.z * ( sin_theta * sp )
    local dlen = math.sqrt( dx*dx + dy*dy + dz*dz )
    if dlen < 0.001 then gib:Remove() return end
    dx = dx / dlen  dy = dy / dlen  dz = dz / dlen
    local speed = math.Rand( 120, 340 )
    phys:SetVelocity( Vector( dx * speed, dy * speed, dz * speed ) )
    phys:SetAngleVelocity( Vector( math.Rand(-400,400), math.Rand(-400,400), math.Rand(-400,400) ) )
    gib:Ignite( 0, 0 )
end

---------------------------------------------------------------------------------------------------------------------------------------------
if CLIENT then
	VJ.AddKillIcon("obj_gekko_rocket", ENT.PrintName, VJ.KILLICON_PROJECTILE)

	/*function ENT:Think()
		if self:IsValid() then
			self.Emitter = ParticleEmitter(self:GetPos())
			self.SmokeEffect1 = self.Emitter:Add("particles/flamelet2", self:GetPos() + self:GetForward()*-7)
			self.SmokeEffect1:SetVelocity(self:GetForward() *math.Rand(0, -50) + Vector(math.Rand(5, -5), math.Rand(5, -5), math.Rand(5, -5)) + self:GetVelocity())
			self.SmokeEffect1:SetDieTime(0.2)
			self.SmokeEffect1:SetStartAlpha(100)
			self.SmokeEffect1:SetEndAlpha(0)
			self.SmokeEffect1:SetStartSize(10)
			self.SmokeEffect1:SetEndSize(1)
			self.SmokeEffect1:SetRoll(math.Rand(-0.2, 0.2))
			self.SmokeEffect1:SetAirResistance(200)
			self.Emitter:Finish()
		end
	end*/
end
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
if !SERVER then return end

ENT.Model = "models/weapons/w_missile_launch.mdl"
ENT.DoesRadiusDamage = true
ENT.RadiusDamageRadius = 250
ENT.RadiusDamage = 110
ENT.RadiusDamageUseRealisticRadius = true
ENT.RadiusDamageType = DMG_BLAST
ENT.RadiusDamageForce = 90
ENT.CollisionDecal = "Scorch"
ENT.SoundTbl_Idle = "weapons/rpg/rocket1.wav"
ENT.SoundTbl_OnCollide = "ambient/explosions/explode_8.wav"
---------------------------------------------------------------------------------------------------------------------------------------------
function ENT:Init()
	//util.SpriteTrail(self, 0, Color(90, 90, 90, 255), false, 10, 1, 3, 1 / (15 + 1)*0.5, "trails/smoke.vmt")
	ParticleEffectAttach("vj_rocket_idle1", PATTACH_ABSORIGIN_FOLLOW, self, 0)
	ParticleEffectAttach("vj_rocket_idle2", PATTACH_ABSORIGIN_FOLLOW, self, 0)
	//ParticleEffectAttach("rocket_smoke", PATTACH_ABSORIGIN_FOLLOW, self, 0)
	//ParticleEffectAttach("smoke_burning_engine_01", PATTACH_ABSORIGIN_FOLLOW, self, 0)
	
	//local dynLight = ents.Create("light_dynamic")
	//dynLight:SetKeyValue("brightness", "1")
	//dynLight:SetKeyValue("distance", "200")
	//dynLight:SetLocalPos(self:GetPos())
	//dynLight:SetLocalAngles( self:GetAngles() )
	//dynLight:Fire("Color", "255 150 0")
	//dynLight:SetParent(self)
	//dynLight:Spawn()
	//dynLight:Activate()
	//dynLight:Fire("TurnOn")
	//self:DeleteOnRemove(dynLight)
end
---------------------------------------------------------------------------------------------------------------------------------------------
local defAngle = Angle(0, 0, 0)
--
function ENT:OnDestroy(data, phys)
	VJ.EmitSound(self, "VJ.Explosion")
	ParticleEffect("vj_explosion3", data.HitPos, defAngle)
	util.ScreenShake(data.HitPos, 16, 200, 1, 3000)
	
	local effectData = EffectData()
	effectData:SetOrigin(data.HitPos)
	//effectData:SetScale(500)
	//util.Effect("HelicopterMegaBomb", effectData)
	//util.Effect("ThumperDust", effectData)
	//util.Effect("Explosion", effectData)
	util.Effect("VJ_Small_Explosion1", effectData)

	local expLight = ents.Create("light_dynamic")
	expLight:SetKeyValue("brightness", "4")
	expLight:SetKeyValue("distance", "300")
	expLight:SetLocalPos(data.HitPos)
	expLight:SetLocalAngles(self:GetAngles())
	expLight:Fire("Color", "255 150 0")
	expLight:SetParent(self)
	expLight:Spawn()
	expLight:Activate()
	expLight:Fire("TurnOn")
	self:DeleteOnRemove(expLight)

	-- Spawn 3 ignited concrete gibs on every explosion
	local hitNormal = IsValid( data.HitEntity ) and
		( data.HitPos - data.HitEntity:GetPos() ):GetNormalized() or
		Vector( 0, 0, 1 )
	for i = 1, 3 do
		SpawnIgnitedGib( data.HitPos, hitNormal )
	end
end
