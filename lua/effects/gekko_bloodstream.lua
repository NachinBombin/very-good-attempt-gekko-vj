-- ============================================================
--  gekko_bloodstream.lua
--  Standalone blood stream for VJ Gekko
--  Mirrors Hemo-fluid-stream architecture exactly.
--  Additions: multi-bone emission + torso-height fallback.
-- ============================================================

-- ============================================================
--  MATERIAL PRE-CACHE  (file scope, exactly like Hemo)
--  decals/trail is stock HL2 — no addon VMT needed.
-- ============================================================
local BLOOD_MATS = {
    Material("decals/trail"),
}

local DECAL_MATS = {
    Material("decals/Blood1"),
    Material("decals/Blood2"),
    Material("decals/Blood3"),
    Material("decals/Blood4"),
    Material("decals/Blood5"),
    Material("decals/Blood6"),
}

-- ============================================================
--  BONE EMISSION POINTS
-- ============================================================
local EMISSION_BONES = {
    "b_spine3",
    "b_pelvis",
    "b_pedestal",
    "b_r_hippiston1",
    "b_l_hippiston1",
}

-- Torso height offset used when bone lookup fails.
-- Gekko pelvis sits ~80 units above its feet (entity origin).
local TORSO_Z = 80

local function GetEmissionPos(ent)
    local boneName = EMISSION_BONES[math.random(#EMISSION_BONES)]
    local boneIdx  = ent:LookupBone(boneName)
    if boneIdx and boneIdx >= 0 then
        local bmat = ent:GetBoneMatrix(boneIdx)
        if bmat then
            return bmat:GetTranslation() + Vector(
                math.Rand(-10, 10),
                math.Rand(-10, 10),
                math.Rand(-5,   5)
            )
        end
    end
    -- Fallback: mid-body, NOT feet
    return ent:GetPos() + Vector(
        math.Rand(-15, 15),
        math.Rand(-15, 15),
        TORSO_Z
    )
end

-- ============================================================
--  PARTICLE SETTINGS  (identical to Hemo defaults)
-- ============================================================
local PARTICLE_SCALE     = 0.4
local PARTICLE_GRAVITY   = 1050
local PARTICLE_FORCE     = 200
local PARTICLE_LIFETIME  = 8
local PARTICLE_REPS      = 300
local PULSATE_MAX_FORCE  = 100
local PULSATE_SPEED_MULT = 8
local DECAL_SCALE        = 0.2
local MIN_STRENGTH       = 0.25

-- ============================================================
--  EFFECT
-- ============================================================
function EFFECT:Init(data)
    local ent = data:GetEntity()

    print("[GekkoBloodstream] Init — ent valid: " .. tostring(IsValid(ent)))

    if not IsValid(ent) then return end

    self.Ent             = ent
    self.reps            = PARTICLE_REPS
    self.StartTime       = CurTime()
    self.CurrentStrength = 1
    self.ExtraForce      = 0
    self:_CalcExtraForce()

    self.TimerName = "GekkoBloodStream_" .. ent:EntIndex() .. "_" .. math.floor(CurTime() * 1000)

    -- Emitter origin at torso height, not feet
    local emitOrigin = ent:GetPos() + Vector(0, 0, TORSO_Z)
    local emitter    = ParticleEmitter(emitOrigin, false)
    if not emitter then
        print("[GekkoBloodstream] ERROR: emitter nil")
        return
    end

    local spurt_delay = math.Rand(0.5, 5) / 60
    local self_ref    = self
    local reps_count  = self.reps

    timer.Create(self.TimerName, spurt_delay, self.reps, function()
        if not IsValid(ent) then
            emitter:Finish()
            timer.Remove(self_ref.TimerName)
            return
        end

        local emitPos  = GetEmissionPos(ent)
        local particle = emitter:Add(table.Random(BLOOD_MATS), emitPos)
        if not particle then return end

        -- Identical to Hemo: no SetColor, no SetAlpha
        particle:SetDieTime(PARTICLE_LIFETIME * (self_ref.CurrentStrength or 1))
        particle:SetStartSize(math.Rand(1.9, 3.8) * PARTICLE_SCALE)
        particle:SetEndSize(0)
        particle:SetStartLength(4   * PARTICLE_SCALE)
        particle:SetEndLength(100  * PARTICLE_SCALE)
        particle:SetGravity(Vector(0, 0, -PARTICLE_GRAVITY))

        local fwd   = ent:GetForward()
        local force = (PARTICLE_FORCE + (self_ref.ExtraForce or 0)) * (self_ref.CurrentStrength or 1)
        particle:SetVelocity(
            fwd * -force +
            Vector(
                math.Rand(-50, 50),
                math.Rand(-50, 50),
                math.Rand(10,  90)
            )
        )

        particle:SetCollide(true)
        particle:SetCollideCallback(function(_, pos, normal)
            util.DecalEx(
                DECAL_MATS[math.random(#DECAL_MATS)],
                Entity(0), pos, normal,
                Color(255, 255, 255),
                DECAL_SCALE, DECAL_SCALE
            )
        end)

        reps_count = reps_count - 1
        if reps_count <= 0 then emitter:Finish() end
    end)
end

function EFFECT:_CalcExtraForce()
    self.ExtraForce = PULSATE_MAX_FORCE * (1 + math.sin(CurTime() * PULSATE_SPEED_MULT))
end

function EFFECT:Think()
    if not timer.Exists(self.TimerName) then return false end
    local elapsed = CurTime() - self.StartTime
    local dietime = self.reps / 60
    self.CurrentStrength = math.Clamp(
        1 - (elapsed / dietime) * (1 - MIN_STRENGTH),
        MIN_STRENGTH, 1
    )
    self:_CalcExtraForce()
    return true
end

function EFFECT:Render() end
