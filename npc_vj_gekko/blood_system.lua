-- ============================================================
--  GEKKO BLOOD STREAM SYSTEM  (server-side orchestration)
--
--  Ported 1-to-1 from bloodstream.lua / bloodmod_extensions.lua.
--  All ConVars and menu options removed; tunables are locals.
--
--  Integration points (called from init.lua):
--    self:GekkoBlood_OnDamage(dmginfo)   -- inside ENT:OnTakeDamage
--
--  ENT:OnRemove is NOT overridden here.  Cleanup runs via
--  hook.Add("EntityRemoved", ...) to avoid clobbering VJ Base.
--
--  The EFFECT lives at lua/effects/gekko_bloodstream/init.lua.
--  AddCSLuaFile for it is handled by GMod automatically because
--  all files under lua/effects/ are auto-sent to clients.
-- ============================================================

-- ------------------------------------------------------------
--  TUNABLES
-- ------------------------------------------------------------
local BS_COOLDOWN_MIN   = 1.0   -- min seconds between spurts on same entity
local BS_COOLDOWN_MAX   = 2.0   -- max seconds
local BS_DUMMY_LIFETIME = 15    -- seconds before bone-follower prop auto-removes

-- Effect flags passed to "gekko_bloodstream":
--   1  →  burst  (live NPC hit)
--   0  →  stream (ragdoll)
local FLAG_BURST  = 1
local FLAG_STREAM = 0

-- ------------------------------------------------------------
--  PHYSBONE → BONE RESOLVER
--  Mirrors DMGINFO:GetHitPhysBone from bloodmod_extensions.lua.
--
--  CreatePhysCollidesFromModel returns a 1-based Lua table.
--  We do (phys_bone - 1) once inside the loop to convert to
--  the 0-based physbone index that TranslatePhysBoneToBone expects.
--  The returned value is that 0-based index.
-- ------------------------------------------------------------
local _collCache = {}

local function GetHitPhysBone(ent, dmginfo)
    local mdl   = ent:GetModel()
    local colls = _collCache[mdl]
    if not colls then
        colls           = CreatePhysCollidesFromModel(mdl)
        _collCache[mdl] = colls
    end

    local dmgPos      = dmginfo:GetDamagePosition()
    local closestBone = nil
    local closestDist = math.huge

    for physBone1, _ in pairs(colls) do
        -- Convert 1-based Lua key → 0-based physbone index (done once, here)
        local physBone0 = physBone1 - 1
        local bone      = ent:TranslatePhysBoneToBone(physBone0)
        local pos       = ent:GetBonePosition(bone)   -- only pos needed here
        if pos then
            local d = pos:DistToSqr(dmgPos)
            if d < closestDist then
                closestDist = d
                closestBone = physBone0   -- store the 0-based index
            end
        end
    end

    return closestBone   -- 0-based physbone index, or nil
end

-- ------------------------------------------------------------
--  CORE SPAWN HELPER
--  Mirrors do_blood_stream() from bloodstream.lua exactly.
-- ------------------------------------------------------------
local function DoBloodStream(lpos, lang, bone, flags, ent)
    if not IsValid(ent) then return end

    if not ent._gekkoNextBloodStream then
        ent._gekkoNextBloodStream = CurTime()
    end
    if ent._gekkoNextBloodStream > CurTime() then return end
    ent._gekkoNextBloodStream = CurTime() + math.Rand(BS_COOLDOWN_MIN, BS_COOLDOWN_MAX)

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
    dummy:SetLocalPos(lpos - lang:Forward() * -8)   -- exact sign from original

    -- Store bone index so the EFFECT can read it
    dummy.bloodstream_lastdmgbone = bone

    -- Track for cleanup
    if not ent._gekkoBloodDummies then ent._gekkoBloodDummies = {} end
    table.insert(ent._gekkoBloodDummies, dummy)

    local ed = EffectData()
    ed:SetEntity(dummy)
    ed:SetFlags(flags)
    util.Effect("gekko_bloodstream", ed)
end

-- ------------------------------------------------------------
--  ENT:GekkoBlood_OnDamage
--  Called from ENT:OnTakeDamage in init.lua.
-- ------------------------------------------------------------
function ENT:GekkoBlood_OnDamage(dmginfo)
    if not dmginfo:IsBulletDamage() then return end

    local physBone = GetHitPhysBone(self, dmginfo)
    if not physBone then return end

    -- physBone is already 0-based; TranslatePhysBoneToBone expects 0-based
    local bone = self:TranslatePhysBoneToBone(physBone)

    local dmgPos   = dmginfo:GetDamagePosition()
    local dmgForce = dmginfo:GetDamageForce()

    -- WorldToLocal needs both origin AND angle of the reference frame.
    -- GetBonePosition returns (pos, ang) — we need both.
    local bonePos, boneAng = self:GetBonePosition(bone)

    local lpos, lang
    if dmgForce:LengthSqr() > 1 then
        lpos, lang = WorldToLocal(dmgPos, dmgForce:Angle(), bonePos, boneAng)
    else
        lpos, lang = WorldToLocal(dmgPos, Angle(0,0,0), bonePos, boneAng)
    end

    -- Cache for ragdoll inheritance (used by CreateEntityRagdoll hook below)
    self._gekkoBloodLastBone = bone
    self._gekkoBloodLastLPos = lpos
    self._gekkoBloodLastLAng = lang

    DoBloodStream(lpos, lang, bone, FLAG_BURST, self)
end

-- ------------------------------------------------------------
--  Ragdoll inheritance
--  Mirrors BloodStream_ApplyEffect hook from bloodstream.lua.
--  Fires on any ragdoll created from this entity.
-- ------------------------------------------------------------
hook.Add("CreateEntityRagdoll", "GekkoBloodStream_Ragdoll", function(ent, rag)
    if not IsValid(ent) or not IsValid(rag) then return end
    if not ent._gekkoBloodLastLPos then return end

    rag.allownextgen4bloodstreams = true
    DoBloodStream(
        ent._gekkoBloodLastLPos,
        ent._gekkoBloodLastLAng,
        ent._gekkoBloodLastBone,
        FLAG_STREAM,
        rag
    )
end)

-- ------------------------------------------------------------
--  Cleanup via EntityRemoved hook — does NOT override ENT:OnRemove
--  so VJ Base's own cleanup remains intact.
--  Mirrors BloodStream_EntityCleanup hook from bloodstream.lua.
-- ------------------------------------------------------------
hook.Add("EntityRemoved", "GekkoBloodStream_Cleanup", function(ent)
    if not ent._gekkoBloodDummies then return end
    for _, d in ipairs(ent._gekkoBloodDummies) do
        if IsValid(d) then SafeRemoveEntity(d) end
    end
    ent._gekkoBloodDummies = nil
end)
