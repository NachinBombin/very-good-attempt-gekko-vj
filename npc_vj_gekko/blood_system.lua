-- ============================================================
--  GEKKO BLOOD STREAM SYSTEM  (server-side)  [DEBUG BUILD]
--  Changes vs normal:
--    - No cooldown (fires every single damage event)
--    - Fires on ALL damage types, not just bullet
--    - Falls back to entity origin if bone resolve fails
--    - Prints to server console on every trigger
-- ============================================================

-- DEBUG: cooldown completely disabled
local BS_COOLDOWN_MIN   = 0
local BS_COOLDOWN_MAX   = 0
local BS_DUMMY_LIFETIME = 30   -- DEBUG: dummy lives longer

local FLAG_BURST  = 1
local FLAG_STREAM = 0

-- ------------------------------------------------------------
--  PHYSBONE -> BONE RESOLVER
-- ------------------------------------------------------------
local _collCache = {}

local function GetHitPhysBone(ent, dmginfo)
    local mdl   = ent:GetModel()
    local colls = _collCache[mdl]
    if not colls then
        colls           = CreatePhysCollidesFromModel(mdl)
        _collCache[mdl] = colls
    end
    if not colls then return nil end

    local dmgPos      = dmginfo:GetDamagePosition()
    local closestBone = nil
    local closestDist = math.huge

    for physBone1, _ in pairs(colls) do
        local physBone0 = physBone1 - 1
        local bone      = ent:TranslatePhysBoneToBone(physBone0)
        local pos       = ent:GetBonePosition(bone)
        if pos then
            local d = pos:DistToSqr(dmgPos)
            if d < closestDist then
                closestDist = d
                closestBone = physBone0
            end
        end
    end

    return closestBone
end

-- ------------------------------------------------------------
--  CORE SPAWN HELPER
-- ------------------------------------------------------------
local function DoBloodStream(lpos, lang, bone, flags, ent)
    if not IsValid(ent) then return end

    -- DEBUG: no cooldown gate
    ent._gekkoNextBloodStream = 0

    local dummy = ents.Create("prop_dynamic")
    if not IsValid(dummy) then
        print("[GekkoBlood DEBUG] prop_dynamic creation failed")
        return
    end
    dummy:SetModel("models/error.mdl")
    dummy:Spawn()
    dummy:SetModelScale(0)
    dummy:SetNotSolid(true)
    dummy:DrawShadow(false)
    SafeRemoveEntityDelayed(dummy, BS_DUMMY_LIFETIME)

    dummy:FollowBone(ent, bone)
    dummy:SetLocalAngles(lang)
    dummy:SetLocalPos(lpos - lang:Forward() * -8)

    dummy.bloodstream_lastdmgbone = bone

    if not ent._gekkoBloodDummies then ent._gekkoBloodDummies = {} end
    table.insert(ent._gekkoBloodDummies, dummy)

    print("[GekkoBlood DEBUG] util.Effect fired | ent:", ent, "| bone:", bone, "| flags:", flags, "| dummy:", dummy)

    local ed = EffectData()
    ed:SetEntity(dummy)
    ed:SetFlags(flags)
    util.Effect("gekko_bloodstream", ed)
end

-- ------------------------------------------------------------
--  ENT:GekkoBlood_OnDamage
--  DEBUG: fires on ANY damage, falls back to bone 0 / entity pos
--  if normal bone resolve fails.
-- ------------------------------------------------------------
function ENT:GekkoBlood_OnDamage(dmginfo)
    -- DEBUG: removed bullet-only filter
    print("[GekkoBlood DEBUG] OnDamage called | dmg:", dmginfo:GetDamage(), "| type:", dmginfo:GetDamageType())

    local physBone = GetHitPhysBone(self, dmginfo)

    local bone
    if physBone then
        bone = self:TranslatePhysBoneToBone(physBone)
    else
        -- DEBUG fallback: use bone 0 so the effect still fires
        print("[GekkoBlood DEBUG] bone resolve failed, falling back to bone 0")
        bone = 0
    end

    local dmgPos   = dmginfo:GetDamagePosition()
    local dmgForce = dmginfo:GetDamageForce()

    local bonePos, boneAng = self:GetBonePosition(bone)
    -- DEBUG fallback if GetBonePosition returns nil
    if not bonePos then
        bonePos = self:GetPos()
        boneAng = self:GetAngles()
        print("[GekkoBlood DEBUG] GetBonePosition nil, using entity origin")
    end

    local lpos, lang
    if dmgForce:LengthSqr() > 1 then
        lpos, lang = WorldToLocal(dmgPos, dmgForce:Angle(), bonePos, boneAng)
    else
        lpos, lang = WorldToLocal(dmgPos, Angle(0,0,0), bonePos, boneAng)
    end

    self._gekkoBloodLastBone = bone
    self._gekkoBloodLastLPos = lpos
    self._gekkoBloodLastLAng = lang

    DoBloodStream(lpos, lang, bone, FLAG_BURST, self)
end

-- ------------------------------------------------------------
--  Ragdoll inheritance
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
--  Cleanup
-- ------------------------------------------------------------
hook.Add("EntityRemoved", "GekkoBloodStream_Cleanup", function(ent)
    if not ent._gekkoBloodDummies then return end
    for _, d in ipairs(ent._gekkoBloodDummies) do
        if IsValid(d) then SafeRemoveEntity(d) end
    end
    ent._gekkoBloodDummies = nil
end)
