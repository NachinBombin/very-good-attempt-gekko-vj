-- ============================================================
-- FILE: lua/entities/npc_vj_gekko/init.lua
-- ============================================================
if CLIENT then return end

include("shared.lua")
include("leg_disable_system.lua")
include("gib_system.lua")

-- ============================================================
--  LOCAL HELPERS
-- ============================================================
local funcGetTable = debug.getregistry()["Entity"].GetTable

-- ============================================================
--  MODEL SETUP
-- ============================================================
function ENT:Initialize()
    self:SetModel("models/metal_gear_solid_4/enemies/gekko.mdl")
    self:SetHullType(HULL_HUMAN_SMASH)
    self:SetHullSizeNormal()
    self:SetNPCState(NPC_STATE_NONE)
    self:SetSolid(SOLID_BBOX)
    self:SetMoveType(MOVETYPE_STEP)
    self:CapabilitiesAdd(CAP_MOVE_GROUND)
    self:SetCollisionBounds(Vector(-48,-48,-4), Vector(48,48,196))
    self:SetMaxHealth(600)
    self:SetHealth(600)
    self:SetCurrentWeaponProficiency(WEAPON_PROFICIENCY_PERFECT)
    self:NavSetGoalTarget(NULL, 0)
    self.BaseClass.Initialize(self)
    -- NW setup
    self:SetNWFloat("GekkoSpeed", 0)
    self:SetNWEntity("GekkoEnemy", NULL)
    self:SetNWBool("GekkoLegsDisabled", false)
    self:SetNWBool("GekkoMGFiring", false)
    self:SetNWInt("GekkoHitReactPulse", 0)
    self:SetNW2String("GekkoHitBoneName", "b_spine3")
    self:SetNW2Vector("GekkoHitDir", Vector(0,1,0))
    self:SetNW2Bool("GekkoHitLarge", false)
end
