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
local PARTICLE_MAT = "decals/trail"

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

-- ── VANILLA BLOOD IMPACT (40% chance) + DECAL SCATTER ───────
-- Fires once per hit, not on every particle tick.

local function PlaceBloodDecal(from, to)
    -- Traces onto MASK_SOLID_BRUSHONLY so decals land on world
    -- geometry, not on the NPC model (which doesn't accept decals).
    local tr = util.TraceLine({
        start  = from,
        endpos = to,
        mask   = MASK_SOLID_BRUSHONLY,
    })
    if tr.Hit then
        util.Decal("Blood", tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal * 4)
    end
end

local function DoVanillaBlood(hitPos, hitNorm)
    -- 40% chance: BloodImpact particle effect at the exact hit position.
    -- "BloodImpact" is the valid registered HL2/GMod effect name.
    -- "bloodspray" does not exist and silently does nothing.
    if math.random() < 0.4 then
        local e = EffectData()
        e:SetOrigin(hitPos)
        e:SetNormal(hitNorm)
        e:SetScale(math.Rand(0.5, 1.5))
        e:SetMagnitude(math.Rand(1, 4))
        e:SetRadius(math.Rand(4, 12))
        util.Effect("BloodImpact", e, false)
    end

    -- Decal on the surface behind the hit point (along the normal).
    PlaceBloodDecal(hitPos + hitNorm * 2, hitPos - hitNorm * 24)

    -- Ground splatter: trace straight down from above the hit,
    -- offset horizontally so drops spread around the feet.
    local scatter = math.random(3, 6)
    for _ = 1, scatter do
        local ox = math.Rand(-28, 28)
        local oy = math.Rand(-28, 28)
        PlaceBloodDecal(
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

    -- Fire vanilla blood on this hit
    DoVanillaBlood(hitPos, hitNorm)

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
