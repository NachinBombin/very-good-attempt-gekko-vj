-- =============================================================
--  gekko_bloodstream  --  Gekko VJ blood-stream effect
--  Ported from NachinBombin/Hemo-fluid-stream- (bloodstreameffectzippy)
--
--  FIXES vs. the failed attempt:
--   1. Registered as "gekko_bloodstream" to match util.Effect() call in cl_init.lua.
--   2. size_mult  read from data:GetScale()     (set by BloodVariant_HemoStream)
--   3. force_mult read from data:GetMagnitude() (set by BloodVariant_HemoStream)
--   4. No dependency on nextgenblood4_* ConVars.
--   5. Material tables built lazily inside Init() -- calling Material() at file
--      scope during effect load returns broken userdata in some GMod builds and
--      causes the "bad argument #2 to insert (number expected, got userdata)" crash.
-- =============================================================

-- ---- string tables (paths only -- materials built on first Init) ---------------
local PARTICLE_PATHS = { "decals/trail" }

local DECAL_PATHS = {
    "decals/Blood1", "decals/Blood2", "decals/Blood3",
    "decals/Blood4", "decals/Blood5", "decals/Blood6",
}

-- lazily populated on first EFFECT:Init call
local decal_mats    = nil
local particle_mats = nil

local function EnsureMaterials()
    if decal_mats then return end
    decal_mats    = {}
    particle_mats = {}
    for _, v in ipairs(DECAL_PATHS)    do decal_mats[#decal_mats+1]       = Material(v) end
    for _, v in ipairs(PARTICLE_PATHS) do particle_mats[#particle_mats+1] = Material(v) end
end

-- ---- tuneable constants --------------------------------------------------------
local particle_length_random      = { min = 100, max = 100 }
local particle_start_length_mult  = 0.1
local particle_scale              = 0.4

local particle_gravity            = 1050
local particle_force              = 200
local particle_pulsate_max_force  = 100
local particle_pulsate_speed_mult = 8

local particle_reps_stream        = 300
local particle_reps_burst         = 150

local particle_fps                = 60
local particle_lifetime           = 8

local decal_scale                 = 0.2
local impact_chance               = 1      -- 1-in-N
local min_strength                = 0.25
local spread_angle                = 5      -- degrees

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
-- -------------------------------------------------------------------------------

-- ===============================================================================
function EFFECT:Init(data)
    -- Build material objects here, not at file scope
    EnsureMaterials()

    local ent = data:GetEntity()
    if not IsValid(ent) then return end

    local flags = data:GetFlags()

    -- Read the values BloodVariant_HemoStream passes
    local size_mult  = math.Clamp(data:GetScale()     or 1, 0.1, 10)
    local force_mult = math.Clamp(data:GetMagnitude() or 1, 0.1, 10)

    local reps = (flags == 1) and particle_reps_burst or particle_reps_stream
    self.reps  = reps

    local spurt_delay = math.Rand(0.5, 5) / particle_fps

    self.StartTime       = CurTime()
    self.CurrentStrength = 1
    self:UpdateExtraForce()

    local emitter = ParticleEmitter(ent:GetPos(), false)
    if not emitter then return end

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

        local base_vel = ent:GetForward()
            * -(particle_force + effect_self.ExtraForce)
            * effect_self.CurrentStrength
            * force_mult

        if spread_angle > 0 then
            local sr   = math.rad(spread_angle)
            local sdir = (ent:GetForward()
                + ent:GetRight() * math.sin(math.Rand(-sr, sr))
                + ent:GetUp()   * math.sin(math.Rand(-sr, sr))):GetNormalized()
            base_vel = sdir * -base_vel:Length()
        end

        particle:SetVelocity(base_vel)
        particle:SetCollide(true)
        particle:SetCollideCallback(function(_, pos, normal)
            if math.random(1, impact_chance) == 1
            and (effect_self.CurrentStrength or min_strength) > 0.2 then
                sound.Play(table.Random(drip_sounds), pos, sound_level, math.Rand(95, 105), 1)
                local ds = decal_scale * size_mult
                util.DecalEx(table.Random(decal_mats), Entity(0), pos, normal,
                    Color(255, 255, 255), ds, ds)
            end
        end)

        if timer.RepsLeft(effect_self.timername) == 0 then
            emitter:Finish()
        end
    end)
end

function EFFECT:UpdateExtraForce()
    self.ExtraForce = particle_pulsate_max_force
        * (1 + math.sin(CurTime() * particle_pulsate_speed_mult))
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
