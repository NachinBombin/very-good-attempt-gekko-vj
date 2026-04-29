-- ============================================================
--  gekko_bloodstream.lua
--  Standalone blood stream effect for VJ Gekko
--  Architecture mirrors Hemo-fluid-stream (NachinBombin)
-- ============================================================

-- ============================================================
--  MATERIAL PRE-CACHE  (FILE SCOPE — outside every function)
--
--  particle/smokesprites_* are UnlitGeneric ADDITIVE textures
--  guaranteed in every GMod/HL2 install.  Black pixels become
--  fully transparent.  SetColor(R,0,0) tints them dark red =
--  blood globs with zero black-square fringing.
-- ============================================================
local BLOOD_MATS = {
    Material("particle/smokesprites_0001"),
    Material("particle/smokesprites_0002"),
    Material("particle/smokesprites_0003"),
    Material("particle/smokesprites_0004"),
    Material("particle/smokesprites_0005"),
    Material("particle/smokesprites_0006"),
    Material("particle/smokesprites_0007"),
    Material("particle/smokesprites_0008"),
    Material("particle/smokesprites_0009"),
}

-- Decal materials for wall / floor splats on collision
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
--  Each burst picks one at random so blood sprays from
--  different body locations rather than one single point.
-- ============================================================
local EMISSION_BONES = {
    "b_spine3",       -- chest / upper torso
    "b_pelvis",       -- lower torso
    "b_pedestal",     -- mid body
    "b_r_hippiston1", -- right hip
    "b_l_hippiston1", -- left hip
}

local function GetEmissionPos(ent)
    -- Try a random bone from the list first
    local boneName = EMISSION_BONES[math.random(#EMISSION_BONES)]
    local boneIdx  = ent:LookupBone(boneName)
    if boneIdx and boneIdx >= 0 then
        local bmat = ent:GetBoneMatrix(boneIdx)
        if bmat then
            -- Small random jitter so even the same bone varies slightly
            local p = bmat:GetTranslation()
            return p + Vector(
                math.Rand(-12, 12),
                math.Rand(-12, 12),
                math.Rand(-8, 8)
            )
        end
    end
    -- Fallback: random offset from entity origin
    return ent:GetPos() + Vector(
        math.Rand(-20, 20),
        math.Rand(-20, 20),
        math.Rand(30, 120)
    )
end

-- ============================================================
--  PARTICLE SETTINGS  (matching Hemo defaults)
-- ============================================================
local PARTICLE_SCALE      = 0.4
local PARTICLE_GRAVITY    = 1050
local PARTICLE_FORCE      = 200
local PARTICLE_LIFETIME   = 8
local PARTICLE_REPS       = 300
local PULSATE_MAX_FORCE   = 100
local PULSATE_SPEED_MULT  = 8
local DECAL_SCALE         = 0.2
local MIN_STRENGTH        = 0.25

-- Blood colour — deep arterial red
local BLOOD_R = 180
local BLOOD_G = 0
local BLOOD_B = 0

-- ============================================================
--  EFFECT
-- ============================================================
function EFFECT:Init(data)
    local ent = data:GetEntity()
    if not IsValid(ent) then return end

    self.Ent            = ent
    self.reps           = PARTICLE_REPS
    self.StartTime      = CurTime()
    self.CurrentStrength = 1
    self:_CalcExtraForce()

    -- Unique name avoids timer collisions in multiplayer
    self.TimerName = "GekkoBloodStream_" .. ent:EntIndex() .. "_" .. math.floor(CurTime() * 1000)

    -- Emitter anchored to entity origin; false = 2D mode (matches Hemo)
    local emitter = ParticleEmitter(ent:GetPos(), false)
    if not emitter then return end

    -- Spurt cadence identical to Hemo (~60 fps base)
    local spurt_delay = math.Rand(0.5, 5) / 60

    local self_ref   = self
    local reps_count = self.reps

    timer.Create(self.TimerName, spurt_delay, self.reps, function()
        if not IsValid(ent) then
            emitter:Finish()
            timer.Remove(self_ref.TimerName)
            return
        end

        -- Each burst emits from a DIFFERENT body location
        local emitPos = GetEmissionPos(ent)

        local particle = emitter:Add(
            BLOOD_MATS[math.random(#BLOOD_MATS)],
            emitPos
        )
        if not particle then return end

        -- Size: matches Hemo scale
        local sz = math.Rand(1.9, 3.8) * PARTICLE_SCALE
        particle:SetStartSize(sz)
        particle:SetEndSize(0)

        -- Length stretch gives the "droplet trail" look
        particle:SetStartLength(4  * PARTICLE_SCALE)
        particle:SetEndLength(100 * PARTICLE_SCALE)

        particle:SetDieTime(PARTICLE_LIFETIME * (self_ref.CurrentStrength or 1))

        -- Tint the additive sprite red — black pixels vanish, white pixels go red
        particle:SetColor(BLOOD_R, BLOOD_G, BLOOD_B)
        particle:SetAlpha(230)

        particle:SetGravity(Vector(0, 0, -PARTICLE_GRAVITY))

        -- Velocity: forward arc from NPC + pulsating force + small spread
        local fwd   = ent:GetForward()
        local force = (PARTICLE_FORCE + (self_ref.ExtraForce or 0)) * (self_ref.CurrentStrength or 1)
        particle:SetVelocity(
            fwd * -force +
            Vector(
                math.Rand(-50, 50),
                math.Rand(-50, 50),
                math.Rand(10, 90)
            )
        )

        -- Collide and leave a decal on whatever surface it hits
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
        if reps_count <= 0 then
            emitter:Finish()
        end
    end)
end

-- Sinusoidal force pulsation — makes the stream pump rather than spray uniformly
function EFFECT:_CalcExtraForce()
    self.ExtraForce = PULSATE_MAX_FORCE * (1 + math.sin(CurTime() * PULSATE_SPEED_MULT))
end

function EFFECT:Think()
    if not timer.Exists(self.TimerName) then
        return false
    end

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
