-- ============================================================
--  lua/effects/gekko_bloodstream_fx.lua
--  Standalone blood stream effect for npc_vj_gekko.
--  Ported from Hemo-fluid-stream (bloodstreameffectzippy).
--  No external dependencies required.
-- ============================================================

local EFFECT = {}

local particle_scale   = 0.4
local stream_lifetime  = 12
local stream_rate      = 0.04
local stream_speed_min = 30
local stream_speed_max = 90
local stream_gravity   = Vector(0, 0, -200)
local drip_chance      = 0.35
local drip_speed       = 15
local blood_color      = Color(180, 10, 10)

local BLOOD_MATERIALS = {
    Material("effects/blood"),
    Material("effects/blood2"),
    Material("effects/blood3"),
    Material("effects/blood4"),
}

local DRIP_MATERIALS = {
    Material("decals/blood1"),
    Material("decals/blood2"),
    Material("decals/blood3"),
}

function EFFECT:Init(data)
    local anchor = data:GetEntity()
    if not IsValid(anchor) then return end

    local timername = "gekko_bstream_" .. tostring(anchor:EntIndex()) .. "_" .. tostring(CurTime())
    self.timername  = timername
    self.anchor     = anchor
    self.starttime  = CurTime()

    local effect_self = self

    timer.Create(timername, stream_rate, math.ceil(stream_lifetime / stream_rate), function()
        if not IsValid(anchor) then
            timer.Remove(timername)
            return
        end

        local pos = anchor:GetPos()
        local ang = anchor:GetAngles()

        -- Main blood jet
        local emitter = ParticleEmitter(pos)
        if emitter then
            local particle = emitter:Add(BLOOD_MATERIALS[math.random(#BLOOD_MATERIALS)], pos)
            if particle then
                local forward = ang:Forward()
                local spread  = Vector(
                    (math.random() - 0.5) * 0.4,
                    (math.random() - 0.5) * 0.4,
                    (math.random() - 0.5) * 0.4
                )
                local vel = (forward + spread) * math.Rand(stream_speed_min, stream_speed_max)

                particle:SetVelocity(vel)
                particle:SetGravity(stream_gravity)
                particle:SetLifeTime(0)
                particle:SetDieTime(math.Rand(0.3, 0.7))
                particle:SetStartAlpha(220)
                particle:SetEndAlpha(0)
                particle:SetStartSize(particle_scale * math.Rand(6, 14))
                particle:SetEndSize(particle_scale * math.Rand(2, 6))
                particle:SetColor(blood_color.r, blood_color.g, blood_color.b)
                particle:SetRoll(math.Rand(0, 360))
                particle:SetRollDelta(math.Rand(-2, 2))
                particle:SetCollide(true)
                particle:SetCollideCallback(function(norm, p)
                    -- splat decal on impact
                    util.Decal("Blood", p:GetPos() + norm * 2, p:GetPos() - norm * 4)
                end)
            end
            emitter:Finish()
        end

        -- Occasional drip
        if math.random() < drip_chance then
            local demitter = ParticleEmitter(pos)
            if demitter then
                local dp = demitter:Add(DRIP_MATERIALS[math.random(#DRIP_MATERIALS)], pos + Vector(0,0,-2))
                if dp then
                    dp:SetVelocity(Vector(
                        (math.random()-0.5)*drip_speed,
                        (math.random()-0.5)*drip_speed,
                        -drip_speed * math.Rand(0.5, 1.5)
                    ))
                    dp:SetGravity(stream_gravity * 0.5)
                    dp:SetLifeTime(0)
                    dp:SetDieTime(math.Rand(0.5, 1.2))
                    dp:SetStartAlpha(180)
                    dp:SetEndAlpha(0)
                    dp:SetStartSize(particle_scale * math.Rand(3, 7))
                    dp:SetEndSize(0)
                    dp:SetColor(blood_color.r, blood_color.g, blood_color.b)
                    dp:SetRoll(math.Rand(0, 360))
                end
                demitter:Finish()
            end
        end
    end)
end

function EFFECT:Think()
    if not IsValid(self.anchor) then
        if self.timername then timer.Remove(self.timername) end
        return false
    end
    if CurTime() > self.starttime + stream_lifetime then
        if self.timername then timer.Remove(self.timername) end
        return false
    end
    return true
end

function EFFECT:Render() end

effects.Register(EFFECT, "gekko_bloodstream_fx")
