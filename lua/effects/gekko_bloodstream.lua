-- ============================================================
-- lua/effects/gekko_bloodstream.lua
-- Standalone blood stream for npc_vj_gekko.
--
-- Caller (init.lua server-side) sets:
--   data:SetEntity(ent)       -- the NPC (used to follow movement)
--   data:SetOrigin(hitPos)    -- REQUIRED: actual bullet/damage hit position
--   data:SetNormal(hitNorm)   -- direction away from attacker
--   data:SetFlags(0)          -- stream mode
--
-- IMPORTANT (server init.lua):
--   Use dmginfo:GetDamagePosition() or tr.HitPos for SetOrigin.
--   Do NOT use self:GetPos() -- that places the stream at the feet.
-- ============================================================

-- ParticleEmitter:Add() requires a raw STRING path, NOT an IMaterial object.
local PARTICLES = {
    "particle/blood1",
    "particle/blood2",
    "particle/blood3",
    "particle/blood4",
}

-- util.DecalEx() requires an IMaterial object, so these ARE pre-cached correctly.
local DECAL_PATHS = {
    "decals/Blood1", "decals/Blood2", "decals/Blood3",
    "decals/Blood4", "decals/Blood5", "decals/Blood6",
}
local decal_mats = {}
for _, v in ipairs(DECAL_PATHS) do
    decal_mats[#decal_mats + 1] = Material(v)
end

-- Tuning
local SIZE_MULT    = 1
local FORCE_MULT   = 1
local SPREAD_DEG   = 5
local REPS         = 80          -- ~1.3 s per trigger at 60fps (was 300 = 5 s, causing stacking)
local PARTICLE_FPS = 60
local P_LIFETIME   = 5
local P_SCALE      = 0.4
local P_FORCE      = 200
local P_GRAVITY    = 1050
local P_LEN_MIN    = 80
local P_LEN_MAX    = 120
local P_LEN_START  = 0.1
local PULSATE_AMP  = 100
local PULSATE_SPD  = 8
local DECAL_SCALE  = 0.2
local MIN_STRENGTH = 0.25

-- ── EFFECT ──────────────────────────────────────────────────

function EFFECT:Init(data)
    local ent = data:GetEntity()
    if not IsValid(ent) then return end

    local hitPos  = data:GetOrigin()
    local hitNorm = data:GetNormal()

    -- Fallback if server forgot to set origin: use WorldSpaceCenter.
    -- NOTE: this fallback will still look wrong. The real fix is in init.lua.
    if hitPos == Vector(0, 0, 0) then
        hitPos = ent:WorldSpaceCenter()
    end
    if hitNorm == Vector(0, 0, 0) then
        hitNorm = ent:GetForward() * -1
    end

    self.StartTime       = CurTime()
    self.CurrentStrength = 1
    self.HitOffset       = hitPos - ent:GetPos()
    self:UpdateExtraForce()

    local spurt_delay = math.Rand(0.5, 3) / PARTICLE_FPS

    -- FIXED: timer name is fixed per-entity (no CurTime suffix).
    -- This means a new trigger REPLACES the old stream instead of stacking.
    self.timername = "GekkoBloodStream_" .. ent:EntIndex()

    -- 2D emitter required for particle/blood* sprite materials.
    local emitter = ParticleEmitter(hitPos, false)
    if not emitter then return end

    local effect_self = self

    timer.Create(self.timername, spurt_delay, REPS, function()
        if not IsValid(ent) then
            if emitter then emitter:Finish() end
            return
        end

        local spawnPos = ent:GetPos() + effect_self.HitOffset
        local length   = math.Rand(P_LEN_MIN, P_LEN_MAX)

        -- FIXED: raw string path (not IMaterial) to prevent black squares.
        local particle = emitter:Add(PARTICLES[math.random(#PARTICLES)], spawnPos)
        if not particle then return end

        local strength = effect_self.CurrentStrength or 1

        particle:SetDieTime(P_LIFETIME * strength)
        particle:SetStartSize(math.Rand(1.9, 3.8) * P_SCALE * SIZE_MULT)
        particle:SetEndSize(0)
        particle:SetStartLength(length * P_SCALE * P_LEN_START * SIZE_MULT)
        particle:SetEndLength(length * P_SCALE * SIZE_MULT)
        particle:SetGravity(Vector(0, 0, -P_GRAVITY))
        particle:SetColor(200, 0, 0)
        particle:SetLighting(false)

        local base_vel = hitNorm * -(P_FORCE + effect_self.ExtraForce) * strength * FORCE_MULT

        if SPREAD_DEG > 0 then
            local sr    = math.rad(SPREAD_DEG)
            local fwd   = hitNorm
            local right = fwd:Cross(Vector(0, 0, 1)):GetNormalized()
            local up    = right:Cross(fwd):GetNormalized()
            local spread_dir = (fwd
                + right * math.sin(math.Rand(-sr, sr))
                + up    * math.sin(math.Rand(-sr, sr))):GetNormalized()
            base_vel = spread_dir * -base_vel:Length()
        end

        particle:SetVelocity(base_vel)
        particle:SetCollide(true)
        particle:SetCollideCallback(function(_, pos, normal)
            local s = effect_self.CurrentStrength or 0
            if s > 0.2 then
                util.DecalEx(
                    table.Random(decal_mats),
                    Entity(0), pos, normal,
                    Color(255, 255, 255),
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
    if not IsValid(ent) then return end
    timer.Remove("GekkoBloodStream_" .. ent:EntIndex())
end)
