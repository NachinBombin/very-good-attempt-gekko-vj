-- ============================================================
-- npc_vj_gekko / init.lua
-- INTEGRATED WITH: Juicy Bleeding System (gekko_juicy_bleeding.lua)
--                  Leg Disable System    (leg_disable_system.lua)
--                  Gib System            (gib_system.lua)
-- SCOPE: Server-only
-- ============================================================
if CLIENT then return end

include("shared.lua")
include("leg_disable_system.lua")
include("gib_system.lua")

-- ============================================================
-- VJ BASE KEYS
-- ============================================================
ENT.Model                   = {"models/metal_gear_solid_4/enemies/gekko.mdl"}
ENT.StartHealth             = 600
ENT.HullType                = HULL_HUMAN_SMASH
ENT.MoveType_SNPC           = MOVETYPE_STEP
ENT.VJ_IsHumanNPC           = false
ENT.HasDeathAnimation       = false
ENT.AllowedToDissolve       = false
ENT.AllowedToFreeze         = false
ENT.BloodColor              = BLOOD_COLOR_RED
ENT.BloodParticle           = "blood_impact_red_01"
ENT.CanBeFollowedByPlayer   = false
ENT.PrimaryWeapon           = "none"
ENT.HasMeleeAttack          = true
ENT.IsMeleeAttacking        = false
ENT.MeleeAttackDamage       = 40
ENT.MeleeAttackDamageType   = DMG_CLUB
ENT.MeleeAttackKnockBack    = 700
ENT.MeleeDistanceOverride   = 200
ENT.HasRangeAttack          = true
ENT.IsRangeAttacking        = false
ENT.RangeDistance           = 2200
ENT.Bleeds                  = false   -- VJ vanilla bleed is overridden by juicy system
ENT.VJ_ID_Liquid            = FCONTENTS_WATER
ENT.ControllerVars          = {
    ["gekko_juicy_bleeding_enabled"] = 1,
    ["gekko_juicy_bleeding_cooldown"] = 0.15,
    ["gekko_juicy_bleeding_maxactive"] = 8,
    ["gekko_juicy_bleeding_darker"] = 0,
}

-- ============================================================
-- CONVARS
-- ============================================================
CreateConVar("gekko_juicy_bleeding_enabled",  "1",    FCVAR_ARCHIVE, "Enable Gekko juicy bleeding", 0, 1)
CreateConVar("gekko_juicy_bleeding_cooldown", "0.15", FCVAR_ARCHIVE, "Min seconds between bleeds", 0.0, 5.0)
CreateConVar("gekko_juicy_bleeding_maxactive","8",    FCVAR_ARCHIVE, "Max concurrent bleed streams", 1, 20)
CreateConVar("gekko_juicy_bleeding_darker",   "0",    FCVAR_ARCHIVE, "Use darker blood variant", 0, 1)

-- ============================================================
-- BONE LIST DEBUGGER  (run once, prints to console)
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
-- LOCAL AI STATE
-- ============================================================
local MELEE_RANGE        = 200
local MG_BURST_BULLETS   = 12
local MG_BULLET_DELAY    = 0.065
local MG_BURST_COOLDOWN  = 1.8
local SPRINT_SPEED       = 420
local WALK_SPEED         = 200
local SOUND_PAIN_COOLDOWN = 0.6

local function GekkoSprint_Start(ent)
    ent._gekkoSprinting = true
    ent:SetMovementActivity(ACT_RUN)
    ent:SetMaxSpeed(SPRINT_SPEED)
    ent:SetMoveSpeed(SPRINT_SPEED)
    ent:SetNWFloat("GekkoSpeed", SPRINT_SPEED)
end

local function GekkoSprint_End(ent)
    ent._gekkoSprinting = false
    ent:SetMaxSpeed(WALK_SPEED)
    ent:SetMoveSpeed(WALK_SPEED)
    ent:SetNWFloat("GekkoSpeed", WALK_SPEED)
end

-- ============================================================
-- SOUND TABLE
-- ============================================================
local SND_PAIN = {
    "npc/vj_gekko/pain1.wav",
    "npc/vj_gekko/pain2.wav",
    "npc/vj_gekko/pain3.wav",
}
local SND_ALERT = {
    "npc/vj_gekko/alert1.wav",
    "npc/vj_gekko/alert2.wav",
}
local SND_DEATH = {
    "npc/vj_gekko/death1.wav",
    "npc/vj_gekko/death2.wav",
}
local SND_MG   = "npc/vj_gekko/mg_fire.wav"
local SND_FOOT = {
    "npc/vj_gekko/step1.wav",
    "npc/vj_gekko/step2.wav",
    "npc/vj_gekko/step3.wav",
}

