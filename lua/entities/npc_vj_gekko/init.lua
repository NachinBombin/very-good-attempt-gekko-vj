-- ============================================================
-- npc_vj_gekko / init.lua
-- ============================================================
-- Weapon list:
--   1. "Midas Veil" (MG + missile)
--   2. "Midas Veil" (MG only)
--   3. "Midas Veil" (missile only)
--   4. Melee only (stomp + kick)
-- ============================================================
if CLIENT then return end

include("shared.lua")
include("leg_disable_system.lua")
include("gib_system.lua")
include("jump_system.lua")
include("targeted_jump_system.lua")
include("crouch_system.lua")
include("crush_system.lua")
include("elastic_system.lua")
include("flinch_system.lua")
include("muzzleflash_system.lua")
include("bullet_impact_system.lua")
include("death_pose_system.lua")

-- ============================================================
-- CONVARS
-- ============================================================
CreateConVar("gekko_juicy_bleeding_enabled",   "1",    FCVAR_ARCHIVE, "Enable Gekko juicy bleeding", 0, 1)
CreateConVar("gekko_juicy_bleeding_cooldown",  "0.15", FCVAR_ARCHIVE, "Min seconds between bleeds", 0.0, 5.0)
CreateConVar("gekko_juicy_bleeding_maxactive", "8",    FCVAR_ARCHIVE, "Max concurrent bleed streams", 1, 20)
CreateConVar("gekko_juicy_bleeding_darker",    "0",    FCVAR_ARCHIVE, "Use darker blood variant", 0, 1)

-- ============================================================
-- SPRINT CONFIGURATION
-- ============================================================
-- When the Gekko has a clear line-of-sight and is within
-- randomly break into a full sprint for 2-4 s, then settle
-- back to normal walk/run speed.
-- Distance thresholds (in Hammer units):
local SPRINT_MIN_DIST       = 400   -- don't sprint if already close
local SPRINT_MAX_DIST       = 1500  -- too far away → don't sprint either
local SPRINT_DUR_MIN        = 2.0   -- seconds, min sprint burst length
local SPRINT_DUR_MAX        = 4.0   -- seconds, max sprint burst length
local SPRINT_COOLDOWN_MIN   = 3.0   -- seconds before next sprint can trigger
local SPRINT_COOLDOWN_MAX   = 7.0   -- seconds before next sprint can trigger
local SPRINT_MOVE_SPEED     = 420   -- MoveSpeed during sprint
local SPRINT_RUN_SPEED      = 420   -- RunSpeed during sprint
local SPRINT_WALK_SPEED     = 420   -- WalkSpeed during sprint

-- ============================================================
-- LOCAL HELPERS
-- ============================================================
local funcGetTable = debug.getregistry()["Entity"].GetTable

-- ============================================================
-- BONE LIST DEBUGGER  (fires once per NPC on spawn)
-- ============================================================
local boneListPrinted = false
local function GekkoDebugBoneList(ent)
    if boneListPrinted then return end
    boneListPrinted = true
    local total = ent:GetBoneCount()
    print("[GekkoAI] ===== BONE LIST =====")
    print("[GekkoAI] Total bones: " .. tostring(total))
    for i = 0, total - 1 do
        local name   = ent:GetBoneName(i)
        local parent = ent:GetBoneParent(i)
        print(string.format("[GekkoAI] [%2d] %s parent=%d", i, tostring(name), parent))
    end
    print("[GekkoAI] ===== END BONE LIST =====")
end

