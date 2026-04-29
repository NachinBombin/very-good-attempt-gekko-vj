-- =============================================================
--  lua/effects/gekko_bloodstream.lua
--  Called by BloodVariant_HemoStream(ent) in cl_init.lua via:
--    util.Effect("gekko_bloodstream", effectdata, false)
--
--  EffectData contract:
--    SetEntity(ent)      -- the gekko entity to bleed from
--    SetFlags(0 or 1)    -- 0 = long stream, 1 = short burst
--    SetScale(float)     -- size multiplier  (0.6 - 1.8)
--    SetMagnitude(float) -- force multiplier (0.7 - 2.0)
-- =============================================================

local EFFECT = {}

local PARTICLE_MATS = {
    Material("particle/blood1"),
    Material("particle/blood2"),
    Material("particle/blood3"),
    Material("particle/blood4"),
    Material("particle/blood5"),
    Material("particle/blood6"),
}

local DECAL_MATS = {
    Material("decals/Blood1"),
    Material("decals/Blood2"),
    Material("decals/Blood3"),
    Material("decals/Blood4"),
    Material("decals/Blood5"),
    Material("decals/Blood6"),
}

local SQUIRT_SOUNDS = {
    "physics/flesh/flesh_impact_bullet1.wav",
    "physics/flesh/flesh_impact_bullet2.wav",
    "physics/flesh/flesh_impact_bullet3.wav",
    "physics/flesh/flesh_impact_bullet4.wav",
    "physics/flesh/flesh_impact_bullet5.wav",
}

local DRIP_SOUNDS = {
    "physics/flesh/flesh_squishy_impact_hard1.wav",
    "physics/flesh/flesh_squishy_impact_hard2.wav",
    "physics/flesh/flesh_squishy_impact_hard3.wav",
    "physics/flesh/flesh_squishy_impact_hard4.wav",
}

local BASE_PARTICLE_SCALE   = 0.45
local BASE_GRAVITY          = 950
local BASE_FORCE            = 220
local PULSATE_MAX_FORCE     = 90
local PULSATE_SPEED_MULT    = 7
local SPREAD_ANGLE_DEG      = 18
local STREAM_LIFETIME       = 7
local MIN_STRENGTH          = 0.20

local REPS_STREAM           = 280
local REPS_BURST            = 120
local TIMER_INTERVAL        = 1 / 55

local BLOOD_BONES = {
    "b_spine3",
    "b_spine4",
    "b_pelvis",
    "b_l_upperleg",
    "b_r_upperleg",
    "b_l_hippiston1",
    "b_r_hippiston1",
}

