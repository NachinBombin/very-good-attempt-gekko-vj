-- ============================================================
-- lua/effects/gekko_bloodstream.lua
-- Standalone blood stream for npc_vj_gekko.
--
-- Caller (cl_init.lua / init.lua) sets:
--   data:SetEntity(ent)       -- the NPC (used to follow movement)
--   data:SetFlags(0)          -- stream mode
-- ============================================================

local PARTICLES = { "decals/trail" }
local DECALS = {
    "decals/Blood1", "decals/Blood2", "decals/Blood3",
    "decals/Blood4", "decals/Blood5", "decals/Blood6",
}

-- Baked-in values matching original Hemo ConVar defaults
local SIZE_MULT    = 1
local FORCE_MULT   = 1
local SPREAD_DEG   = 5
local REPS         = 300
local PARTICLE_FPS = 60
local P_LIFETIME   = 8
local P_SCALE      = 0.4
local P_FORCE      = 200
local P_GRAVITY    = 1050
local P_LEN_MIN    = 100
local P_LEN_MAX    = 100
local P_LEN_START  = 0.1
local PULSATE_AMP  = 100
local PULSATE_SPD  = 8
local DECAL_SCALE  = 0.2
local MIN_STRENGTH = 0.25

local function PrecacheMats(tbl)
    local out = {}
    for _, v in ipairs(tbl) do out[#out+1] = Material(v) end
    return out
end
local particle_mats = PrecacheMats(PARTICLES)
local decal_mats    = PrecacheMats(DECALS)

-- ── EFFECT ──────────────────────────────────────────────────

function EFFECT:Init(data)
    local ent     = data:GetEntity()

    if not IsValid(ent) then return end

    -- Derive a plausible wound position from the NPC's center.
    -- Server no longer needs to set SetOrigin or SetNormal;
    -- we build them here so the effect is self-contained.
    local hitPos  = data:GetOrigin()
    if hitPos == Vector(0,0,0) then
        hitPos = ent:WorldSpaceCenter()
    end
    local hitNorm = data:GetNormal()
    if hitNorm == Vector(0,0,0) then
        hitNorm = ent:GetForward() * -1
    end

    self.StartTime       = CurTime()
    self.CurrentStrength = 1
    self.HitOffset       = hitPos - ent:GetPos()
    self:UpdateExtraForce()

    local spurt_delay = math.Rand(0.5, 5) / PARTICLE_FPS
    self.timername = "GekkoBloodStream_" .. ent:EntIndex() .. "_" .. CurTime()

    -- FIX: use 3D emitter (true). 2D mode renders decals/trail as black squares.
    local emitter = ParticleEmitter(hitPos, true)
    if not emitter then return end

    local effect_self = self

    timer.Create(self.timername, spurt_delay, REPS, function()
        if not IsValid(ent) or not emitter then
            if emitter then emitter:Finish() end
            timer.Remove(effect_self.timername)
            return
        end

        local spawnPos = ent:GetPos() + effect_self.HitOffset

        local length = math.Rand(P_LEN_MIN, P_LEN_MAX)

        local particle = emitter:Add(table.Random(particle_mats), spawnPos)
        if not particle then return end

        -- FIX: guard CurrentStrength with 'or 1' so closures that outlive
        -- the EFFECT object (garbage-collected after Think returns false)
        -- never compare nil with a number (was line 105 crash).
        local strength = effect_self.CurrentStrength or 1

        particle:SetDieTime(P_LIFETIME * strength)
        particle:SetStartSize(math.Rand(1.9, 3.8) * P_SCALE * SIZE_MULT)
        particle:SetEndSize(0)
        particle:SetStartLength(length * P_SCALE * P_LEN_START * SIZE_MULT)
        particle:SetEndLength(length * P_SCALE * SIZE_MULT)
        particle:SetGravity(Vector(0, 0, -P_GRAVITY))

        local base_vel = hitNorm * -(P_FORCE + effect_self.ExtraForce) * strength * FORCE_MULT

        if SPREAD_DEG > 0 then
            local sr  = math.rad(SPREAD_DEG)
            local fwd   = hitNorm
            local right = fwd:Cross(Vector(0,0,1)):GetNormalized()
            local up    = right:Cross(fwd):GetNormalized()
            local spread_dir = (fwd + right * math.sin(math.Rand(-sr,sr)) + up * math.sin(math.Rand(-sr,sr))):GetNormalized()
            base_vel = spread_dir * -base_vel:Length()
        end

        particle:SetVelocity(base_vel)
        particle:SetCollide(true)
        particle:SetCollideCallback(function(_, pos, normal)
            -- FIX: guard against nil after effect object is destroyed
            local s = effect_self.CurrentStrength or 0
            if s > 0.2 then
                util.DecalEx(
                    table.Random(decal_mats),
                    Entity(0), pos, normal,
                    Color(255,255,255),
                    DECAL_SCALE * SIZE_MULT,
                    DECAL_SCALE * SIZE_MULT
                )
            end
        end)

        if (timer.RepsLeft(effect_self.timername) or 1) == 0 then
            emitter:Finish()
        end
    end)
end

function EFFECT:UpdateExtraForce()
    self.ExtraForce = PULSATE_AMP * (1 + math.sin(CurTime() * PULSATE_SPD))
end

function EFFECT:Think()
    if timer.Exists(self.timername) then
        local lifetime = CurTime() - self.StartTime
        local dietime  = REPS * (1 / PARTICLE_FPS)
        self.CurrentStrength = math.Clamp(
            1 - (lifetime / dietime) * (1 - MIN_STRENGTH), 0, 1
        )
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
