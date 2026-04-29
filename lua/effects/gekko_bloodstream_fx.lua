-- ============================================================
--  lua/effects/gekko_bloodstream_fx.lua
--  Standalone blood stream effect for npc_vj_gekko.
--  Ported from Hemo-fluid-stream (bloodstreameffectzippy).
--  No external dependencies required.
--
--  Registered as "gekko_bloodstream" to match cl_init call:
--    util.Effect("gekko_bloodstream", effectdata, false)
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
local blood_r, blood_g, blood_b = 180, 10, 10

-- BUG FIX #2: emitter:Add() requires a raw STRING path, not an IMaterial object.
-- Storing strings here; they are passed directly to emitter:Add() each tick.
local BLOOD_MATERIALS = {
    "effects/blood",
    "effects/blood2",
    "effects/blood3",
    "effects/blood4",
}

-- BUG FIX #3: decals/blood* are decal paths, not particle sprite paths.
-- Drip particles must also use the effects/ sprite paths.
local DRIP_MATERIALS = {
    "effects/blood",
    "effects/blood2",
    "effects/blood3",
}

function EFFECT:Init(data)
    local anchor = data:GetEntity()
    if not IsValid(anchor) then return end

    local timername = "gekko_bstream_" .. tostring(anchor:EntIndex()) .. "_" .. tostring(CurTime())
    self.timername  = timername
    self.anchor     = anchor
    self.starttime  = CurTime()

    timer.Create(timername, stream_rate, math.ceil(stream_lifetime / stream_rate), function()
        if not IsValid(anchor) then
            timer.Remove(timername)
            return
        end

        local pos = anchor:GetPos() + Vector(0, 0, 70)
        local ang = anchor:GetAngles()

        -- BUG FIX #4: second arg true = 3D emitter.
        -- Without it particles are 2D sprites; gravity/collide barely visible.
        local emitter = ParticleEmitter(pos, true)
        if emitter then
            -- BUG FIX #2 applied: passing string path, not IMaterial object.
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
                particle:SetColor(blood_r, blood_g, blood_b)
                particle:SetRoll(math.Rand(0, 360))
                particle:SetRollDelta(math.Rand(-2, 2))
                particle:SetCollide(true)
                particle:SetCollideCallback(function(norm, p)
                    util.Decal("Blood", p:GetPos() + norm * 2, p:GetPos() - norm * 4)
                end)
            end
            emitter:Finish()
        end

        -- Occasional drip
        if math.random() < drip_chance then
            -- BUG FIX #4: 3D emitter for drips as well.
            local demitter = ParticleEmitter(pos, true)
            if demitter then
                -- BUG FIX #2 + #3: string path from effects/ folder.
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
                    dp:SetColor(blood_r, blood_g, blood_b)
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

-- BUG FIX #1: was "gekko_bloodstream_fx" — cl_init calls util.Effect("gekko_bloodstream").
-- Name mismatch meant the effect NEVER ran. Renamed to match the call site.
effects.Register(EFFECT, "gekko_bloodstream")
