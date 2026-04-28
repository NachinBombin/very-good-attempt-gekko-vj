-- =============================================================
--  lua/effects/gekko_bloodstream.lua
--  Gekko VJ blood-stream effect
--
--  GMod loads effects ONLY from <addon_root>/lua/effects/.
--  The copy that was inside npc_vj_gekko/lua/effects/ was never
--  mounted, which is why util.Effect("gekko_bloodstream") silently
--  failed. This file is the single authoritative copy.
--
--  Crash fix: Material() called at file scope during effect
--  registration returns broken userdata in some GMod builds.
--  All Material() calls are deferred into EnsureMaterials()
--  which runs inside EFFECT:Init (safe, live-game context).
-- =============================================================

-- ---- path tables only (no Material() calls here) -----------
local DECAL_PATHS = {
    "decals/Blood1", "decals/Blood2", "decals/Blood3",
    "decals/Blood4", "decals/Blood5", "decals/Blood6",
}

-- Tinted smoke sprites -- coloured red via SetColor, cheap & reliable
local PARTICLE_PATHS = {
    "particle/smokesprites_0001",
    "particle/smokesprites_0002",
    "particle/smokesprites_0003",
    "particle/smokesprites_0004",
    "particle/smokesprites_0005",
}

-- lazily populated on first EFFECT:Init
local decal_mats    = nil
local particle_mats = nil

local function EnsureMaterials()
    if decal_mats then return end
    decal_mats    = {}
    particle_mats = {}
    for _, v in ipairs(DECAL_PATHS)    do decal_mats[#decal_mats+1]       = Material(v) end
    for _, v in ipairs(PARTICLE_PATHS) do particle_mats[#particle_mats+1] = Material(v) end
end

-- ---- blood colour ------------------------------------------
local BLOOD_R, BLOOD_G, BLOOD_B = 180, 10, 10

-- ---- stream/burst constants --------------------------------
local REPS_STREAM = 28     -- ticks for a long wound stream
local REPS_BURST  = 10     -- ticks for a quick burst
local SPURT_DELAY = 0.055  -- seconds per tick

-- =============================================================
function EFFECT:Init(data)
    EnsureMaterials()   -- safe: we are inside a running game frame

    local ent        = data:GetEntity()
    local origin     = data:GetOrigin()
    local flags      = data:GetFlags()
    local size_mult  = math.max(data:GetScale(),     0.1)
    local force_mult = math.max(data:GetMagnitude(), 0.1)

    -- Fallback origin if caller didn't SetOrigin
    if origin == Vector(0, 0, 0) and IsValid(ent) then
        origin = ent:GetPos() + Vector(0, 0, 60)
    end

    local reps = (flags == 1) and REPS_BURST or REPS_STREAM

    self.TimerName = "GekkoBS_" .. tostring(math.random(1, 999999)) .. "_" .. CurTime()

    local emitter = ParticleEmitter(origin, false)
    if not emitter then return end

    local eff        = self
    local base_speed = 220 * force_mult

    local function SpurtTick()
        -- Follow a moving NPC
        local pos = origin
        if IsValid(ent) then
            pos = ent:GetPos() + Vector(0, 0, 60)
        end

        local fwd   = IsValid(ent) and ent:GetForward() or Vector(1, 0, 0)
        local right = IsValid(ent) and ent:GetRight()   or Vector(0, 1, 0)

        -- Blood mist puff
        local mist = emitter:Add(particle_mats[math.random(#particle_mats)], pos)
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
            mist:SetColor(BLOOD_R, BLOOD_G, BLOOD_B)
        end

        -- 3-5 arcing droplets
        for _ = 1, math.random(3, 5) do
            local dir = (fwd
                + right * math.Rand(-0.55, 0.55)
                + Vector(0, 0, 1) * math.Rand(-0.2, 0.7)):GetNormalized()

            local droplet = emitter:Add(particle_mats[math.random(#particle_mats)], pos)
            if droplet then
                droplet:SetVelocity(dir * math.Rand(base_speed * 0.45, base_speed * 1.3))
                droplet:SetDieTime(math.Rand(0.5, 1.3))
                droplet:SetStartAlpha(255)
                droplet:SetEndAlpha(0)
                droplet:SetStartSize(math.Rand(2, 5) * size_mult)
                droplet:SetEndSize(math.Rand(0.5, 2) * size_mult)
                droplet:SetRoll(math.Rand(0, 360))
                droplet:SetAirResistance(28)
                droplet:SetGravity(Vector(0, 0, -620))
                droplet:SetColor(BLOOD_R, BLOOD_G, BLOOD_B)
                droplet:SetCollide(true)
                droplet:SetCollideCallback(function(_, hpos, normal)
                    util.DecalEx(
                        decal_mats[math.random(#decal_mats)],
                        Entity(0), hpos, normal,
                        Color(255, 255, 255),
                        0.15 * size_mult,
                        0.15 * size_mult
                    )
                end)
            end
        end

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
