-- ============================================================
--  gekko_bloodstream.lua
--  Blood stream for VJ Gekko.
--
--  ParticleEmitter abandoned: every material tried rendered
--  as black squares on target system.
--
--  Instead we fire util.Effect("BloodSpray") + "BloodImpact"
--  in rapid bursts from random bone positions.
--  These are the SAME built-in effects used by the other five
--  blood variants in cl_init — guaranteed to render correctly.
--  Zero custom materials. 100% stock GMod.
-- ============================================================

-- ============================================================
--  BONE EMISSION POINTS
-- ============================================================
local EMISSION_BONES = {
    "b_spine3",
    "b_pelvis",
    "b_pedestal",
    "b_r_hippiston1",
    "b_l_hippiston1",
}

local TORSO_Z = 80   -- fallback height when bone lookup fails

local function GetEmissionPos(ent)
    local boneName = EMISSION_BONES[math.random(#EMISSION_BONES)]
    local boneIdx  = ent:LookupBone(boneName)
    if boneIdx and boneIdx >= 0 then
        local bmat = ent:GetBoneMatrix(boneIdx)
        if bmat then
            return bmat:GetTranslation() + Vector(
                math.Rand(-12, 12),
                math.Rand(-12, 12),
                math.Rand(-6,   6)
            )
        end
    end
    return ent:GetPos() + Vector(
        math.Rand(-15, 15),
        math.Rand(-15, 15),
        TORSO_Z
    )
end

-- ============================================================
--  STREAM SETTINGS
-- ============================================================
local STREAM_REPS      = 40     -- number of bursts
local STREAM_INTERVAL  = 0.06   -- seconds between bursts (~17Hz)
local SPRAY_SCALE_MIN  = 3
local SPRAY_SCALE_MAX  = 6
local SPRAY_MAG_MIN    = 8
local SPRAY_MAG_MAX    = 18
local IMPACT_SCALE_MIN = 4
local IMPACT_SCALE_MAX = 8

-- ============================================================
--  EFFECT
-- ============================================================
function EFFECT:Init(data)
    local ent = data:GetEntity()

    print("[GekkoBloodstream] Init — ent valid: " .. tostring(IsValid(ent)))

    if not IsValid(ent) then return end

    self.TimerName = "GekkoBloodStream_" .. ent:EntIndex() .. "_" .. math.floor(CurTime() * 1000)

    timer.Create(self.TimerName, STREAM_INTERVAL, STREAM_REPS, function()
        if not IsValid(ent) then
            timer.Remove(self.TimerName)
            return
        end

        local pos = GetEmissionPos(ent)
        local fwd = ent:GetForward()

        -- Direction: mostly away from NPC forward, slight upward arc
        local dir = (fwd * -1 + Vector(
            math.Rand(-0.4, 0.4),
            math.Rand(-0.4, 0.4),
            math.Rand(0.05, 0.4)
        )):GetNormalized()

        -- BloodSpray: travelling blood droplets
        local eSpray = EffectData()
        eSpray:SetOrigin(pos)
        eSpray:SetNormal(dir)
        eSpray:SetScale(math.Rand(SPRAY_SCALE_MIN, SPRAY_SCALE_MAX))
        eSpray:SetMagnitude(math.Rand(SPRAY_MAG_MIN, SPRAY_MAG_MAX))
        util.Effect("BloodSpray", eSpray, false)

        -- BloodImpact: burst cloud at emission point
        local eImpact = EffectData()
        eImpact:SetOrigin(pos)
        eImpact:SetNormal(dir)
        eImpact:SetScale(math.Rand(IMPACT_SCALE_MIN, IMPACT_SCALE_MAX))
        eImpact:SetMagnitude(math.Rand(4, 10))
        util.Effect("BloodImpact", eImpact, false)
    end)
end

function EFFECT:Think()  return false end
function EFFECT:Render() end
