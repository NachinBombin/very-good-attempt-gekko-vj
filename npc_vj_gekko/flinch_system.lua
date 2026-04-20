if SERVER then AddCSLuaFile() end

local FLINCH_DEFAULT_DURATION = 0.32
local FLINCH_FADEIN = 0.07
local FLINCH_FADEOUT = 0.18
local FLINCH_COOLDOWN = 0.18
local FLINCH_CHANCE = 1

local HITGROUP_TO_PROFILE = {
    [HITGROUP_HEAD] = {
        duration = 0.22,
        fadeIn = 0.04,
        fadeOut = 0.16,
        pelvis = Angle(-8, 0, 0),
        spine = Angle(-18, 0, 0),
        neck = Angle(10, 0, 0),
    },
    [HITGROUP_CHEST] = {
        duration = 0.30,
        fadeIn = 0.06,
        fadeOut = 0.18,
        pelvis = Angle(4, 0, 0),
        spine = Angle(-12, 0, 0),
        neck = Angle(4, 0, 0),
    },
    [HITGROUP_STOMACH] = {
        duration = 0.34,
        fadeIn = 0.06,
        fadeOut = 0.20,
        pelvis = Angle(12, 0, 0),
        spine = Angle(-7, 0, 0),
        neck = Angle(0, 0, 0),
    },
    [HITGROUP_LEFTARM] = {
        duration = 0.28,
        fadeIn = 0.05,
        fadeOut = 0.18,
        lhip = Angle(-10, -8, 8),
        rhip = Angle(6, 0, 0),
        spine = Angle(-6, -8, 0),
    },
    [HITGROUP_RIGHTARM] = {
        duration = 0.28,
        fadeIn = 0.05,
        fadeOut = 0.18,
        lhip = Angle(6, 0, 0),
        rhip = Angle(-10, 8, -8),
        spine = Angle(-6, 8, 0),
    },
    [HITGROUP_LEFTLEG] = {
        duration = 0.33,
        fadeIn = 0.06,
        fadeOut = 0.20,
        lhip = Angle(18, -10, 18),
        rhip = Angle(-6, 0, 0),
        pelvis = Angle(2, -4, 0),
    },
    [HITGROUP_RIGHTLEG] = {
        duration = 0.33,
        fadeIn = 0.06,
        fadeOut = 0.20,
        lhip = Angle(-6, 0, 0),
        rhip = Angle(18, 10, -18),
        pelvis = Angle(2, 4, 0),
    },
    default = {
        duration = FLINCH_DEFAULT_DURATION,
        fadeIn = FLINCH_FADEIN,
        fadeOut = FLINCH_FADEOUT,
        pelvis = Angle(6, 0, 0),
        spine = Angle(-8, 0, 0),
    }
}

-- These flags always suppress flinch, checked with bitmask (bit.band).
-- DMG_BULLET, DMG_CRUSH (physical bullets), DMG_CLUB, DMG_SLASH etc. are
-- intentionally NOT here so physical bullet addons work correctly.
local BANNED_DMG_FLAGS = {
    DMG_BURN,
    DMG_SLOWBURN,
    DMG_FALL,
    DMG_RADIATION,
    DMG_PARALYZE,
    DMG_POISON,
    DMG_DROWN,
    DMG_DROWNRECOVER,
    DMG_NERVEGAS,
}

local function IsTargetDmgType(dmginfo)
    local dmgBits = dmginfo:GetDamageType()
    for _, flag in ipairs(BANNED_DMG_FLAGS) do
        if bit.band(dmgBits, flag) ~= 0 then return false end
    end
    return true
end

local function Smoothstep(t)
    t = math.Clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

local function LerpAngleLinear(t, a, b)
    return Angle(
        Lerp(t, a.p, b.p),
        Lerp(t, a.y, b.y),
        Lerp(t, a.r, b.r)
    )
end

local function EnsureFlinchCache(ent)
    if ent._gekkoFlinchCache then return ent._gekkoFlinchCache end

    ent._gekkoFlinchCache = {
        pelvis = ent:LookupBone("b_pelvis")        or -1,
        spine  = ent:LookupBone("b_spine3")        or -1,
        neck   = ent:LookupBone("b_spine4")        or -1,
        lhip   = ent:LookupBone("b_l_hippiston1")  or -1,
        rhip   = ent:LookupBone("b_r_hippiston1")  or -1,
    }

    return ent._gekkoFlinchCache
end