-- ============================================================
-- WEAPON / LOADOUT SYSTEM
-- ============================================================
-- Loadout table – each entry is a set of VJ-Base weapon keys
-- that get merged into ENT when a loadout is chosen.
local LOADOUTS = {
    -- 1: Full Midas Veil  (MG + missile)
    {
        HasRangeAttack             = true,
        RangeAttackEntityDamage    = 18,
        RangeAttackDamage          = 18,
        AnimationTranslations      = {},
        RangeAttackBulletCount     = 1,
        RangeAttackBulletSpread    = Vector(0.025, 0.025, 0),
        RangeAttackTracerName      = "Tracer",
        HasSecondaryRangeAttack    = true,
        SecondaryRangeAttackDamage = 90,
        SecondaryRangeAttackType   = "Projectile",
    },
    -- 2: MG only
    {
        HasRangeAttack             = true,
        RangeAttackEntityDamage    = 18,
        RangeAttackDamage          = 18,
        RangeAttackBulletCount     = 1,
        RangeAttackBulletSpread    = Vector(0.025, 0.025, 0),
        RangeAttackTracerName      = "Tracer",
        HasSecondaryRangeAttack    = false,
    },
    -- 3: Missile only
    {
        HasRangeAttack             = false,
        HasSecondaryRangeAttack    = true,
        SecondaryRangeAttackDamage = 90,
        SecondaryRangeAttackType   = "Projectile",
    },
    -- 4: Melee only
    {
        HasRangeAttack             = false,
        HasSecondaryRangeAttack    = false,
    },
}

