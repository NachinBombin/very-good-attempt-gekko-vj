-- lua/effects/gekko_bloodstream_fx.lua
-- Standalone port of Hemo-fluid-stream bloodstreameffectzippy.lua
-- Self-contained: no external addon dependency.

-- ============================================================
--  LIMB MULTIPLIER
-- ============================================================
local function GetLimbMultiplierForBone(boneName)
    if not boneName then return 1 end
    boneName = string.lower(boneName)
    if string.find(boneName, "head")                                                     then return 2.5  end
    if string.find(boneName, "neck")                                                     then return 2.0  end
    if string.find(boneName, "clavicle") or string.find(boneName, "upperarm") or
       string.find(boneName, "forearm")  or string.find(boneName, "wrist")   or
       string.find(boneName, "hand")                                                     then return 1.2  end
    if string.find(boneName, "thigh")    or string.find(boneName, "calf")    or
       string.find(boneName, "foot")     or string.find(boneName, "toe")                then return 1.2  end
    return 1.0
end

-- ============================================================
--  MATERIALS  (exact same paths as original)
-- ============================================================
local function make_materials(tbl)
    local out = {}
    for _, v in ipairs(tbl) do
        table.insert(out, Material(v))
    end
    return out
end

local particle_mats = make_materials({ "decals/trail" })

local decal_mats = make_materials({
    "decals/Blood1",
    "decals/Blood3",
    "decals/Blood4",
    "decals/Blood5",
    "decals/Blood6",
    "decals/Blood2",
    "decals/Blood3",
})

-- ============================================================
--  SOUNDS  (vanilla HL2 fallbacks; Hemo sounds unavailable standalone)
-- ============================================================
local drip_sounds = {
    "physics/flesh/flesh_squishy_impact_hard1.wav",
    "physics/flesh/flesh_squishy_impact_hard2.wav",
    "physics/flesh/flesh_squishy_impact_hard3.wav",
    "physics/flesh/flesh_squishy_impact_hard4.wav",
}

local squrt_sounds = {
    "physics/flesh/flesh_impact_bullet1.wav",
    "physics/flesh/flesh_impact_bullet2.wav",
    "physics/flesh/flesh_impact_bullet3.wav",
    "physics/flesh/flesh_impact_bullet4.wav",
    "physics/flesh/flesh_impact_bullet5.wav",
}

-- ============================================================
--  PARTICLE CONSTANTS  (identical to original)
-- ============================================================
local particle_length_random     = { min = 100, max = 100 }
local particle_start_lengt_mult  = 0.1
local particle_scale             = 0.4
local particle_gravity           = 1050
local particle_force             = 200
local particle_pulsate_max_force = 100
local particle_pulsate_speed_mult= 8
local particle_reps_stream       = 300
local particle_reps_burst        = 150
local particle_fps               = 60
local particle_lifetime          = 8
local decal_scale                = 0.2
local sound_level                = 70
local sound_level2               = 35
local min_strenght               = 0.25
local impact_chance              = 1
local stream_spread              = 5

-- ============================================================
--  EFFECT
--  NOTE: do NOT declare "local EFFECT = {}" here.
--  GMod sets EFFECT as a global before loading this file and
--  auto-registers it by filename after load. A local would shadow
--  that global, causing the framework to overwrite our table
--  with an empty one.
-- ============================================================

function EFFECT:Init(data)
    local ent = data:GetEntity()
    if not IsValid(ent) then return end

    local flags     = data:GetFlags()
    self.reps       = (flags == 1) and particle_reps_burst or particle_reps_stream

    local boneName = ""
    if ent.bloodstream_lastdmgbone then
        boneName = ent:GetBoneName(ent.bloodstream_lastdmgbone) or ""
    end
    local limb_mult  = GetLimbMultiplierForBone(boneName)
    local force_mult = 1.0 * limb_mult
    local density    = 1.0 / limb_mult

    local spurt_delay = math.Rand(0.5, 5) / (particle_fps * density)

    self.StartTime       = CurTime()
    self.CurrentPos      = ent:GetPos()
    self.CurrentStrenght = 1
    self:UpdateExtraForce()

    self.timername = "GekkoBloodStream_" .. ent:EntIndex() .. "_" .. CurTime()

    local emitter = ParticleEmitter(self.CurrentPos, false)
    if not emitter then return end

    sound.Play(table.Random(squrt_sounds), ent:GetPos(), sound_level2, math.Rand(95, 105))

    local effect_self = self
    local reps        = self.reps
    local timername   = self.timername

    timer.Create(timername, spurt_delay, reps, function()
        if not IsValid(ent) then
            emitter:Finish()
            timer.Remove(timername)
            return
        end

        sound.Play(table.Random(squrt_sounds), ent:GetPos(), sound_level2, math.Rand(95, 105))

        ent.CurrentPos = ent:GetPos()

        local length   = math.Rand(particle_length_random.min, particle_length_random.max)
        local particle = emitter:Add(table.Random(particle_mats), ent.CurrentPos)

        if particle then
            particle:SetDieTime(particle_lifetime * effect_self.CurrentStrenght)
            particle:SetStartSize(math.Rand(1.9, 3.8) * particle_scale)
            particle:SetEndSize(0)
            particle:SetStartLength(length * particle_scale * particle_start_lengt_mult)
            particle:SetEndLength(length * particle_scale)
            particle:SetGravity(Vector(0, 0, -particle_gravity))

            local base_velocity = ent:GetForward() * -(particle_force + effect_self.ExtraForce) * effect_self.CurrentStrenght * force_mult

            if stream_spread > 0 then
                local spread_rad   = math.rad(stream_spread)
                local random_pitch = math.Rand(-spread_rad, spread_rad)
                local random_yaw   = math.Rand(-spread_rad, spread_rad)
                local forward = ent:GetForward()
                local right   = ent:GetRight()
                local up      = ent:GetUp()
                local spread_dir = forward + (right * math.sin(random_yaw)) + (up * math.sin(random_pitch))
                spread_dir:Normalize()
                base_velocity = spread_dir * -base_velocity:Length()
            end

            particle:SetVelocity(base_velocity)
            particle:SetCollide(true)
            particle:SetCollideCallback(function(_, pos, normal)
                if math.random(1, impact_chance) == 1 and (effect_self.CurrentStrenght or min_strenght) > 0.2 then
                    sound.Play(table.Random(drip_sounds), pos, sound_level, math.Rand(95, 105))
                    util.DecalEx(table.Random(decal_mats), Entity(0), pos, normal, Color(255, 255, 255), decal_scale, decal_scale)
                end
            end)
        end

        if timer.RepsLeft(timername) == 0 then
            emitter:Finish()
        end
    end)
end

function EFFECT:UpdateExtraForce()
    self.ExtraForce = particle_pulsate_max_force * (1 + math.sin(CurTime() * particle_pulsate_speed_mult))
end

function EFFECT:Think()
    if timer.Exists(self.timername) then
        local lifetime = CurTime() - self.StartTime
        local dietime  = self.reps * (1 / particle_fps)
        self.CurrentStrenght = math.Clamp(1 - (lifetime / dietime) * (1 - min_strenght), 0, 1)
        self:UpdateExtraForce()
        return true
    end
    return false
end

function EFFECT:Render() end