local function GetHitgroupFromDamage(ent, dmginfo)
    -- LastHitGroup is a plain number field on NPCs, NOT a method.
    local hg = ent.LastHitGroup
    if type(hg) == "number" and hg ~= HITGROUP_GENERIC then return hg end

    -- Fallback: estimate hitgroup from damage position.
    local hitPos = dmginfo:GetDamagePosition()
    if not hitPos or hitPos == vector_origin then return HITGROUP_GENERIC end

    local _, maxs = ent:GetCollisionBounds()
    local localPos = ent:WorldToLocal(hitPos)
    local z        = localPos.z
    local centerX  = localPos.x

    local headLine    = maxs.z * 0.72
    local chestLine   = maxs.z * 0.45
    local stomachLine = maxs.z * 0.24

    if z >= headLine then return HITGROUP_HEAD end
    if z >= chestLine then
        if centerX > 22  then return HITGROUP_RIGHTARM end
        if centerX < -22 then return HITGROUP_LEFTARM  end
        return HITGROUP_CHEST
    end
    if z >= stomachLine then return HITGROUP_STOMACH end
    if centerX >= 0 then return HITGROUP_RIGHTLEG end
    return HITGROUP_LEFTLEG
end

local function BuildPose(profile)
    return {
        pelvis = profile.pelvis or angle_zero,
        spine  = profile.spine  or angle_zero,
        neck   = profile.neck   or angle_zero,
        lhip   = profile.lhip   or angle_zero,
        rhip   = profile.rhip   or angle_zero,
    }
end

local function ApplyBoneAngle(ent, boneId, ang)
    if boneId and boneId >= 0 then
        ent:ManipulateBoneAngles(boneId, ang, false)
    end
end

function GekkoFlinch_OnDamage(ent, dmginfo)
    if not IsValid(ent) then return end
    if not ent:Alive() then return end
    if ent._deathPoseActive then return end
    if ent._gekkoLegsDisabled then return end
    if not IsTargetDmgType(dmginfo) then return end
    if math.Rand(0, 1) > FLINCH_CHANCE then return end

    local now = CurTime()
    if now < (ent._gekkoNextFlinchTime or 0) then return end

    local hitgroup = GetHitgroupFromDamage(ent, dmginfo)
    local profile  = HITGROUP_TO_PROFILE[hitgroup] or HITGROUP_TO_PROFILE.default

    ent._gekkoFlinch = {
        startTime = now,
        duration  = profile.duration or FLINCH_DEFAULT_DURATION,
        fadeIn    = profile.fadeIn   or FLINCH_FADEIN,
        fadeOut   = profile.fadeOut  or FLINCH_FADEOUT,
        pose      = BuildPose(profile),
        hitgroup  = hitgroup,
    }

    ent._gekkoNextFlinchTime = now + math.max(profile.duration or FLINCH_DEFAULT_DURATION, FLINCH_COOLDOWN)
    ent.Flinching = true
end

function GekkoFlinch_Think(ent)
    if not IsValid(ent) then return end

    local fl = ent._gekkoFlinch
    if not fl then
        ent.Flinching = false
        return
    end

    local cache    = EnsureFlinchCache(ent)
    local elapsed  = CurTime() - fl.startTime
    local duration = math.max(fl.duration or FLINCH_DEFAULT_DURATION, 0.001)

    if elapsed >= duration then
        ApplyBoneAngle(ent, cache.pelvis, angle_zero)
        ApplyBoneAngle(ent, cache.spine,  angle_zero)
        ApplyBoneAngle(ent, cache.neck,   angle_zero)
        ApplyBoneAngle(ent, cache.lhip,   angle_zero)
        ApplyBoneAngle(ent, cache.rhip,   angle_zero)
        ent._gekkoFlinch = nil
        ent.Flinching = false
        return
    end

    local weight
    if elapsed < fl.fadeIn then
        weight = Smoothstep(elapsed / math.max(fl.fadeIn, 0.001))
    elseif elapsed > (duration - fl.fadeOut) then
        weight = Smoothstep((duration - elapsed) / math.max(fl.fadeOut, 0.001))
    else
        weight = 1
    end

    local pose = fl.pose
    ApplyBoneAngle(ent, cache.pelvis, LerpAngleLinear(weight, angle_zero, pose.pelvis))
    ApplyBoneAngle(ent, cache.spine,  LerpAngleLinear(weight, angle_zero, pose.spine))
    ApplyBoneAngle(ent, cache.neck,   LerpAngleLinear(weight, angle_zero, pose.neck))
    ApplyBoneAngle(ent, cache.lhip,   LerpAngleLinear(weight, angle_zero, pose.lhip))
    ApplyBoneAngle(ent, cache.rhip,   LerpAngleLinear(weight, angle_zero, pose.rhip))
    ent.Flinching = true
end
