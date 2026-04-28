-- =============================================================
--  gekko_bloodstream  –  Gekko VJ blood-stream effect
--  Ported from NachinBombin/Hemo-fluid-stream- (bloodstreameffectzippy)
--
--  FIXES vs. the failed attempt:
--   1. The effect is now registered as "gekko_bloodstream", matching
--      the util.Effect("gekko_bloodstream", ...) call in cl_init.lua.
--   2. size_mult  is read from data:GetScale()     (set by BloodVariant_HemoStream)
--   3. force_mult is read from data:GetMagnitude() (set by BloodVariant_HemoStream)
--   4. No dependency on nextgenblood4_* ConVars – works without Hemo installed.
--   5. flags == 0 → long stream (particle_reps_stream)
--      flags == 1 → short burst  (particle_reps_burst)
-- =============================================================

-- ---- tuneable constants ----------------------------------------
local particles = { "decals/trail" }

local decals = {
    "decals/Blood1", "decals/Blood2", "decals/Blood3",
    "decals/Blood4", "decals/Blood5", "decals/Blood6",
}

local particle_length_random        = { min = 100, max = 100 }
local particle_start_length_mult    = 0.1
local particle_scale                = 0.4

local particle_gravity              = 1050
local particle_force                = 200
local particle_pulsate_max_force    = 100
local particle_pulsate_speed_mult   = 8

local particle_reps_stream          = 300
local particle_reps_burst           = 150

local particle_fps                  = 60
local particle_lifetime             = 8

local decal_scale                   = 0.2
local impact_chance                 = 1   -- 1-in-N
local min_strength                  = 0.25
local spread_angle                  = 5   -- degrees

local drip_sounds = {
    "bloodsplashing/drip_1.wav",
    "bloodsplashing/drip_2.wav",
    "bloodsplashing/drip_3.wav",
    "bloodsplashing/drip_4.wav",
    "bloodsplashing/drip_5.wav",
    "bloodsplashing/drips_1.wav",
    "bloodsplashing/drips_2.wav",
    "bloodsplashing/drips_3.wav",
    "bloodsplashing/drips_4.wav",
    "bloodsplashing/drips_5.wav",
    "bloodsplashing/drips_6.wav",
    "bloodsplashing/spatter_hard_1.wav",
    "bloodsplashing/spatter_hard_2.wav",
    "bloodsplashing/spatter_hard_3.wav",
}
local squrt_sounds = {
    "squirting/artery_squirt_1.wav",
    "squirting/artery_squirt_2.wav",
    "squirting/artery_squirt_3.wav",
}
local sound_level  = 70
local sound_level2 = 35
-- ----------------------------------------------------------------

local function make_materials(tbl)
    local out = {}
    for _, v in ipairs(tbl) do
        table.insert(out, Material(v))
    end
    return out
end

local decal_mats    = make_materials(decals)
local particle_mats = make_materials(particles)

-- ================================================================
function EFFECT:Init(data)
    local ent = data:GetEntity()
    if not IsValid(ent) then return end

    local flags = data:GetFlags()

    -- *** KEY FIX: read the values that BloodVariant_HemoStream sets ***
    local size_mult  = data:GetScale()      -- set via effectdata:SetScale(size_mult)
    local force_mult = data:GetMagnitude()  -- set via effectdata:SetMagnitude(force_mult)

    -- Clamp to sane range so bad callers don't explode the effect
    size_mult  = math.Clamp(size_mult  or 1, 0.1, 10)
    force_mult = math.Clamp(force_mult or 1, 0.1, 10)

    local reps = math.floor(
        (flags == 1 and particle_reps_burst) or
        particle_reps_stream
    )
    self.reps = reps

    local spurt_delay = math.Rand(0.5, 5) / particle_fps

    self.StartTime      = CurTime()
    self.CurrentPos     = ent:GetPos()
    self.CurrentStrength = 1
    self:UpdateExtraForce()

    local emitter = ParticleEmitter(self.CurrentPos, false)
    if not emitter then return end

    -- unique timer name per entity+time to survive multiplayer
    self.timername = "GekkoBloodStream_" .. ent:EntIndex() .. "_" .. CurTime()

    sound.Play(table.Random(squrt_sounds), ent:GetPos(), sound_level2, math.Rand(95, 105), 1)

    local effect_self = self

    timer.Create(self.timername, spurt_delay, reps, function()
        if not IsValid(ent) or not emitter then
            if emitter then emitter:Finish() end
            timer.Remove(effect_self.timername)
            return
        end

        sound.Play(table.Random(squrt_sounds), ent:GetPos(), sound_level2, math.Rand(95, 105), 1)

        local length   = math.Rand(particle_length_random.min, particle_length_random.max)
        local particle = emitter:Add(table.Random(particle_mats), ent:GetPos())
        if not particle then return end

        particle:SetDieTime(particle_lifetime * effect_self.CurrentStrength)
        particle:SetStartSize(math.Rand(1.9, 3.8) * particle_scale * size_mult)
        particle:SetEndSize(0)
        particle:SetStartLength(length * particle_scale * particle_start_length_mult * size_mult)
        particle:SetEndLength(length * particle_scale * size_mult)
        particle:SetGravity(Vector(0, 0, -particle_gravity))

        -- base velocity, honoring force_mult from the caller
        local base_vel = ent:GetForward() * -(particle_force + effect_self.ExtraForce) * effect_self.CurrentStrength * force_mult

        -- add random spread
        if spread_angle > 0 then
            local sr    = math.rad(spread_angle)
            local fwd   = ent:GetForward()
            local right = ent:GetRight()
            local up    = ent:GetUp()
            local sdir  = (fwd
                + right * math.sin(math.Rand(-sr, sr))
                + up    * math.sin(math.Rand(-sr, sr))):GetNormalized()
            base_vel = sdir * -base_vel:Length()
        end

        particle:SetVelocity(base_vel)
        particle:SetCollide(true)
        particle:SetCollideCallback(function(_, pos, normal)
            if math.random(1, impact_chance) == 1
            and (effect_self.CurrentStrength or min_strength) > 0.2 then
                sound.Play(table.Random(drip_sounds), pos, sound_level, math.Rand(95, 105), 1)
                local ds = decal_scale * size_mult
                util.DecalEx(table.Random(decal_mats), Entity(0), pos, normal, Color(255, 255, 255), ds, ds)
            end
        end)

        if timer.RepsLeft(effect_self.timername) == 0 then
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
        self.CurrentStrength = math.Clamp(
            1 - (lifetime / dietime) * (1 - min_strength), 0, 1)
        self:UpdateExtraForce()
        return true
    end
    return false
end

function EFFECT:Render() end

hook.Add("EntityRemoved", "GekkoBloodStream_Cleanup", function(ent)
    if ent.gekko_bloodstream_timer then
        timer.Remove(ent.gekko_bloodstream_timer)
    end
end)
