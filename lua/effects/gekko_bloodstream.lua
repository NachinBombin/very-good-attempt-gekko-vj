-- ============================================================
-- lua/effects/gekko_bloodstream.lua
-- Standalone blood stream for npc_vj_gekko.
--
-- Caller (cl_init.lua / init.lua) sets:
--   data:SetEntity(ent)       -- the NPC (used to follow movement)
--   data:SetOrigin(hitPos)    -- bullet impact position
--   data:SetNormal(hitNorm)   -- surface normal at impact
--   data:SetFlags(0)          -- stream mode
-- ============================================================

-- ParticleEmitter:Add() requires a raw STRING path, NOT an IMaterial object.
local PARTICLE_MAT  = "decals/trail"
local BURST_MATS    = {
    "particle/blood1",
    "particle/blood2",
    "particle/blood3",
    "particle/blood4",
}

-- util.DecalEx() requires an IMaterial object.
local DECAL_PATHS = {
    "decals/Blood1", "decals/Blood2", "decals/Blood3",
    "decals/Blood4", "decals/Blood5", "decals/Blood6",
}
local decal_mats = {}
for _, v in ipairs(DECAL_PATHS) do
    decal_mats[#decal_mats + 1] = Material(v)
end

-- Fixed constants
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
local DECAL_SCALE  = 0.2
local MIN_STRENGTH = 0.25

-- Randomized per trigger (ranges)
local SIZE_MULT_MIN   = 1.0
local SIZE_MULT_MAX   = 2.8
local FORCE_MULT_MIN  = 1.0
local FORCE_MULT_MAX  = 2.0
local PULSATE_SPD_MIN = 6.0
local PULSATE_SPD_MAX = 10.0

-- ── IMPACT BURST + DECAL SCATTER ───────────────────────────
-- Fires once per hit inside EFFECT:Init.
--
-- NOTE: util.Effect("BloodImpact") reads GetBloodColor() from the entity.
-- The Gekko sets BLOOD_COLOR_NONE in init.lua to suppress VJ base blood,
-- which causes BloodImpact to render nothing silently.
-- We use a ParticleEmitter burst instead — same system as the stream,
-- guaranteed to work regardless of blood color settings.

local function DoImpactBurst(hitPos, hitNorm)
    -- 40% chance: short burst of blood drops at the impact point.
    if math.random() < 0.4 then
        local emitter = ParticleEmitter(hitPos, false)
        if emitter then
            local count = math.random(10, 20)
            for _ = 1, count do
                local mat = BURST_MATS[math.random(#BURST_MATS)]
                local p   = emitter:Add(mat, hitPos)
                if p then
                    -- Spread outward from the hit normal with randomness
                    local dir = (hitNorm + VectorRand() * 0.7):GetNormalized()
                    p:SetVelocity(dir * math.Rand(80, 280))
                    p:SetGravity(Vector(0, 0, -700))
                    p:SetLifeTime(0)
                    p:SetDieTime(math.Rand(0.25, 0.7))
                    p:SetStartAlpha(240)
                    p:SetEndAlpha(0)
                    p:SetStartSize(math.Rand(3, 11))
                    p:SetEndSize(0)
                    p:SetColor(200, 0, 0)
                    p:SetRoll(math.Rand(0, 360))
                    p:SetCollide(true)
                    -- Each burst drop that lands places a blood decal.
                    p:SetCollideCallback(function(_, pos, norm)
                        util.Decal("Blood", pos + norm, pos - norm * 4)
                    end)
                end
            end
            emitter:Finish()
        end
    end

    -- Scatter ground decals directly: util.Decal does its own internal
    -- trace from start to end and places the decal where it hits geometry.
    -- Trace straight down from around the hit point to land on the floor.
    local scatter = math.random(3, 6)
    for _ = 1, scatter do
        local ox = math.Rand(-30, 30)
        local oy = math.Rand(-30, 30)
        util.Decal("Blood",
            hitPos + Vector(ox, oy,  20),
            hitPos + Vector(ox, oy, -96)
        )
    end
end

-- ── EFFECT ──────────────────────────────────────────────────

function EFFECT:Init(data)
    local ent = data:GetEntity()
    if not IsValid(ent) then return end

    -- Roll random values once per trigger
    self.SIZE_MULT   = math.Rand(SIZE_MULT_MIN,   SIZE_MULT_MAX)
    self.FORCE_MULT  = math.Rand(FORCE_MULT_MIN,  FORCE_MULT_MAX)
    self.PULSATE_SPD = math.Rand(PULSATE_SPD_MIN, PULSATE_SPD_MAX)

    local hitPos = data:GetOrigin()
    if hitPos == Vector(0, 0, 0) then
        hitPos = ent:WorldSpaceCenter()
    end
    local hitNorm = data:GetNormal()
    if hitNorm == Vector(0, 0, 0) then
        hitNorm = ent:GetForward() * -1
    end

    -- Fire impact burst + ground decals on this hit
    DoImpactBurst(hitPos, hitNorm)

    self.StartTime       = CurTime()
    self.CurrentStrength = 1
    self.HitOffset       = hitPos - ent:GetPos()
    self:UpdateExtraForce()

    local spurt_delay = math.Rand(0.5, 5) / PARTICLE_FPS
    self.timername = "GekkoBloodStream_" .. ent:EntIndex() .. "_" .. CurTime()

    -- 3D emitter (true) — 2D mode renders decals/trail as black squares.
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
        local length   = math.Rand(P_LEN_MIN, P_LEN_MAX)
        local size_m   = effect_self.SIZE_MULT
        local force_m  = effect_self.FORCE_MULT

        local particle = emitter:Add(PARTICLE_MAT, spawnPos)
        if not particle then return end

        local strength = effect_self.CurrentStrength or 1

        particle:SetDieTime(P_LIFETIME * strength)
        particle:SetStartSize(math.Rand(1.9, 3.8) * P_SCALE * size_m)
        particle:SetEndSize(0)
        particle:SetStartLength(length * P_SCALE * P_LEN_START * size_m)
        particle:SetEndLength(length * P_SCALE * size_m)
        particle:SetGravity(Vector(0, 0, -P_GRAVITY))

        local base_vel = hitNorm * -(P_FORCE + effect_self.ExtraForce) * strength * force_m

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
                    DECAL_SCALE * size_m,
                    DECAL_SCALE * size_m
                )
            end
        end)

        if (timer.RepsLeft(effect_self.timername) or 1) == 0 then
            emitter:Finish()
        end
    end)
end

function EFFECT:UpdateExtraForce()
    self.ExtraForce = PULSATE_AMP * (1 + math.sin(CurTime() * (self.PULSATE_SPD or 8)))
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
