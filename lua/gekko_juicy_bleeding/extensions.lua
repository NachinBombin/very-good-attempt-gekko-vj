-- ============================================================
-- FILE: lua/gekko_juicy_bleeding/extensions.lua
-- PURPOSE: Extends CTakeDamageInfo metatable with bone-detection
--          helpers used by both the live-NPC and ragdoll bleed paths.
-- SCOPE: Shared (loaded server-side by autorun; sent to client via
--        AddCSLuaFile in gekko_juicy_bleeding.lua)
-- Code reference: Custom Blood Bleeding 3332958092
--                 Universal SMOD Bleeding Effect 2840303209
-- ============================================================

local DMGINFO = FindMetaTable("CTakeDamageInfo")

local COLL_CACHE = {}

local vec_max = Vector(1, 1, 1)
local vec_min = -vec_max

-- NPCs whose physmesh layout doesn't suit bone-level bleeding.
local blacklist_npcs = {
    "npc_turret_floor",
    "npc_rollermine",
    "npc_barnacle",
    "npc_turret_ceiling",
    "npc_manhack",
    "npc_cscanner",
    "npc_combine_camera",
    "npc_clawscanner",
    "npc_strider",
    "npc_zombie",
    "npc_zombie_torso",
    "npc_fastzombie",
    "npc_fastzombie_torso",
    "npc_poisonzombie",
    "npc_zombine",
    "npc_dog",
}

local function OFBleeding_ISNPCBlacklisted(ent)
    return table.HasValue(blacklist_npcs, ent:GetClass())
end

local function nearest_bone_to_pos(ent, world_pos, fallback_bone)
    local nearest_bone     = nil
    local nearest_dist_sqr = math.huge
    local bone_count       = ent:GetBoneCount() or 0

    for b = 0, bone_count - 1 do
        local bone_pos = ent:GetBonePosition(b)
        if isvector(bone_pos) then
            local dist_sqr = bone_pos:DistToSqr(world_pos)
            if dist_sqr < nearest_dist_sqr then
                nearest_dist_sqr = dist_sqr
                nearest_bone     = b
            end
        end
    end

    return nearest_bone or fallback_bone
end

-- Returns the physics-bone index closest to the damage origin,
-- or nil if the entity is blacklisted / has no valid model.
function DMGINFO:GetHitPhysBone(ent)
    if OFBleeding_ISNPCBlacklisted(ent) then return nil end

    local mdl = ent:GetModel()
    if not mdl or mdl == "" then return nil end

    local colls = COLL_CACHE[mdl]
    if not colls then
        colls = CreatePhysCollidesFromModel(mdl)
        if not colls then return nil end
        COLL_CACHE[mdl] = colls
    end

    local dmgpos = self:GetDamagePosition()
    local dmgdir = self:GetDamageForce()
    if not isvector(dmgpos) then return nil end
    if not isvector(dmgdir) or dmgdir:LengthSqr() <= 0 then
        dmgdir = ent:GetForward()
    end
    dmgdir:Normalize()

    local ray_start = dmgpos - dmgdir * 50
    local ray_end   = dmgpos + dmgdir * 50

    for phys_bone, coll in pairs(colls) do
        if coll then
            phys_bone = phys_bone - 1
            local bone = ent:TranslatePhysBoneToBone(phys_bone)
            if not bone or bone < 0 then continue end

            local pos, ang = ent:GetBonePosition(bone)
            if pos ~= nil and ang ~= nil then
                local ok, result = pcall(function()
                    return coll:TraceBox(pos, ang, ray_start, ray_end, vec_min, vec_max)
                end)
                if ok and result then
                    return phys_bone
                end
            end
        end
    end

    -- No phys-bone hit: fall back to the bone nearest the damage position.
    -- This ensures we always return something useful rather than nil.
    local bone_count = ent:GetBoneCount() or 0
    if bone_count > 0 then
        return nil  -- Caller must handle nil; nearest_bone_to_pos used in GetAnimBone.
    end
end

-- Returns the animation bone index for the hit location.
-- This is what OFBleeding_DO / GekkoTriggerJuicyBleed uses for FollowBone.
function DMGINFO:GetAnimBone(ent)
    local phys_bone = self:GetHitPhysBone(ent)

    -- If no phys bone hit (e.g. close-range, overlapping geometry),
    -- fall back to the animation bone nearest the damage position.
    if phys_bone == nil then
        return nearest_bone_to_pos(ent, self:GetDamagePosition(), 0)
    end

    local fallback_bone = ent:TranslatePhysBoneToBone(phys_bone)
    return nearest_bone_to_pos(ent, self:GetDamagePosition(), fallback_bone)
end
