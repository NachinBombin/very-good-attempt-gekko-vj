-- ============================================================
--  GEKKO BLOOD STREAM EFFECT
--  Based on bloodstreameffectzippy.lua (Hemo-fluid-stream)
--  Copied verbatim, ConVars replaced by per-call randomizers.
--  size_mult  → data:GetScale()      (randomized at call site)
--  force_mult → data:GetMagnitude()  (randomized at call site)
-- ============================================================

local particles = {
    "decals/trail",
}

local decals = {
    "decals/Blood1",
    "decals/Blood3",
    "decals/Blood4",
    "decals/Blood5",
    "decals/Blood6",
    "decals/Blood2",
    "decals/Blood3",
}

local particle_length_random         = { min = 100, max = 100 }
local particle_start_lengt_mult      = 0.1
local particle_scale                 = 0.4

local particle_gravity               = 1050
local particle_force                 = 200
local particle_pulsate_max_force     = 100
local particle_pulsate_speed_mult    = 8

local particle_reps_stream           = 300
local particle_reps_burst            = 150

local particle_fps                   = 60
local particle_lifetime              = 8

local stream_particle_lifetime       = 8
local burst_particle_lifetime        = 8

local decal_scale                    = 0.2

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
    "bloodsplashing/spatter_grass_1.wav",
    "bloodsplashing/spatter_grass_2.wav",
    "bloodsplashing/spatter_grass_3.wav",
    "bloodsplashing/spatter_hard_1.wav",
    "bloodsplashing/spatter_hard_2.wav",
    "bloodsplashing/spatter_hard_3.wav",
    "bloodsplashing/drip_lowpass_1.wav",
    "bloodsplashing/drip_lowpass_2.wav",
    "bloodsplashing/drip_lowpass_3.wav",
    "bloodsplashing/drip_lowpass_4.wav",
    "bloodsplashing/drip_lowpass_5.wav",
}

local sound_level = 70

local squrt_sounds = {
    "squirting/artery_squirt_1.wav",
    "squirting/artery_squirt_2.wav",
    "squirting/artery_squirt_3.wav",
    "squirting/artery_squirt_3.wav",
    "squirting/artery_squirt_2.wav",
    "squirting/artery_squirt_1.wav",
    "squirting/artery_squirt_2.wav",
    "squirting/artery_squirt_2.wav",
    "squirting/artery_squirt_3.wav",
    "squirting/artery_squirt_1.wav",
    "squirting/artery_squirt_3.wav",
    "squirting/artery_squirt_2.wav",
}

local sound_level2   = 35
local impact_chance  = 1

local function make_materials(tbl)
    local materials = {}
    for _, v in ipairs(tbl) do
        table.insert(materials, Material(v))
    end
    return materials
end

local decal_mats    = make_materials(decals)
local particle_mats = make_materials(particles)

local min_strenght = 0.25

function EFFECT:Init(data)
    local ent = data:GetEntity()
    if not IsValid(ent) then return end

    local flags = data:GetFlags()

    -- size_mult and force_mult are baked in by the Gekko caller via SetScale / SetMagnitude
    local size_mult  = data:GetScale()
    local force_mult = data:GetMagnitude()

    -- spread is randomized here per-stream for natural variation
    local spread_angle = math.Rand(2, 9)

    local reps_multiplier = 1
    self.reps = math.floor(
        ((flags == 1 and particle_reps_burst) or
         (flags == 0 and particle_reps_stream) or 0)
        * reps_multiplier
    )

    local density    = 1
    local spurt_delay = math.Rand(0.5, 5) / (particle_fps * density)

    self.StartTime    = CurTime()
    self.CurrentPos   = ent:GetPos()
    self.CurrentStrenght = 1
    self:UpdateExtraForce()

    self.timername = "GekkoBloodStreamTimer_" .. ent:EntIndex() .. "_" .. CurTime()

    local emitter = ParticleEmitter(self.CurrentPos, false)
    if not emitter then return end

    sound.Play(table.Random(squrt_sounds), ent:GetPos(), sound_level2, math.Rand(95, 105), 1)

    local effect_self = self
    local reps        = self.reps

    timer.Create(self.timername, spurt_delay, reps, function()
        if not IsValid(ent) or not emitter then
            if emitter then emitter:Finish() end
            timer.Remove(effect_self.timername)
            return
        end

        sound.Play(table.Random(squrt_sounds), ent:GetPos(), sound_level2, math.Rand(95, 105), 1)

        ent.CurrentPos = ent:GetPos()

        local length   = math.Rand(particle_length_random.min, particle_length_random.max)
        local particle = emitter:Add(table.Random(particle_mats), ent.CurrentPos)

        if not particle then return end

        particle:SetDieTime(particle_lifetime * effect_self.CurrentStrenght)
        particle:SetStartSize(math.Rand(1.9, 3.8) * particle_scale * size_mult)
        particle:SetEndSize(0)
        particle:SetStartLength(length * particle_scale * particle_start_lengt_mult * size_mult)
        particle:SetEndLength(length * particle_scale * size_mult)
        particle:SetGravity(Vector(0, 0, -particle_gravity))

        local base_velocity = ent:GetForward() * -(particle_force + effect_self.ExtraForce) * effect_self.CurrentStrenght * force_mult

        if spread_angle > 0 then
            local spread_rad   = math.rad(spread_angle)
            local random_pitch = math.Rand(-spread_rad, spread_rad)
            local random_yaw   = math.Rand(-spread_rad, spread_rad)

            local forward = ent:GetForward()
            local right   = ent:GetRight()
            local up      = ent:GetUp()

            local spread_dir = forward + (right * math.sin(random_yaw)) + (up * math.sin(random_pitch))
            spread_dir:Normalize()

            local velocity_magnitude = base_velocity:Length()
            base_velocity = spread_dir * -velocity_magnitude
        end

        particle:SetVelocity(base_velocity)
        particle:SetCollide(true)
        particle:SetCollideCallback(function(_, pos, normal)
            if math.random(1, impact_chance) == 1 and (effect_self.CurrentStrenght or min_strenght) > 0.2 then
                sound.Play(table.Random(drip_sounds), pos, sound_level, math.Rand(95, 105), 1)
                local ds = decal_scale * size_mult
                util.DecalEx(table.Random(decal_mats), Entity(0), pos, normal, Color(255, 255, 255), ds, ds)
            end
        end)

        if timer.RepsLeft(effect_self.timername) == 0 then emitter:Finish() end
    end)
end

function EFFECT:UpdateExtraForce()
    self.ExtraForce = particle_pulsate_max_force * (1 + math.sin(CurTime() * particle_pulsate_speed_mult))
end

function EFFECT:Think()
    if timer.Exists(self.timername) then
        local lifetime = CurTime() - self.StartTime
        local dietime  = self.reps * (1 / particle_fps)
        self.CurrentStrenght = math.Clamp(
            1 - (lifetime / dietime) * (1 - min_strenght),
            0, 1
        )
        self:UpdateExtraForce()
        return true
    else
        return false
    end
end

function EFFECT:Render() end

hook.Add("EntityRemoved", "GekkoBloodStream_Cleanup", function(ent)
    if ent.gekko_bloodstream_timer then
        timer.Remove(ent.gekko_bloodstream_timer)
    end
end)