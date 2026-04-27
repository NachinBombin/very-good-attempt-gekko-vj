-- ============================================================
--  GEKKO BLOOD STREAM EFFECT  (client-side)
--  Registered as effect name "gekko_bloodstream".
--
--  Ported 1-to-1 from bloodstreameffectzippy.lua.
--  All ConVar reads replaced with hardcoded local constants.
--
--  EFFECT flags:
--    flags & 1  == 1  →  burst  (fewer reps, short pop)
--    flags & 1  == 0  →  stream (more reps, sustained)
-- ============================================================

-- ------------------------------------------------------------
--  TUNABLES  (was ConVars in the original)
-- ------------------------------------------------------------
local REPS_STREAM        = 300    -- particle repetitions for stream mode
local REPS_BURST         = 150    -- particle repetitions for burst mode
local REPS_MULTIPLIER    = 1.0    -- global reps scale
local SIZE_MULT          = 1.0    -- particle size multiplier
local FORCE_MULT         = 1.0    -- launch force multiplier
local SPREAD_ANGLE       = 5      -- cone spread in degrees (0 = straight)
local DENSITY            = 1.0    -- spurt frequency; lower = more frequent

local PARTICLE_LENGTH_RAND = { min = -100, max = 100 }
local PARTICLE_START_LEN_MULT = 0.1
local PARTICLE_SCALE     = 0.4
local PARTICLE_GRAVITY   = 1050
local PARTICLE_FORCE     = 200
local PULSATE_MAX_FORCE  = 100
local PULSATE_SPEED_MULT = 8
local PARTICLE_FPS       = 60
local PARTICLE_LIFETIME  = 8
local STREAM_PARTICLE_LIFETIME = 8
local BURST_PARTICLE_LIFETIME  = 8
local DECAL_SCALE        = 0.2
local IMPACT_CHANCE      = 1      -- 1-in-N; 1 = always
local MIN_STRENGTH       = 0.25

local BLOOD_SOUND_VOLUME  = 1.0
local SQUIRT_SOUND_VOLUME = 1.0
local SOUND_LEVEL_DRIP    = 70
local SOUND_LEVEL_SQUIRT  = 35

-- ------------------------------------------------------------
--  ASSET TABLES
-- ------------------------------------------------------------
local PARTICLE_MATS_RAW = { "decals/blood_trail" }
local DECAL_MATS_RAW = {
    "decals/Blood1", "decals/Blood3", "decals/Blood4",
    "decals/Blood5", "decals/Blood6", "decals/Blood2",
}

local DRIP_SOUNDS = {
    "blood/splashing/drip1.wav",  "blood/splashing/drip2.wav",
    "blood/splashing/drip3.wav",  "blood/splashing/drip4.wav",
    "blood/splashing/drip5.wav",
    "blood/splashing/drips1.wav", "blood/splashing/drips2.wav",
    "blood/splashing/drips3.wav", "blood/splashing/drips4.wav",
    "blood/splashing/drips5.wav", "blood/splashing/drips6.wav",
    "blood/splashing/spattergrass1.wav", "blood/splashing/spattergrass2.wav",
    "blood/splashing/spattergrass3.wav",
    "blood/splashing/spatterhard1.wav",  "blood/splashing/spatterhard2.wav",
    "blood/splashing/spatterhard3.wav",
    "blood/splashing/driplowpass1.wav",  "blood/splashing/driplowpass2.wav",
    "blood/splashing/driplowpass3.wav",  "blood/splashing/driplowpass4.wav",
    "blood/splashing/driplowpass5.wav",
}
local SQUIRT_SOUNDS = {
    "squirting/arterysquirt1.wav", "squirting/arterysquirt2.wav",
    "squirting/arterysquirt3.wav", "squirting/arterysquirt3.wav",
    "squirting/arterysquirt2.wav", "squirting/arterysquirt1.wav",
    "squirting/arterysquirt2.wav", "squirting/arterysquirt2.wav",
    "squirting/arterysquirt3.wav", "squirting/arterysquirt1.wav",
    "squirting/arterysquirt3.wav", "squirting/arterysquirt2.wav",
}

-- Pre-cache materials into IMaterial objects once (mirrors makematerialstbl)
local function MakeMaterials(tbl)
    local out = {}
    for _, v in ipairs(tbl) do
        table.insert(out, Material(v))
    end
    return out
end

local particleMats = MakeMaterials(PARTICLE_MATS_RAW)
local decalMats    = MakeMaterials(DECAL_MATS_RAW)

-- ------------------------------------------------------------
--  EFFECT
-- ------------------------------------------------------------
local EFFECT = {}