-- Returns a random loadout index (1–4)
local function RollWeapon()
    return math.random(1, #LOADOUTS)
end

-- Apply a loadout index to an entity, skipping key if value is nil
local function ApplyLoadout(ent, idx)
    local loadout = LOADOUTS[idx]
    if not loadout then return end
    for k, v in pairs(loadout) do
        ent[k] = v
    end
end

-- Re-roll a loadout, guaranteeing it is different from `exclude`
local function RerollLoadout(ent, exclude)
    local reroll
    repeat reroll = RollWeapon() until reroll ~= exclude
    ApplyLoadout(ent, reroll)
    ent._currentLoadout = reroll
end

-- ============================================================
-- SPRINT STATE MACHINE
-- ============================================================

-- Apply sprint speeds, force run animation state, arm the end timer.
local function GekkoSprint_Begin(ent)
    -- Guard: don't sprint while in a jump or crouch
    local js = ent:GetGekkoJumpState()
    if js and js ~= "none" then
        ent._gekkoSprintNextT = CurTime() + math.Rand(SPRINT_COOLDOWN_MIN, SPRINT_COOLDOWN_MAX)
        return
    end
    if ent._gekkoCrouching then
        ent._gekkoSprintNextT = CurTime() + math.Rand(SPRINT_COOLDOWN_MIN, SPRINT_COOLDOWN_MAX)
        return
    end

    ent._gekkoSprinting    = true
    ent._gekkoSprintEndT   = CurTime() + math.Rand(SPRINT_DUR_MIN, SPRINT_DUR_MAX)

    -- Swap to sprint speeds (save originals if not already saved)
    if not ent._preSprint_MoveSpeed then
        ent._preSprint_MoveSpeed = ent.MoveSpeed
        ent._preSprint_RunSpeed  = ent.RunSpeed
        ent._preSprint_WalkSpeed = ent.WalkSpeed
    end
    ent.MoveSpeed  = SPRINT_MOVE_SPEED
    ent.RunSpeed   = SPRINT_RUN_SPEED
    ent.WalkSpeed  = SPRINT_WALK_SPEED

    print(string.format("[GekkoSprint] BEGIN | dur=%.1fs", ent._gekkoSprintEndT - CurTime()))
end

local function GekkoSprint_End(ent)
    ent._gekkoSprinting = false

    if ent._preSprint_MoveSpeed then
        ent.MoveSpeed = ent._preSprint_MoveSpeed
        ent.RunSpeed  = ent._preSprint_RunSpeed
        ent.WalkSpeed = ent._preSprint_WalkSpeed
        ent._preSprint_MoveSpeed = nil
        ent._preSprint_RunSpeed  = nil
        ent._preSprint_WalkSpeed = nil
    end

    ent._gekkoSprintNextT = CurTime() + math.Rand(SPRINT_COOLDOWN_MIN, SPRINT_COOLDOWN_MAX)
    print("[GekkoSprint] END")
end

-- Called every OnThink tick. Manages the sprint state machine.
local function GekkoSprint_Think(ent)
    if not IsValid(ent) then return end

    -- If currently sprinting, check if the burst has expired
    if ent._gekkoSprinting then
        if CurTime() >= ent._gekkoSprintEndT then
            GekkoSprint_End(ent)
        end
        return  -- don't re-evaluate while already sprinting
    end

    -- Cooldown: too soon to consider another sprint
    if CurTime() < (ent._gekkoSprintNextT or 0) then return end

    local enemy = ent:GetEnemy()
    if not IsValid(enemy) then return end

    local dist = ent:GetPos():Distance(enemy:GetPos())
    if dist < SPRINT_MIN_DIST or dist > SPRINT_MAX_DIST then return end

    -- 30 % chance per evaluation window to begin a sprint
    if math.random() < 0.30 then
        GekkoSprint_Begin(ent)
    else
        -- Delay next evaluation by a shorter window
        ent._gekkoSprintNextT = CurTime() + math.Rand(1.0, 2.5)
    end
end

-- ============================================================
-- VJ BASE ENTITY KEYS
-- ============================================================
ENT.Model           = {"models/metal_gear_solid_4/enemies/gekko.mdl"}
ENT.StartHealth     = 600
ENT.HasDeathAnimation = false
ENT.VJ_ID_Liquid    = FCONTENTS_WATER
ENT.Bleeds          = false   -- vanilla VJ bleed suppressed; juicy system takes over

-- Melee
ENT.HasMeleeAttack          = true
ENT.MeleeAttackDamage       = 65
ENT.MeleeAttackDamageType   = DMG_CLUB
ENT.MeleeAttackKnockBack    = 800

-- Range (defaults; overridden by loadout on spawn)
ENT.HasRangeAttack          = true
ENT.RangeAttackEntityDamage = 18
ENT.RangeAttackDamage       = 18
ENT.RangeAttackBulletCount  = 1
ENT.RangeAttackBulletSpread = Vector(0.025, 0.025, 0)
ENT.RangeAttackTracerName   = "Tracer"

-- Secondary (missile) defaults
ENT.HasSecondaryRangeAttack    = true
ENT.SecondaryRangeAttackDamage = 90

-- ============================================================
-- INITIALIZE
-- ============================================================
function ENT:OnEntityInfo()
    GekkoDebugBoneList(self)

    -- Pick a random loadout for this spawn
    local roll = RollWeapon()
    ApplyLoadout(self, roll)
    self._currentLoadout = roll

    -- Sprint state
    self._gekkoSprinting   = false
    self._gekkoSprintEndT  = 0
    self._gekkoSprintNextT = CurTime() + math.Rand(SPRINT_COOLDOWN_MIN, SPRINT_COOLDOWN_MAX)

    -- NW vars for client
    self:SetNWInt   ("GekkoHitReactPulse", 0)
    self:SetNW2String("GekkoHitBoneName", "b_spine3")
    self:SetNW2Vector("GekkoHitDir",      Vector(0,1,0))
    self:SetNW2Bool  ("GekkoHitLarge",    false)

    print("[GekkoAI] AI enabled, state ACTIVE")
end

-- ============================================================
-- THINK HOOK  (called by VJ Base every server tick)
-- ============================================================
function ENT:VJ_OnThink()
    GekkoSprint_Think(self)
    self:GekkoJump_Think()
    self:GekkoTargetedJump_Think()
    self:GekkoCrouch_Think()
    self:GekkoElastic_Think()
end

-- ============================================================
-- VANILLA BLOOD HELPERS
-- ============================================================
local function GekkoSignalBloodHit(ent, hitPos, hitNormal)
    local ed = EffectData()
    ed:SetEntity(ent)
    ed:SetOrigin(hitPos)
    ed:SetNormal(hitNormal)
    ed:SetMagnitude(1)
    util.Effect("HelicopterImpact", ed, true, true)
end

local function GekkoVanillaBleed(ent, hitPos, hitDir)
    util.Decal("Blood", hitPos - hitDir * 4, hitPos + hitDir * 8, ent)
    local ed = EffectData()
    ed:SetOrigin(hitPos)
    ed:SetNormal(-hitDir)
    util.Effect("BloodImpact", ed, true, true)
end

-- ============================================================
-- SHOULD WE JUICY-BLEED THIS HIT?
-- ============================================================
local function ShouldJuicyBleed(dmginfo)
    if dmginfo:IsDamageType(DMG_BURN)      then return false end
    if dmginfo:IsDamageType(DMG_DROWN)     then return false end
    if dmginfo:IsDamageType(DMG_DISSOLVE)  then return false end
    if dmginfo:IsDamageType(DMG_RADIATION) then return false end
    if dmginfo:GetDamage() <= 0            then return false end
    return true
end

-- ============================================================
-- ON TAKE DAMAGE
-- ORDER OF OPS:
--   1. save/zero damage force (prevent VJ knockback on MOVETYPE_STEP)
--   2. early-exit guards
--   3. compute hitDir BEFORE force is zeroed
--   4. GekkoVanillaBleed + GekkoSignalBloodHit
--   5. GekkoLegs_OnDamage, GekkoGib_OnDamage
--   6. restore force → BaseClass.OnTakeDamage
--      VJ Base writes GetLastDamageHitGroup() during step 6
--   7. GekkoTriggerJuicyBleed(self, dmginfo, hitDir, hitgroup)
-- ============================================================
function ENT:OnTakeDamage(dmginfo)
    if not IsValid(self) or not self:Alive() then return end

    local savedForce = dmginfo:GetDamageForce()
    dmginfo:SetDamageForce(Vector(0,0,0))

    local hitPos = dmginfo:GetDamagePosition()
    if hitPos == vector_origin then
        local inflictor = dmginfo:GetInflictor()
        if IsValid(inflictor) then
            hitPos = inflictor:GetPos()
        else
            dmginfo:SetDamageForce(savedForce)
            self.BaseClass.OnTakeDamage(self, dmginfo)
            return
        end
    end

    -- Head zone damage reduction (above collar)
    local headZ = self:GetPos().z + 155
    if hitPos.z > headZ then dmginfo:ScaleDamage(1 / 3) end

    local rawDmg   = dmginfo:GetDamage()
    local attacker = dmginfo:GetAttacker()

    -- Compute hitDir NOW before anything zeroes it further
    local hitDir = IsValid(attacker)
        and (hitPos - attacker:GetPos()):GetNormalized()
        or self:GetForward()

    GekkoVanillaBleed(self, hitPos, hitDir)

    if dmginfo:IsBulletDamage() then
        GekkoSignalBloodHit(self, hitPos, hitDir)
    end

    self:GekkoLegs_OnDamage(dmginfo)
    self:GekkoGib_OnDamage(rawDmg, dmginfo)

    dmginfo:SetDamageForce(savedForce)
    self.BaseClass.OnTakeDamage(self, dmginfo)
    -- GetLastDamageHitGroup() is only valid AFTER BaseClass runs.
    if ShouldJuicyBleed(dmginfo) and GekkoTriggerJuicyBleed then
        GekkoTriggerJuicyBleed(self, dmginfo, hitDir, self:GetLastDamageHitGroup())
    end
end

-- ============================================================
-- DEATH
-- ============================================================
function ENT:OnDeath(dmginfo, hitgroup, status)
    if self._gekkoSprinting then GekkoSprint_End(self) end
    -- Ragdoll bleed handoff is handled by the CreateEntityRagdoll hook
    -- in gekko_juicy_bleeding.lua — no manual hook.Call needed here.
end