function EFFECT:Init(data)
    local ent = data:GetEntity()
    if not IsValid(ent) then return end

    local flags      = data:GetFlags()
    local size_mult  = math.Clamp(data:GetScale()     or 1, 0.3, 3.0)
    local force_mult = math.Clamp(data:GetMagnitude() or 1, 0.3, 3.0)

    self.reps            = (flags == 1) and REPS_BURST or REPS_STREAM
    self.StartTime       = CurTime()
    self.CurrentStrength = 1
    self.size_mult       = size_mult
    self.force_mult      = force_mult

    self.timername = "GekkoBloodStream_" .. ent:EntIndex() .. "_" .. CurTime()

    -- FIX: create emitter before the timer so closure captures it cleanly.
    -- If creation fails, bail before creating the timer.
    local emitter = ParticleEmitter(ent:GetPos(), false)
    if not emitter then return end

    sound.Play(
        SQUIRT_SOUNDS[math.random(#SQUIRT_SOUNDS)],
        ent:GetPos(), 68, math.random(90, 110)
    )

    -- FIX: ALL mutable state the timer closure needs lives in this
    -- shared table. The timer callback must NEVER touch `self` directly
    -- because `self` inside a GMod timer callback is NOT the effect table.
    local state = {
        CurrentStrength = 1,
        ExtraForce      = PULSATE_MAX_FORCE,
    }
    self._state = state

    local timername  = self.timername
    local reps       = self.reps
    local startTime  = self.StartTime

    timer.Create(timername, TIMER_INTERVAL, reps, function()
        -- FIX: guard both ent AND emitter; clean up emitter on death
        if not IsValid(ent) then
            if emitter then emitter:Finish() emitter = nil end
            timer.Remove(timername)
            return
        end

        -- Emit position: pick a random bone
        local emit_pos = ent:GetPos() + Vector(0, 0, 80)
        local boneName = BLOOD_BONES[math.random(#BLOOD_BONES)]
        local boneIdx  = ent:LookupBone(boneName)
        if boneIdx and boneIdx >= 0 then
            local mat = ent:GetBoneMatrix(boneIdx)
            if mat then emit_pos = mat:GetTranslation() end
        end

        -- FIX: safe normalization guard before GetNormalized()
        local fwd = ent:GetForward()
        local up  = Vector(0, 0, 1)
        local base_dir = fwd + up * 0.3
        if base_dir:LengthSqr() < 0.001 then base_dir = Vector(1, 0, 0.3) end
        base_dir:Normalize()

        local right = fwd:Cross(up)
        if right:LengthSqr() < 0.001 then right = Vector(0, 1, 0) end
        right:Normalize()

        local spread_rad = math.rad(SPREAD_ANGLE_DEG)
        local pitch_off  = math.Rand(-spread_rad, spread_rad)
        local yaw_off    = math.Rand(-spread_rad, spread_rad)
        local dir = (base_dir + right * math.sin(yaw_off) + up * math.sin(pitch_off)):GetNormalized()

        -- FIX: read from shared state table, NOT from self
        local strength = state.CurrentStrength
        local speed    = (BASE_FORCE + state.ExtraForce) * strength * force_mult
        local sz       = BASE_PARTICLE_SCALE * size_mult

        local particle = emitter:Add(PARTICLE_MATS[math.random(#PARTICLE_MATS)], emit_pos)
        if particle then
            particle:SetDieTime(STREAM_LIFETIME * strength)
            particle:SetStartSize(math.Rand(2.0, 4.0) * sz)
            particle:SetEndSize(0)
            particle:SetStartLength(10 * sz)
            particle:SetEndLength(math.Rand(80, 120) * sz)
            particle:SetGravity(Vector(0, 0, -BASE_GRAVITY))
            particle:SetVelocity(dir * speed)
            particle:SetCollide(true)
            particle:SetCollideCallback(function(_, pos, normal)
                -- FIX: read strength from state table, not self
                if state.CurrentStrength > 0.15 then
                    sound.Play(
                        DRIP_SOUNDS[math.random(#DRIP_SOUNDS)],
                        pos, 60, math.random(90, 115)
                    )
                    local ds = 0.18 * size_mult
                    util.DecalEx(
                        DECAL_MATS[math.random(#DECAL_MATS)],
                        Entity(0), pos, normal,
                        Color(255, 255, 255), ds, ds
                    )
                end
            end)
        end

        -- FIX: guard RepsLeft - timer.RepsLeft returns nil if timer is gone
        local repsLeft = timer.RepsLeft(timername)
        if repsLeft ~= nil and repsLeft == 0 then
            emitter:Finish()
            emitter = nil
        end
    end)
end

function EFFECT:_UpdateExtraForce()
    local ef = PULSATE_MAX_FORCE * (1 + math.sin(CurTime() * PULSATE_SPEED_MULT))
    self.ExtraForce = ef
    if self._state then
        self._state.ExtraForce = ef
    end
end

function EFFECT:Think()
    if timer.Exists(self.timername) then
        local lifetime = CurTime() - self.StartTime
        local dietime  = self.reps * TIMER_INTERVAL
        local strength = math.Clamp(
            1 - (lifetime / dietime) * (1 - MIN_STRENGTH),
            0, 1
        )
        self.CurrentStrength = strength
        -- FIX: push updated strength into the shared state table
        if self._state then
            self._state.CurrentStrength = strength
        end
        self:_UpdateExtraForce()
        return true
    end
    return false
end

function EFFECT:Render() end

-- FIX: explicit registration so GMod always finds the effect
effects.Register(EFFECT, "gekko_bloodstream")