function EFFECT:Init(data)
    local ent   = data:GetEntity()
    if not IsValid(ent) then return end

    local flags = data:GetFlags()

    -- Reps: burst flag = bit 0 set
    local repsBase   = ((flags & 1) == 1) and REPS_BURST or REPS_STREAM
    self.reps        = math.floor(repsBase * REPS_MULTIPLIER)

    -- Spurt delay from density tunable
    local spurtDelay = math.Rand(0.5, 5 * PARTICLE_FPS * DENSITY)

    self.StartTime   = CurTime()
    self.CurrentPos  = ent:GetPos()
    self:UpdateExtraForce()

    -- Unique timer name per entity instance
    self.timerName = "GekkoBloodStreamTimer_" .. ent:EntIndex() .. "_" .. CurTime()

    local emitter = ParticleEmitter(self.CurrentPos, false)
    if not emitter then return end

    -- Initial squirt sound
    sound.Play(table.Random(SQUIRT_SOUNDS), ent:GetPos(), SOUND_LEVEL_SQUIRT,
        math.Rand(95, 105), SQUIRT_SOUND_VOLUME)

    -- Capture locals for timer closure
    local effectSelf = self
    local reps       = self.reps

    timer.Create(self.timerName, spurtDelay, reps, function()
        if not IsValid(ent) or not emitter then
            if emitter then emitter:Finish() end
            timer.Remove(effectSelf.timerName)
            return
        end

        -- Per-rep squirt sound
        sound.Play(table.Random(SQUIRT_SOUNDS), ent:GetPos(), SOUND_LEVEL_SQUIRT,
            math.Rand(95, 105), SQUIRT_SOUND_VOLUME)

        ent.CurrentPos = ent:GetPos()

        local length = math.Rand(PARTICLE_LENGTH_RAND.min, PARTICLE_LENGTH_RAND.max)

        local particle = emitter:Add(table.Random(particleMats), ent.CurrentPos)
        if not particle then return end

        particle:SetDieTime(PARTICLE_LIFETIME * effectSelf.CurrentStrenght)
        particle:SetStartSize(math.Rand(1.9, 3.8) * PARTICLE_SCALE * SIZE_MULT)
        particle:SetEndSize(0)
        particle:SetStartLength(length * PARTICLE_SCALE * PARTICLE_START_LEN_MULT * SIZE_MULT)
        particle:SetEndLength(length * PARTICLE_SCALE * SIZE_MULT)
        particle:SetGravity(Vector(0, 0, -PARTICLE_GRAVITY))

        -- Base velocity with force multiplier
        local baseVelocity = ent:GetForward() * (-PARTICLE_FORCE + effectSelf.ExtraForce) *
            effectSelf.CurrentStrenght * FORCE_MULT

        -- Spread cone
        if SPREAD_ANGLE > 0 then
            local spreadRad  = math.rad(SPREAD_ANGLE)
            local randPitch  = math.Rand(-spreadRad, spreadRad)
            local randYaw    = math.Rand(-spreadRad, spreadRad)
            local fwd   = ent:GetForward()
            local right = ent:GetRight()
            local up    = ent:GetUp()
            local spreadDir = fwd + right * math.sin(randYaw) + up * math.sin(randPitch)
            spreadDir:Normalize()
            local magnitude = baseVelocity:Length()
            baseVelocity    = spreadDir * (-magnitude)
        end

        particle:SetVelocity(baseVelocity)
        particle:SetCollide(true)
        particle:SetCollideCallback(function(_, pos, normal)
            if math.random(1, IMPACT_CHANCE) == 1 and
               (effectSelf.CurrentStrenght or 0) > MIN_STRENGTH - 0.2 then
                sound.Play(table.Random(DRIP_SOUNDS), pos, SOUND_LEVEL_DRIP,
                    math.Rand(95, 105), BLOOD_SOUND_VOLUME)
                local dSize = DECAL_SCALE * SIZE_MULT
                util.DecalEx(table.Random(decalMats), Entity(0), pos, normal,
                    Color(255, 255, 255), dSize, dSize)
            end
        end)

        if timer.RepsLeft(effectSelf.timerName) == 0 then
            emitter:Finish()
        end
    end)
end

function EFFECT:UpdateExtraForce()
    self.ExtraForce      = PULSATE_MAX_FORCE * (1 - math.sin(CurTime() * PULSATE_SPEED_MULT))
    self.CurrentStrenght = 1
end

function EFFECT:Think()
    if timer.Exists(self.timerName) then
        local lifetime = CurTime() - self.StartTime
        local dieTime  = self.reps * (1 / PARTICLE_FPS) * self.CurrentStrenght
        self.CurrentStrenght = math.Clamp(
            1 - (lifetime / (dieTime + 0.001)) * (1 - MIN_STRENGTH),
            0, 1
        )
        self:UpdateExtraForce()
        return true
    end
    return false
end

function EFFECT:Render() end

effects.Register(EFFECT, "gekko_bloodstream")

-- Cleanup timers when a dummy prop is removed (multiplayer stability)
hook.Add("EntityRemoved", "GekkoBloodStreamCleanup", function(ent)
    if ent.gekkoBloodTimerName then
        timer.Remove(ent.gekkoBloodTimerName)
    end
end)
