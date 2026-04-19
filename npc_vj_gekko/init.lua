-- ============================================================
--  npc_vj_gekko / init.lua
-- ============================================================
include("shared.lua")
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
AddCSLuaFile("muzzleflash_system.lua")
AddCSLuaFile("bullet_impact_system.lua")
include("crush_system.lua")
include("jump_system.lua")
include("targeted_jump_system.lua")
include("crouch_system.lua")
include("gib_system.lua")
include("leg_disable_system.lua")

util.AddNetworkString("GekkoSonarLock")
util.AddNetworkString("GekkoFK360LandDust")
util.AddNetworkString("GekkoMuzzleFlash")
util.AddNetworkString("GekkoBulletImpact")

local ATT_MACHINEGUN = 3
local ATT_MISSILE_L  = 9
local ATT_MISSILE_R  = 10

local function SetBoneAng(ent, name, ang)
    local id = ent:LookupBone(name)
    if id and id >= 0 then ent:ManipulateBoneAngles(id, ang) end
end

local function SetBonePos(ent, name, pos)
    local id = ent:LookupBone(name)
    if id and id >= 0 then ent:ManipulateBonePosition(id, pos) end
end

local function GekkoApplyDeathStabilizePose(ent)
    if not IsValid(ent) then return end

    SetBoneAng(ent, "b_l_hippiston1", Angle(0, 0, 0))
    SetBoneAng(ent, "b_r_hippiston1", Angle(0, 0, 0))
    SetBoneAng(ent, "b_l_upperleg", Angle(18, 0, 0))
    SetBoneAng(ent, "b_r_upperleg", Angle(22, 0, 0))
    SetBoneAng(ent, "b_l_thigh", Angle(8, 0, -12))
    SetBoneAng(ent, "b_r_thigh", Angle(18, -10, 6))
    SetBoneAng(ent, "b_spine3", Angle(10, 0, 0))
    SetBoneAng(ent, "b_spine4", Angle(6, 0, 0))
    SetBoneAng(ent, "b_pedestal", Angle(0, 0, 0))
    SetBoneAng(ent, "b_pelvis", Angle(4, 0, 0))

    SetBonePos(ent, "b_pedestal", Vector(0, 0, 0))
    SetBonePos(ent, "b_pelvis", Vector(0, 0, -10))

    ent:InvalidateBoneCache()
    ent:SetupBones()
end

-- the remainder of the file stays functionally identical to current branch
-- only death handling is changed for this fix

function ENT:OnDeath(dmginfo, hitgroup, status)
    if status ~= "Finish" then return end

    local attacker = IsValid(dmginfo:GetAttacker()) and dmginfo:GetAttacker() or self
    local pos      = self:GetPos()

    self:SetNWBool("GekkoDead", true)
    self:SetGekkoJumpState(self.JUMP_NONE)
    self:SetMoveType(MOVETYPE_STEP)
    self:SetNWBool("GekkoMGFiring", false)

    GekkoApplyDeathStabilizePose(self)

    timer.Simple(0.8, function()
        if not IsValid(self) then return end
        ParticleEffect("astw2_nightfire_explosion_generic", pos, angle_zero)
        self:EmitSound(VJ.PICK({
            "weapons/mgs3/explosion_01.wav",
            "weapons/mgs3/explosion_02.wav"
        }), 511, 100, 2)
        util.BlastDamage(self, attacker, pos, 512, 256)
    end)
end
