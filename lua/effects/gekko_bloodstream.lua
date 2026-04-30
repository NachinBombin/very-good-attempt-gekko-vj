-- ============================================================
-- lua/effects/gekko_bloodstream.lua
-- Standalone blood stream + blood mist for npc_vj_gekko.
--
-- Rates (per hit):
--   Blood mist  : 100%
--   Blood stream:  40%
-- ============================================================

local PARTICLE_MAT  = "decals/trail"

local MIST_MAT_BASE = "particle/smokesprites_000"  -- append 1-9

local MIST_R = 210
local MIST_G = 30
local MIST_B = 30

local DECAL_PATHS = {
    "decals/Blood1", "decals/Blood2", "decals/Blood3",
    "decals/Blood4", "decals/Blood5", "decals/Blood6",
}
local decal_mats = {}
for _, v in ipairs(DECAL_PATHS) do
    decal_mats[#decal_mats + 1] = Material(v)
end

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

local SIZE_MULT_MIN   = 1.0
local SIZE_MULT_MAX   = 2.8
local FORCE_MULT_MIN  = 1.0
local FORCE_MULT_MAX  = 2.0
local PULSATE_SPD_MIN = 6.0
local PULSATE_SPD_MAX = 10.0

local STREAM_CHANCE = 0.40

local MIST_COUNT   = { 8,   14,  22  }
local MIST_SIZEMIN = { 5,   7,   10  }
local MIST_SIZEMAX = { 14,  20,  30  }
local MIST_LIFEMIN = { 0.4, 0.6, 0.8 }
local MIST_LIFEMAX = { 0.8, 1.2, 1.8 }
local MIST_SPEED   = { 35,  55,  80  }
local MIST_ALPHA   = { 50,  65,  80  }

-- ── BLOOD MIST (100% of hits) ──────────────────────────────

local function SpawnBloodMist(hitPos, hitNorm)
    local w       = math.random(1, 3)
    local emitter = ParticleEmitter(hitPos, true)
    if not emitter then return end

    local count = MIST_COUNT[w]
    local speed = MIST_SPEED[w]

    for _ = 1, count do
        local mat = MIST_MAT_BASE .. math.random(1, 9)
        local p   = emitter:Add(mat, hitPos)
        if not p then continue end

        local vel = hitNorm * math.Rand(speed * 0.6, speed) + VectorRand() * (speed * 0.3)

        p:SetVelocity(vel)
        p:SetLifeTime(0)
        p:SetDieTime(math.Rand(MIST_LIFEMIN[w], MIST_LIFEMAX[w]))
        p:SetStartAlpha(MIST_ALPHA[w])
        p:SetEndAlpha(0)
        p:SetStartSize(math.Rand(MIST_SIZEMIN[w] * 0.8, MIST_SIZEMIN[w] * 1.2))
        p:SetEndSize(math.Rand(MIST_SIZEMAX[w] * 0.8, MIST_SIZEMAX[w] * 1.2))
        p:SetColor(MIST_R, MIST_G, MIST_B)
        p:SetAirResistance(40)
        p:SetGravity(Vector(0, 0, -12))
        p:SetRoll(math.Rand(0, 360))
        p:SetRollDelta(math.Rand(-0.4, 0.4))
    end

    emitter:Finish()
end

-- ── GROUND DECALS ON HIT ──────────────────────────────────

local function DoImpactDecals(hitPos)
    local count = math.random(3, 6)
    for _ = 1, count do
        local ox = math.Rand(-30, 30)
        local oy = math.Rand(-30, 30)
        util.Decal("Blood",
            hitPos + Vector(ox, oy,  20),
            hitPos + Vector(ox, oy, -96)
        )
    end
end

-- ── EFFECT ────────────────────────────────────────────────

function EFFECT:Init(data)
    local ent = data:GetEntity()
    if not IsValid(ent) then return end

    local hitPos = data:GetOrigin()
    if hitPos == Vector(0, 0, 0) then
        hitPos = ent:WorldSpaceCenter()
    end
    local hitNorm = data:GetNormal()
    if hitNorm == Vector(0, 0, 0) then
        hitNorm = ent:GetForward() * -1
    end

    -- Mist and decals: every hit.
    SpawnBloodMist(hitPos, hitNorm)
    DoImpactDecals(hitPos)

    -- Stream: only 40% of hits.
    if math.random() > STREAM_CHANCE then return end

    self.SIZE_MULT   = math.Rand(SIZE_MULT_MIN,   SIZE_MULT_MAX)
    self.FORCE_MULT  = math.Rand(FORCE_MULT_MIN,  FORCE_MULT_MAX)
    self.PULSATE_SPD = math.Rand(PULSATE_SPD_MIN, PULSATE_SPD_MAX)

    self.StartTime       = CurTime()
    self.CurrentStrength = 1
    self.HitOffset       = hitPos - ent:GetPos()
    self:UpdateExtraForce()

    local spurt_delay = math.Rand(0.5, 5) / PARTICLE_FPS
    self.timername = "GekkoBloodStream_" .. ent:EntIndex() .. "_" .. CurTime()

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
    -- timername is nil when the stream was skipped (60% of hits) — guard required.
    if not self.timername then return false end
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
