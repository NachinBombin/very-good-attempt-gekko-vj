-- ============================================================
--  gekko_bloodstream.lua
--  This is a DIRECT COPY of Hemo's bloodstreameffectzippy.lua
--  with only the effect name changed. No other modifications.
--  decals/trail confirmed working on target system.
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

local particle_length_random       = {min=100, max=100}
local particle_start_lengt_mult    = 0.1
local particle_scale               = 0.4
local particle_gravity             = 1050
local particle_force               = 200
local particle_pulsate_max_force   = 100
local particle_pulsate_speed_mult  = 8
local particle_reps_stream         = 300
local particle_fps                 = 60
local particle_lifetime            = 8
local decal_scale                  = 0.2
local impact_chance                = 1
local min_strenght                 = 0.25

local function make_materials(tbl)
    local materials = {}
    for _, v in ipairs(tbl) do
        table.insert(materials, Material(v))
    end
    return materials
end

local decal_mats    = make_materials(decals)
local particle_mats = make_materials(particles)

function EFFECT:Init(data)
    local ent = data:GetEntity()
    if not IsValid(ent) then return end

    local flags = data:GetFlags()

    self.reps = (flags == 1 and 150) or (flags == 0 and particle_reps_stream) or particle_reps_stream

    local spurt_delay = math.Rand(0.5, 5) / particle_fps

    self.StartTime      = CurTime()
    self.CurrentPos     = ent:GetPos()
    self.CurrentStrenght = 1
    self:UpdateExtraForce()

    self.timername = "GekkoBloodStreamTimer_" .. ent:EntIndex() .. "_" .. CurTime()
    local emitter  = ParticleEmitter(self.CurrentPos, false)
    if not emitter then return end

    local effect_self = self
    local reps        = self.reps

    timer.Create(self.timername, spurt_delay, reps, function()
        if not IsValid(ent) or not emitter then
            if emitter then emitter:Finish() end
            timer.Remove(effect_self.timername)
            return
        end

        ent.CurrentPos = ent:GetPos()

        local length   = math.Rand(particle_length_random.min, particle_length_random.max)
        local particle = emitter:Add(table.Random(particle_mats), ent.CurrentPos)

        particle:SetDieTime(particle_lifetime * effect_self.CurrentStrenght)
        particle:SetStartSize(math.Rand(1.9, 3.8) * particle_scale)
        particle:SetEndSize(0)
        particle:SetStartLength(length * particle_scale * particle_start_lengt_mult)
        particle:SetEndLength(length * particle_scale)
        particle:SetGravity(Vector(0, 0, -particle_gravity))

        local base_velocity = ent:GetForward() * -(particle_force + effect_self.ExtraForce) * effect_self.CurrentStrenght
        particle:SetVelocity(base_velocity)

        particle:SetCollide(true)
        particle:SetCollideCallback(function(_, pos, normal)
            if math.random(1, impact_chance) == 1 and (effect_self.CurrentStrenght or min_strenght) > 0.2 then
                util.DecalEx(table.Random(decal_mats), Entity(0), pos, normal,
                    Color(255,255,255), decal_scale, decal_scale)
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
        self.CurrentStrenght = math.Clamp(1 - (lifetime / dietime) * (1 - min_strenght), 0, 1)
        self:UpdateExtraForce()
        return true
    end
    return false
end

function EFFECT:Render() end
