if SERVER then return end

-- FIXED: Store material PATH STRINGS, not IMaterial objects.
-- ParticleEmitter:Add() requires a string path. Passing an IMaterial
-- object (returned by Material()) causes Add() to return nil every time,
-- producing zero particles.
local particle_mats = {
    "decals/trail",
}

local particle_length_random      = { min = 100, max = 100 }
local particle_start_length_mult  = 0.1
local particle_scale              = 0.4
local particle_gravity            = 1050
local particle_force              = 200
local particle_pulsate_max_force  = 100
local particle_pulsate_speed_mult = 8
local particle_reps_stream        = 300
local particle_fps                = 60
local particle_lifetime           = 8
local impact_chance               = 1
local min_strenght                = 0.25

function EFFECT:Init(data)
    local ent = data:GetEntity()
    if not IsValid(ent) then return end

    local flags = data:GetFlags()
    self.reps = (flags == 1 and 150) or (flags == 0 and particle_reps_stream) or particle_reps_stream

    local spurt_delay = math.Rand(0.5, 5) / particle_fps

    self.StartTime       = CurTime()
    self.CurrentStrenght = 1
    self:UpdateExtraForce()

    -- FIXED: true = 3D emitter so particles have correct world-space perspective.
    -- false (2D) made particles render as flat screen-space sprites,
    -- causing them to appear invisible at most viewing angles.
    self.timername = "GekkoBloodStreamTimer_" .. ent:EntIndex() .. "_" .. CurTime()
    local emitter  = ParticleEmitter(ent:GetPos(), true)
    if not emitter then return end

    local effect_self = self

    timer.Create(self.timername, spurt_delay, self.reps, function()
        if not IsValid(ent) then
            emitter:Finish()
            timer.Remove(effect_self.timername)
            return
        end

        ent.CurrentPos = ent:GetPos()

        local length   = math.Rand(particle_length_random.min, particle_length_random.max)
        local mat      = particle_mats[math.random(#particle_mats)]
        local particle = emitter:Add(mat, ent.CurrentPos)
        if not particle then return end

        particle:SetDieTime(particle_lifetime * effect_self.CurrentStrenght)
        particle:SetStartSize(math.Rand(1.9, 3.8) * particle_scale)
        particle:SetEndSize(0)
        particle:SetStartLength(length * particle_scale * particle_start_length_mult)
        particle:SetEndLength(length * particle_scale)
        particle:SetGravity(Vector(0, 0, -particle_gravity))

        local vel = ent:GetForward() * -(particle_force + effect_self.ExtraForce) * effect_self.CurrentStrenght
        particle:SetVelocity(vel)

        particle:SetCollide(true)
        particle:SetCollideCallback(function(_, pos, normal)
            if math.random(1, impact_chance) == 1 and effect_self.CurrentStrenght > 0.2 then
                util.Decal("Blood", pos + normal, pos - normal)
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
        self.CurrentStrenght = math.Clamp(1 - (lifetime / dietime) * (1 - min_strenght), 0, 1)
        self:UpdateExtraForce()
        return true
    end
    return false
end

function EFFECT:Render() end