-- ============================================================
-- VJ BASE OVERRIDES
-- ============================================================
function ENT:OnEntityInfo()
    GekkoDebugBoneList(self)
    self:SetMaxSpeed(WALK_SPEED)
    self:SetMoveSpeed(WALK_SPEED)
    self:SetNWFloat("GekkoSpeed", WALK_SPEED)
    self:SetNWEntity("GekkoEnemy", NULL)
    self:SetNWBool("GekkoLegsDisabled", false)
    self:SetNWBool("GekkoMGFiring", false)
    self:SetNWInt("GekkoHitReactPulse", 0)
    self:SetNW2String("GekkoHitBoneName", "b_spine3")
    self:SetNW2Vector("GekkoHitDir", Vector(0,1,0))
    self:SetNW2Bool("GekkoHitLarge", false)
    self._mgBurstActive   = false
    self._mgBurstEndT     = 0
    self._mgNextBurst     = 0
    self._lastPainSnd     = 0
    self._gekkoSprinting  = false
    print("[GekkoAI] AI enabled, state ACTIVE")
end

function ENT:VJ_OnThink()
    self:GekkoLegs_Think()

    -- MG burst firing
    if self._mgBurstActive and CurTime() > self._mgBurstEndT then
        self._mgBurstActive = false
        self:SetNWBool("GekkoMGFiring", false)
    end

    -- Sprint toward enemy when far
    local enemy = self:GetEnemy()
    if IsValid(enemy) then
        self:SetNWEntity("GekkoEnemy", enemy)
        local dist = self:GetPos():Distance(enemy:GetPos())
        if dist > 600 and not self._gekkoSprinting then
            GekkoSprint_Start(self)
        elseif dist <= 600 and self._gekkoSprinting then
            GekkoSprint_End(self)
        end
    else
        self:SetNWEntity("GekkoEnemy", NULL)
        if self._gekkoSprinting then GekkoSprint_End(self) end
    end
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
    if dmginfo:IsDamageType(DMG_BURN)     then return false end
    if dmginfo:IsDamageType(DMG_DROWN)    then return false end
    if dmginfo:IsDamageType(DMG_DISSOLVE) then return false end
    if dmginfo:IsDamageType(DMG_RADIATION)then return false end
    if dmginfo:GetDamage() <= 0           then return false end
    return true
end

