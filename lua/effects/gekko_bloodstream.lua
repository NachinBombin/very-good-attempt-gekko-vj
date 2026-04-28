-- ============================================================
--  GEKKO BLOOD STREAM EFFECT
--  Timed particle stream, mirrors Hemo-fluid-stream architecture.
--
--  data:GetEntity()    = the gekko NPC
--  data:GetOrigin()    = world-space wound position (bone origin)
--  data:GetScale()     = size_mult   (set by BloodVariant_HemoStream)
--  data:GetMagnitude() = force_mult  (set by BloodVariant_HemoStream)
--  data:GetFlags()     = 0 = stream (long), 1 = burst (short)
-- ============================================================

local BLOOD_COLOR_R = 180
local BLOOD_COLOR_G = 10
local BLOOD_COLOR_B = 10

local PARTICLE_MATS = {
    Material("particle/smokesprites_0001"),
    Material("particle/smokesprites_0002"),
    Material("particle/smokesprites_0003"),
    Material("particle/smokesprites_0004"),
    Material("particle/smokesprites_0005"),
    Material("particle/smokesprites_0006"),
    Material("particle/smokesprites_0007"),
    Material("particle/smokesprites_0008"),
    Material("particle/smokesprites_0009"),
}

local DECAL_MATS = {
    Material("decals/Blood1"),
    Material("decals/Blood2"),
    Material("decals/Blood3"),
    Material("decals/Blood4"),
    Material("decals/Blood5"),
    Material("decals/Blood6"),
}

-- How many timer ticks for stream vs burst
local REPS_STREAM = 28
local REPS_BURST  = 10

-- Seconds between each spurt tick
local SPURT_DELAY = 0.055

function EFFECT:Init(data)
    local ent        = data:GetEntity()
    local origin     = data:GetOrigin()
    local flags      = data:GetFlags()
    local size_mult  = math.max(data:GetScale(),     0.1)
    local force_mult = math.max(data:GetMagnitude(), 0.1)

    -- If origin is zero vector (caller didn't set it), fall back to NPC base + offset
    if origin == Vector(0, 0, 0) and IsValid(ent) then
        origin = ent:GetPos() + Vector(0, 0, 60)
    end

    local reps = (flags == 1) and REPS_BURST or REPS_STREAM

    self.StartTime = CurTime()
    self.TimerName = "GekkoBloodStream_" .. tostring(math.random(1, 999999)) .. "_" .. CurTime()

    local emitter = ParticleEmitter(origin, false)
    if not emitter then return end

    -- Capture locals for the timer closure
    local eff        = self
    local base_speed = 220 * force_mult

    local function SpurtTick()
        -- Re-derive origin from entity each tick so stream follows a moving NPC
        local pos = origin
        if IsValid(ent) then
            pos = ent:GetPos() + Vector(0, 0, 60)
        end

        -- Spray direction: outward from NPC forward, biased upward
        local fwd   = IsValid(ent) and ent:GetForward() or Vector(1, 0, 0)
        local right = IsValid(ent) and ent:GetRight()   or Vector(0, 1, 0)
        local up    = Vector(0, 0, 1)

        -- Blood mist puff
        local mist = emitter:Add(PARTICLE_MATS[math.random(#PARTICLE_MATS)], pos)
        if mist then
            mist:SetVelocity(Vector(math.Rand(-20, 20), math.Rand(-20, 20), math.Rand(5, 40)))
            mist:SetDieTime(math.Rand(0.3, 0.7))
            mist:SetStartAlpha(160)
            mist:SetEndAlpha(0)
            mist:SetStartSize(6  * size_mult)
            mist:SetEndSize(18 * size_mult)
            mist:SetRoll(math.Rand(0, 360))
            mist:SetRollDelta(math.Rand(-3, 3))
            mist:SetAirResistance(55)
            mist:SetGravity(Vector(0, 0, -180))
            mist:SetColor(BLOOD_COLOR_R, BLOOD_COLOR_G, BLOOD_COLOR_B)
        end

        -- 3–5 arcing droplets per tick
        for _ = 1, math.random(3, 5) do
            local spread_r = math.Rand(-0.55, 0.55)
            local spread_u = math.Rand(-0.2,  0.7)
            local dir = (fwd + right * spread_r + up * spread_u)
            dir:Normalize()

            local speed   = math.Rand(base_speed * 0.45, base_speed * 1.3)
            local droplet = emitter:Add(PARTICLE_MATS[math.random(#PARTICLE_MATS)], pos)
            if droplet then
                droplet:SetVelocity(dir * speed)
                droplet:SetDieTime(math.Rand(0.5, 1.3))
                droplet:SetStartAlpha(255)
                droplet:SetEndAlpha(0)
                droplet:SetStartSize(math.Rand(2, 5) * size_mult)
                droplet:SetEndSize(math.Rand(0.5, 2) * size_mult)
                droplet:SetRoll(math.Rand(0, 360))
                droplet:SetRollDelta(0)
                droplet:SetAirResistance(28)
                droplet:SetGravity(Vector(0, 0, -620))
                droplet:SetColor(BLOOD_COLOR_R, BLOOD_COLOR_G, BLOOD_COLOR_B)
                droplet:SetCollide(true)
                droplet:SetCollideCallback(function(_, hpos, normal)
                    util.DecalEx(
                        DECAL_MATS[math.random(#DECAL_MATS)],
                        Entity(0), hpos, normal,
                        Color(255, 255, 255),
                        0.15 * size_mult,
                        0.15 * size_mult
                    )
                end)
            end
        end

        -- Finish emitter on last rep
        if timer.RepsLeft(eff.TimerName) == 0 then
            emitter:Finish()
        end
    end

    timer.Create(self.TimerName, SPURT_DELAY, reps, SpurtTick)
end

function EFFECT:Think()
    return timer.Exists(self.TimerName)
end

function EFFECT:Render() end
