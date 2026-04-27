-- ============================================================
--  GEKKO BLOOD STREAM SYSTEM  (server-side orchestration)
--
--  Ported 1-to-1 from bloodstreameffectzippy / bloodstream.lua
--  by NachinBombin.  All ConVars and menu options removed;
--  tunables are hardcoded locals below.
--
--  Integration points (called from init.lua):
--    self:GekkoBlood_OnDamage(dmginfo)   -- inside ENT:OnTakeDamage
--    self:GekkoBlood_OnRemove()          -- inside ENT:OnRemove
--
--  The actual particle emitter lives in blood_effect_cl.lua
--  which is registered as effect "gekko_bloodstream".
-- ============================================================

AddCSLuaFile("blood_effect_cl.lua")

-- ------------------------------------------------------------
--  TUNABLES  (replaces ConVars from the original addon)
-- ------------------------------------------------------------
local BS_COOLDOWN_MIN   = 1.0   -- min seconds between spurts on the same hit bone
local BS_COOLDOWN_MAX   = 2.0   -- max seconds
local BS_DUMMY_LIFETIME = 15    -- seconds before the bone-follower prop is removed

-- Effect flags passed to "gekko_bloodstream" EFFECT:
--   flags == 1  →  burst  (on live NPC hit)
--   flags == 0  →  stream (on ragdoll)
local FLAG_BURST  = 1
local FLAG_STREAM = 0

-- ============================================================
--  PHYSBONE → BONE RESOLVER
--  Inlined from bloodmod_extensions.lua
--  Finds the physics bone closest to the damage position.
-- ============================================================
local _collCache = {}

local function GetHitPhysBone(ent, dmginfo)
    local mdl   = ent:GetModel()
    local colls = _collCache[mdl]
    if not colls then
        colls = CreatePhysCollidesFromModel(mdl)
        _collCache[mdl] = colls
    end

    local dmgPos       = dmginfo:GetDamagePosition()
    local closestBone  = nil
    local closestDist  = math.huge

    for physBone, _ in pairs(colls) do
        local bone = ent:TranslatePhysBoneToBone(physBone - 1)
        local pos  = ent:GetBonePosition(bone)
        if pos then
            local d = pos:DistToSqr(dmgPos)
            if d < closestDist then
                closestDist = d
                closestBone = physBone - 1
            end
        end
    end

    return closestBone
end

-- ============================================================
--  CORE SPAWN HELPER
--  Mirrors do_bloodstream() from bloodstream.lua exactly.
--  Creates an invisible bone-following prop_dynamic, then
--  fires the client effect "gekko_bloodstream" on it.
-- ============================================================
local function DoBloodStream(lpos, lang, bone, flags, ent)
    if not IsValid(ent) then return end

    -- Cooldown guard (per-entity)
    if not ent._gekkoNextBloodStream then
        ent._gekkoNextBloodStream = CurTime()
    end
    if ent._gekkoNextBloodStream > CurTime() then return end
    ent._gekkoNextBloodStream = CurTime() + math.Rand(BS_COOLDOWN_MIN, BS_COOLDOWN_MAX)

    -- Invisible bone-following dummy (same trick as original)
    local dummy = ents.Create("prop_dynamic")
    if not IsValid(dummy) then return end
    dummy:SetModel("models/error.mdl")
    dummy:Spawn()
    dummy:SetModelScale(0)
    dummy:SetNotSolid(true)
    dummy:DrawShadow(false)
    SafeRemoveEntityDelayed(dummy, BS_DUMMY_LIFETIME)
    dummy:FollowBone(ent, bone)
    dummy:SetLocalAngles(lang)
    dummy:SetLocalPos(lpos - lang:Forward() * 8)

    -- Store hit bone so the effect can read it for limb multipliers
    dummy.bloodstreamlastdmgbone = bone

    -- Track for cleanup
    if not ent._gekkoBloodDummies then ent._gekkoBloodDummies = {} end
    table.insert(ent._gekkoBloodDummies, dummy)

    -- Fire the client effect
    local ed = EffectData()
    ed:SetEntity(dummy)
    ed:SetFlags(flags)
    util.Effect("gekko_bloodstream", ed)
end

-- ============================================================
--  ENT:GekkoBlood_OnDamage
--  Call from ENT:OnTakeDamage(dmginfo)
-- ============================================================
function ENT:GekkoBlood_OnDamage(dmginfo)
    -- Only bullet damage triggers a spurt (mirrors original addon logic)
    if not dmginfo:IsBulletDamage() then return end

    local physBone = GetHitPhysBone(self, dmginfo)
    if not physBone then return end

    local bone = self:TranslatePhysBoneToBone(physBone)
    local dmgPos  = dmginfo:GetDamagePosition()
    local dmgForce = dmginfo:GetDamageForce()
    -- Derive a world angle from the force vector (same as original)
    local lang, lpos
    if dmgForce:LengthSqr() > 1 then
        lpos, lang = WorldToLocal(dmgPos, dmgForce:Angle(), self:GetBonePosition(bone))
    else
        lpos = self:WorldToLocal(dmgPos)
        lang = Angle(0, 0, 0)
    end

    -- Store last-hit info so ragdoll can inherit it
    self._gekkoBloodLastBone = bone
    self._gekkoBloodLastLPos = lpos
    self._gekkoBloodLastLAng = lang

    DoBloodStream(lpos, lang, bone, FLAG_BURST, self)
end

-- ============================================================
--  ENT:GekkoBlood_OnDeath
--  Call from ENT:OnDeath  so the ragdoll inherits the stream.
--  Pass the ragdoll entity once it's valid.
-- ============================================================
function ENT:GekkoBlood_OnDeath(ragdoll)
    if not IsValid(ragdoll) then return end
    if not self._gekkoBloodLastLPos then return end
    ragdoll.allownextgen4bloodstreams = true
    DoBloodStream(
        self._gekkoBloodLastLPos,
        self._gekkoBloodLastLAng,
        self._gekkoBloodLastBone,
        FLAG_STREAM,
        ragdoll
    )
end

-- ============================================================
--  ENT:GekkoBlood_OnRemove
--  Call from ENT:OnRemove / cleanup
-- ============================================================
function ENT:GekkoBlood_OnRemove()
    if self._gekkoBloodDummies then
        for _, d in ipairs(self._gekkoBloodDummies) do
            if IsValid(d) then SafeRemoveEntity(d) end
        end
        self._gekkoBloodDummies = nil
    end
end
