-- =============================================================
--  gekko_bloodstream.lua
--  Called by BloodVariant_HemoStream(ent) in cl_init.lua via:
--    util.Effect("gekko_bloodstream", effectdata, false)
--
--  EffectData contract:
--    SetEntity(ent)      -- the gekko entity to bleed from
--    SetFlags(0 or 1)    -- 0 = long stream, 1 = short burst
--    SetScale(float)     -- size multiplier  (0.6 – 1.8)
--    SetMagnitude(float) -- force multiplier (0.7 – 2.0)
--
--  Design fixes vs. the original Hemo port:
--    1. Self-contained: no external ConVars, no custom sound packs required.
--    2. Reads SetScale / SetMagnitude instead of ignoring them.
--    3. Bleeds in a FORWARD + UPWARD arc so the stream is
--       visible from the player's side.
--    4. Uses HL2 stock blood particles/decals — always available.
-- =============================================================

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

-- Stock HL2 flesh-hit sounds, always present in any GarrysMod install
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

-- Tunable constants
local BASE_PARTICLE_SCALE   = 0.45
local BASE_GRAVITY          = 950
local BASE_FORCE            = 220      -- units/s before multiplier
local PULSATE_MAX_FORCE     = 90
local PULSATE_SPEED_MULT    = 7
local SPREAD_ANGLE_DEG      = 18       -- cone half-angle for spray
local STREAM_LIFETIME       = 7
local MIN_STRENGTH          = 0.20

local REPS_STREAM           = 280      -- pulses for a long stream
local REPS_BURST            = 120      -- pulses for a short burst
local TIMER_INTERVAL        = 1 / 55  -- ~55 hz tick

function EFFECT:Init(data)
    local ent = data:GetEntity()
    if not IsValid(ent) then return end

    local flags      = data:GetFlags()       -- 0 = stream, 1 = burst
    local size_mult  = data:GetScale()       -- passed from BloodVariant_HemoStream
    local force_mult = data:GetMagnitude()

    -- Clamp to sane values in case caller passes garbage
    size_mult  = math.Clamp(size_mult  or 1, 0.3, 3.0)
    force_mult = math.Clamp(force_mult or 1, 0.3, 3.0)

    self.reps       = (flags == 1) and REPS_BURST or REPS_STREAM
    self.StartTime  = CurTime()
    self.CurrentStrength = 1
    self:_UpdateExtraForce()

    -- Unique timer name so multiple simultaneous bleeds don't stomp each other
    self.timername = "GekkoBloodStream_" .. tostring(ent:EntIndex()) .. "_" .. tostring(CurTime())

    local emitter = ParticleEmitter(ent:GetPos(), false)
    if not emitter then return end

    -- Initial squirt sound
    sound.Play(
        SQUIRT_SOUNDS[math.random(#SQUIRT_SOUNDS)],
        ent:GetPos(), 68, math.random(90, 110)
    )

    local self_ref = self
    local reps     = self.reps

    timer.Create(self.timername, TIMER_INTERVAL, reps, function()
        if not IsValid(ent) or not emitter then
            if emitter then emitter:Finish() end
            timer.Remove(self_ref.timername)
            return
        end

        -- -------------------------------------------------------
        --  Emit position: random bone on the gekko so blood
        --  appears to pour from the body, not the origin
        -- -------------------------------------------------------
        local BLOOD_BONES = {
            "b_spine3",
            "b_spine4",
            "b_pelvis",
            "b_l_upperleg",
            "b_r_upperleg",
            "b_l_hippiston1",
            "b_r_hippiston1",
        }
        local emit_pos = ent:GetPos() + Vector(0, 0, 80)
        local boneName = BLOOD_BONES[math.random(#BLOOD_BONES)]
        local boneIdx  = ent:LookupBone(boneName)
        if boneIdx and boneIdx >= 0 then
            local mat = ent:GetBoneMatrix(boneIdx)
            if mat then
                emit_pos = mat:GetTranslation()
            end
        end

        -- -------------------------------------------------------
        --  Direction: forward arc upward so stream is visible.
        --  The original Hemo code used -GetForward() which shoots
        --  BACKWARD (into geometry behind the NPC).  We use a
        --  blend of forward + slight upward bias instead.
        -- -------------------------------------------------------
        local fwd = ent:GetForward()
        local up  = Vector(0, 0, 1)

        -- Build a spread cone around (fwd + 0.3*up)
        local base_dir = (fwd + up * 0.3):GetNormalized()
        local spread_rad = math.rad(SPREAD_ANGLE_DEG)
        local right = fwd:Cross(up):GetNormalized()

        local pitch_off = math.Rand(-spread_rad, spread_rad)
        local yaw_off   = math.Rand(-spread_rad, spread_rad)
        local dir = (base_dir + right * math.sin(yaw_off) + up * math.sin(pitch_off)):GetNormalized()

        -- -------------------------------------------------------
        --  Particle
        -- -------------------------------------------------------
        local speed = (BASE_FORCE + self_ref.ExtraForce) * self_ref.CurrentStrength * force_mult
        local sz    = BASE_PARTICLE_SCALE * size_mult

        local particle = emitter:Add(PARTICLE_MATS[math.random(#PARTICLE_MATS)], emit_pos)
        if particle then
            particle:SetDieTime(STREAM_LIFETIME * self_ref.CurrentStrength)
            particle:SetStartSize(math.Rand(2.0, 4.0) * sz)
            particle:SetEndSize(0)
            particle:SetStartLength(10 * sz)
            particle:SetEndLength(math.Rand(80, 120) * sz)
            particle:SetGravity(Vector(0, 0, -BASE_GRAVITY))
            particle:SetVelocity(dir * speed)
            particle:SetCollide(true)
            particle:SetCollideCallback(function(_, pos, normal)
                if self_ref.CurrentStrength > 0.15 then
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

        if timer.RepsLeft(self_ref.timername) == 0 then
            emitter:Finish()
        end
    end)
end

function EFFECT:_UpdateExtraForce()
    self.ExtraForce = PULSATE_MAX_FORCE * (1 + math.sin(CurTime() * PULSATE_SPEED_MULT))
end

function EFFECT:Think()
    if timer.Exists(self.timername) then
        local lifetime = CurTime() - self.StartTime
        local dietime  = self.reps * TIMER_INTERVAL
        self.CurrentStrength = math.Clamp(
            1 - (lifetime / dietime) * (1 - MIN_STRENGTH),
            0, 1
        )
        self:_UpdateExtraForce()
        return true
    end
    return false
end

function EFFECT:Render() end
