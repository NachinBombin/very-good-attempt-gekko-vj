-- ============================================================
--  GEKKO BLOOD STREAM EFFECT
--  Blood particles arc forward from the entity using
--  patterns from VJ_Blood1 (DrVrej/VJ-Base).
--  data:GetScale()     = size_mult   (set by BloodVariant_HemoStream)
--  data:GetMagnitude() = force_mult  (set by BloodVariant_HemoStream)
--  data:GetFlags()     = 0 stream / 1 burst
-- ============================================================

local BLOOD_COLOR_R = 180
local BLOOD_COLOR_G = 10
local BLOOD_COLOR_B = 10

local SMOKE_MATS = {
    "particle/smokesprites_0001",
    "particle/smokesprites_0002",
    "particle/smokesprites_0003",
    "particle/smokesprites_0004",
    "particle/smokesprites_0005",
    "particle/smokesprites_0006",
    "particle/smokesprites_0007",
    "particle/smokesprites_0008",
    "particle/smokesprites_0009",
}

local DECALS = {
    "decals/Blood1",
    "decals/Blood2",
    "decals/Blood3",
    "decals/Blood4",
    "decals/Blood5",
    "decals/Blood6",
}

function EFFECT:Init(data)
    local ent        = data:GetEntity()
    local origin     = data:GetOrigin()
    local flags      = data:GetFlags()   -- 0 = stream, 1 = burst
    local size_mult  = math.max(data:GetScale(), 0.1)
    local force_mult = math.max(data:GetMagnitude(), 0.1)

    -- If entity is valid use its position; otherwise fall back to origin
    if IsValid(ent) then
        origin = ent:GetPos() + Vector(0, 0, 60)
    end

    local fwd   = IsValid(ent) and ent:GetForward() or Vector(1, 0, 0)
    local right = IsValid(ent) and ent:GetRight()   or Vector(0, 1, 0)
    local up    = IsValid(ent) and ent:GetUp()      or Vector(0, 0, 1)

    local count      = (flags == 1) and 12 or 24
    local base_speed = 180 * force_mult

    local emitter = ParticleEmitter(origin)
    if not emitter then return end

    -- Blood mist cloud at origin
    for _ = 1, 6 do
        local mist = emitter:Add(SMOKE_MATS[math.random(#SMOKE_MATS)], origin)
        if mist then
            mist:SetVelocity(Vector(math.Rand(-30, 30), math.Rand(-30, 30), math.Rand(10, 60)))
            mist:SetDieTime(math.Rand(0.4, 0.9))
            mist:SetStartAlpha(180)
            mist:SetEndAlpha(0)
            mist:SetStartSize(8 * size_mult)
            mist:SetEndSize(22 * size_mult)
            mist:SetRoll(math.Rand(0, 360))
            mist:SetRollDelta(math.Rand(-2, 2))
            mist:SetAirResistance(60)
            mist:SetGravity(Vector(0, 0, -200))
            mist:SetColor(BLOOD_COLOR_R, BLOOD_COLOR_G, BLOOD_COLOR_B)
            mist:SetCollide(false)
        end
    end

    -- Arcing blood droplets
    for _ = 1, count do
        local spread_x = math.Rand(-0.5, 0.5)
        local spread_z = math.Rand(-0.3, 0.6)
        local dir = (fwd + right * spread_x + up * spread_z)
        dir:Normalize()

        local speed = math.Rand(base_speed * 0.5, base_speed * 1.4)
        local droplet = emitter:Add(SMOKE_MATS[math.random(#SMOKE_MATS)], origin)
        if droplet then
            droplet:SetVelocity(dir * speed)
            droplet:SetDieTime(math.Rand(0.5, 1.2))
            droplet:SetStartAlpha(255)
            droplet:SetEndAlpha(0)
            droplet:SetStartSize(math.Rand(2, 5) * size_mult)
            droplet:SetEndSize(math.Rand(1, 3) * size_mult)
            droplet:SetRoll(math.Rand(0, 360))
            droplet:SetRollDelta(0)
            droplet:SetAirResistance(30)
            droplet:SetGravity(Vector(0, 0, -600))
            droplet:SetColor(BLOOD_COLOR_R, BLOOD_COLOR_G, BLOOD_COLOR_B)
            droplet:SetCollide(true)
            droplet:SetCollideCallback(function(_, pos, normal)
                util.Decal(DECALS[math.random(#DECALS)], pos + normal, pos - normal)
            end)
        end
    end

    emitter:Finish()
end

function EFFECT:Think()
    return false
end

function EFFECT:Render() end