-- ============================================================
-- ON TAKE DAMAGE
-- ORDER OF OPS:
--   1. save/zero damage force (prevent VJ knockback on MOVETYPE_STEP)
--   2. early-exit: death spiral guard, head zone, hitPos guard
--   3. compute hitDir BEFORE force is zeroed
--   4. GekkoVanillaBleed  (decals/effects)
--   5. GekkoLegs_OnDamage, GekkoGib_OnDamage
--   6. restore force, call BaseClass  <- VJ writes GetLastDamageHitGroup here
--   7. GekkoTriggerJuicyBleed(self, dmginfo, hitDir, hitgroup)
--      hitDir   = already computed in step 3
--      hitgroup = GetLastDamageHitGroup() valid ONLY after step 6
-- ============================================================
function ENT:OnTakeDamage(dmginfo)
    if self._dyingGuard then return end
    if not self:IsAlive() then return end

    local savedForce = dmginfo:GetDamageForce()
    dmginfo:SetDamageForce(Vector(0,0,0))

    -- Early exits that need force restored first
    local function bailout()
        dmginfo:SetDamageForce(savedForce)
        self.BaseClass.OnTakeDamage(self, dmginfo)
    end

    local hitPos = dmginfo:GetDamagePosition()
    if hitPos == vector_origin then
        local inflictor = dmginfo:GetInflictor()
        if IsValid(inflictor) then
            hitPos = inflictor:GetPos()
        else
            bailout(); return
        end
    end

    -- Head zone damage reduction
    local headZ = self:GetPos().z + 155
    if hitPos.z > headZ then dmginfo:ScaleDamage(1 / 3) end

    local rawDmg   = dmginfo:GetDamage()
    local attacker = dmginfo:GetAttacker()
    -- Compute hitDir NOW - before any zeroing logic - from world positions
    local hitDir   = IsValid(attacker)
        and (hitPos - attacker:GetPos()):GetNormalized()
        or self:GetForward()

    GekkoVanillaBleed(self, hitPos, hitDir)

    if rawDmg >= 30 then
        GekkoSignalBloodHit(self, hitPos, -hitDir)
    end

    self:GekkoLegs_OnDamage(dmginfo)
    self:GekkoGib_OnDamage(rawDmg, dmginfo)

    -- Pain sound with cooldown
    if CurTime() > (self._lastPainSnd or 0) then
        self._lastPainSnd = CurTime() + SOUND_PAIN_COOLDOWN
        self:EmitSound(SND_PAIN[math.random(#SND_PAIN)], 75, math.random(95,110))
    end

    dmginfo:SetDamageForce(savedForce)
    self.BaseClass.OnTakeDamage(self, dmginfo)
    -- GetLastDamageHitGroup() is only valid AFTER BaseClass runs.
    if ShouldJuicyBleed(dmginfo) and GekkoTriggerJuicyBleed then
        GekkoTriggerJuicyBleed(self, dmginfo, hitDir, self:GetLastDamageHitGroup())
    end
end

function ENT:OnThink()
    if self._gekkoLegsDisabled then self:GekkoLegs_Think() end
    if self._mgBurstActive and CurTime() > self._mgBurstEndT then
        self._mgBurstActive = false
        self:SetNWBool("GekkoMGFiring", false)
    end
    if self._gekkoSprinting then
        local enemy = self:GetEnemy()
        if not IsValid(enemy) then GekkoSprint_End(self) end
    end
end

-- ============================================================
-- MELEE ATTACK
-- ============================================================
function ENT:MeleeAttack_NormalDamage_Distance()
    return MELEE_RANGE
end

function ENT:OnCallMeleeAttack(traceres)
    if not IsValid(traceres.Entity) then return end
    local dmg = DamageInfo()
    dmg:SetDamage(self.MeleeAttackDamage)
    dmg:SetAttacker(self)
    dmg:SetInflictor(self)
    dmg:SetDamageType(self.MeleeAttackDamageType)
    local dir = (traceres.Entity:GetPos() - self:GetPos()):GetNormalized()
    dmg:SetDamageForce(dir * self.MeleeAttackKnockBack * 100)
    dmg:SetDamagePosition(traceres.HitPos)
    traceres.Entity:TakeDamageInfo(dmg)
end

-- ============================================================
-- RANGE ATTACK  (machine gun burst)
-- ============================================================
function ENT:HasRangeAttack_Check()
    if self._mgBurstActive then return false end
    if CurTime() < self._mgNextBurst then return false end
    local enemy = self:GetEnemy()
    if not IsValid(enemy) then return false end
    return self:GetPos():Distance(enemy:GetPos()) <= self.RangeDistance
end

function ENT:OnCallRangeAttack()
    local enemy = self:GetEnemy()
    if not IsValid(enemy) then return end
    self._mgBurstActive = true
    self._mgBurstEndT   = CurTime() + MG_BURST_BULLETS * MG_BULLET_DELAY
    self._mgNextBurst   = self._mgBurstEndT + MG_BURST_COOLDOWN
    self:SetNWBool("GekkoMGFiring", true)
    self:EmitSound(SND_MG, 75, 100)
    for i = 1, MG_BURST_BULLETS do
        timer.Simple((i - 1) * MG_BULLET_DELAY, function()
            if not IsValid(self) then return end
            if not IsValid(self:GetEnemy()) then return end
            self:FireBullets({
                Attacker  = self,
                Damage    = 8,
                Force     = 600,
                Num       = 1,
                Spread    = Vector(0.05, 0.05, 0),
                Tracer    = 1,
                Dir       = (self:GetEnemy():EyePos() - self:GetShootPos()):GetNormalized(),
                Src       = self:GetShootPos(),
            })
        end)
    end
end

-- ============================================================
-- FOOTSTEP SOUNDS
-- ============================================================
function ENT:OnFootstepSound()
    self:EmitSound(SND_FOOT[math.random(#SND_FOOT)], 70, math.random(90,115))
end

-- ============================================================
-- DEATH
-- ============================================================
function ENT:OnDeath(dmginfo, hitgroup, status)
    self._dyingGuard = true
    if self._gekkoSprinting then GekkoSprint_End(self) end
    self:SetNWBool("GekkoMGFiring", false)
    self:EmitSound(SND_DEATH[math.random(#SND_DEATH)], 80, math.random(95, 110))

    -- Allow the server ragdoll to receive bleed handoff via hooks
    -- hook.Call("GekkoRagdollSpawned") is fired by CreateEntityRagdoll
    -- listener already in gekko_juicy_bleeding.lua
end
