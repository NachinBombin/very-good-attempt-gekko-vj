-- ============================================================
--  GEKKO BLOOD STREAM SYSTEM  (server-side)
--
--  Replaces the broken gekko_bloodstream EFFECT approach.
--  Instead we net-broadcast GekkoBloodGeyser with a world-space
--  origin + direction so cl_init.lua can run a full geyser burst
--  directly -- no dummy prop, no missing EFFECT file.
-- ============================================================

-- Minimum seconds between geyser net-messages per NPC.
-- Set to 0 to fire on every hit (useful for testing).
local BS_COOLDOWN = 0.18

local FLAG_BURST  = 1
local FLAG_STREAM = 0

-- Network string declared in init.lua via util.AddNetworkString.

-- ------------------------------------------------------------
--  PHYSBONE -> BONE RESOLVER
--  Finds the bone closest to the damage position so the geyser
--  sprays from the actual hit location on the model.
-- ------------------------------------------------------------
local _collCache = {}

local function GetHitBone(ent, dmginfo)
    local mdl   = ent:GetModel()
    local colls = _collCache[mdl]
    if not colls then
        colls           = CreatePhysCollidesFromModel(mdl)
        _collCache[mdl] = colls
    end
    if not colls then return 0 end

    local dmgPos      = dmginfo:GetDamagePosition()
    local closestBone = 0
    local closestDist = math.huge

    for physBone1 in pairs(colls) do
        local physBone0 = physBone1 - 1
        local bone      = ent:TranslatePhysBoneToBone(physBone0)
        local pos       = ent:GetBonePosition(bone)
        if pos then
            local d = pos:DistToSqr(dmgPos)
            if d < closestDist then
                closestDist = d
                closestBone = bone
            end
        end
    end

    return closestBone
end

-- ------------------------------------------------------------
--  NET SEND
--  Sends world-space geyser origin + force direction to all
--  clients.  cl_init.lua receives GekkoBloodGeyser and calls
--  the appropriate BloodVariant_* function.
-- ------------------------------------------------------------
local function SendBloodGeyser(ent, dmginfo, flag)
    local bone    = GetHitBone(ent, dmginfo)
    local bonePos = ent:GetBonePosition(bone)
    if not bonePos then bonePos = ent:GetPos() end

    local dmgForce = dmginfo:GetDamageForce()
    local dir
    if dmgForce:LengthSqr() > 1 then
        dir = dmgForce:GetNormalized()
    else
        -- fallback: spray upward-forward from the hit surface
        dir = (ent:GetForward() + Vector(0, 0, 0.6)):GetNormalized()
    end

    -- Clamp origin to model bounds so it never spawns underground
    local origin = bonePos
    origin.z     = math.max(origin.z, ent:GetPos().z + 20)

    net.Start("GekkoBloodGeyser")
        net.WriteVector(origin)
        net.WriteVector(dir)
        net.WriteUInt(flag, 1)   -- 0 = stream, 1 = burst
    net.Broadcast()

    -- Cache last hit for ragdoll inheritance
    ent._gekkoBloodLastOrigin = origin
    ent._gekkoBloodLastDir    = dir
end

-- ------------------------------------------------------------
--  ENT:GekkoBlood_OnDamage
--  Called from init.lua:OnTakeDamage on every damage event.
--  Gated by a short per-NPC cooldown to avoid spam on
--  rapid-fire weapons (MG bursts etc.).
-- ------------------------------------------------------------
function ENT:GekkoBlood_OnDamage(dmginfo)
    local now = CurTime()
    if now < (self._gekkoNextBloodStream or 0) then return end
    self._gekkoNextBloodStream = now + BS_COOLDOWN

    SendBloodGeyser(self, dmginfo, FLAG_BURST)
end

-- ------------------------------------------------------------
--  Ragdoll inheritance
--  When the Gekko dies and a ragdoll is created, continue a
--  blood stream from the last known hit location.
-- ------------------------------------------------------------
hook.Add("CreateEntityRagdoll", "GekkoBloodStream_Ragdoll", function(ent, rag)
    if not IsValid(ent) or not IsValid(rag)        then return end
    if not ent._gekkoBloodLastOrigin               then return end
    if ent:GetClass() ~= "npc_vj_gekko"            then return end

    -- Synthesise a fake dmginfo-like table for SendBloodGeyser
    -- by directly sending the cached last-hit data.
    net.Start("GekkoBloodGeyser")
        net.WriteVector(ent._gekkoBloodLastOrigin)
        net.WriteVector(ent._gekkoBloodLastDir or Vector(0,0,1))
        net.WriteUInt(FLAG_STREAM, 1)
    net.Broadcast()
end)

-- ------------------------------------------------------------
--  Cleanup  (nothing to clean up now -- no dummy props)
-- ------------------------------------------------------------
