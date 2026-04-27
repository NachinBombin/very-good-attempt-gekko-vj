-- ============================================================
--  GEKKO BLOOD STREAM EFFECT  (client-side)
--  Registered as GMod EFFECT "gekko_bloodstream".
--  Lives at lua/effects/gekko_bloodstream/init.lua  <- correct path.
--
--  EFFECT flags:
--    bit.band(flags,1) == 1  ->  burst  (fewer reps, short pop)
--    bit.band(flags,1) == 0  ->  stream (more reps, sustained)
-- ============================================================

-- ------------------------------------------------------------
--  TUNABLES
-- ------------------------------------------------------------
local REPS_STREAM        = 300
local REPS_BURST         = 150
local REPS_MULTIPLIER    = 1.0
local SIZE_MULT          = 1.0
local FORCE_MULT         = 1.0
local SPREAD_ANGLE       = 5
local DENSITY            = 1.0

local PARTICLE_LENGTH_RAND     = { min = 100, max = 100 }
local PARTICLE_START_LEN_MULT  = 0.1
local PARTICLE_SCALE           = 0.4
local PARTICLE_GRAVITY         = 1050
local PARTICLE_FORCE           = 200
local PULSATE_MAX_FORCE        = 100
local PULSATE_SPEED_MULT       = 8
local PARTICLE_FPS             = 60
local PARTICLE_LIFETIME        = 8
local DECAL_SCALE              = 0.2
local IMPACT_CHANCE            = 1
local MIN_STRENGTH             = 0.25

local BLOOD_SOUND_VOLUME  = 1.0
local SQUIRT_SOUND_VOLUME = 1.0
local SOUND_LEVEL_DRIP    = 70
local SOUND_LEVEL_SQUIRT  = 35

-- ------------------------------------------------------------
--  ASSET TABLES
-- ------------------------------------------------------------
local PARTICLE_MATS_RAW = { "decals/trail" }
local DECAL_MATS_RAW = {
    "decals/Blood1", "decals/Blood3", "decals/Blood4",
    "decals/Blood5", "decals/Blood6", "decals/Blood2",
    "decals/Blood3",
}

local DRIP_SOUNDS = {
    "bloodsplashing/drip_1.wav",          "bloodsplashing/drip_2.wav",
    "bloodsplashing/drip_3.wav",          "bloodsplashing/drip_4.wav",
    "bloodsplashing/drip_5.wav",
    "bloodsplashing/drips_1.wav",         "bloodsplashing/drips_2.wav",
    "bloodsplashing/drips_3.wav",         "bloodsplashing/drips_4.wav",
    "bloodsplashing/drips_5.wav",         "bloodsplashing/drips_6.wav",
    "bloodsplashing/spatter_grass_1.wav", "bloodsplashing/spatter_grass_2.wav",
    "bloodsplashing/spatter_grass_3.wav",
    "bloodsplashing/spatter_hard_1.wav",  "bloodsplashing/spatter_hard_2.wav",
    "bloodsplashing/spatter_hard_3.wav",
    "bloodsplashing/drip_lowpass_1.wav",  "bloodsplashing/drip_lowpass_2.wav",
    "bloodsplashing/drip_lowpass_3.wav",  "bloodsplashing/drip_lowpass_4.wav",
    "bloodsplashing/drip_lowpass_5.wav",
}
local SQUIRT_SOUNDS = {
    "squirting/artery_squirt_1.wav", "squirting/artery_squirt_2.wav",
    "squirting/artery_squirt_3.wav", "squirting/artery_squirt_3.wav",
    "squirting/artery_squirt_2.wav", "squirting/artery_squirt_1.wav",
    "squirting/artery_squirt_2.wav", "squirting/artery_squirt_2.wav",
    "squirting/artery_squirt_3.wav", "squirting/artery_squirt_1.wav",
    "squirting/artery_squirt_3.wav", "squirting/artery_squirt_2.wav",
}

-- Material() returns (IMaterial, bool) in some GMod builds.
-- Wrapping in () clamps it to exactly 1 return value so
-- table.insert(out, val) never receives a spurious 3rd argument
-- that Lua would interpret as the positional form table.insert(t, pos, val).
local function MakeMaterials(tbl)
    local out = {}
    for _, v in ipairs(tbl) do
        out[#out + 1] = (Material(v))   -- () clamps multi-return to 1 value
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
    local ent = data:GetEntity()
    if not IsValid(ent) then return end

    local flags = data:GetFlags()

    -- LuaJIT / Lua 5.1: use bit.band() not &
    local repsBase   = (bit.band(flags, 1) == 1) and REPS_BURST or REPS_STREAM
    self.reps        = math.floor(repsBase * REPS_MULTIPLIER)

    local spurtDelay = math.Rand(0.5, 5) / (PARTICLE_FPS * DENSITY)

    self.StartTime  = CurTime()
    self.CurrentPos = ent:GetPos()
    self:UpdateExtraForce()

    self.timerName = "GekkoBloodStreamTimer_" .. ent:EntIndex() .. "_" .. CurTime()

    local emitter = ParticleEmitter(self.CurrentPos, false)
    if not emitter then return end

    sound.Play(table.Random(SQUIRT_SOUNDS), ent:GetPos(), SOUND_LEVEL_SQUIRT,
        math.Rand(95, 105), SQUIRT_SOUND_VOLUME)

    local effectSelf = self
    local reps       = self.reps

    timer.Create(self.timerName, spurtDelay, reps, function()
        if not IsValid(ent) or not emitter then
            if emitter then emitter:Finish() end
            timer.Remove(effectSelf.timerName)
            return
        end

        sound.Play(table.Random(SQUIRT_SOUNDS), ent:GetPos(), SOUND_LEVEL_SQUIRT,
            math.Rand(95, 105), SQUIRT_SOUND_VOLUME)

        ent.CurrentPos = ent:GetPos()

        local length   = math.Rand(PARTICLE_LENGTH_RAND.min, PARTICLE_LENGTH_RAND.max)
        local particle = emitter:Add(table.Random(particleMats), ent.CurrentPos)
        if not particle then return end

        particle:SetDieTime(PARTICLE_LIFETIME * effectSelf.CurrentStrenght)
        particle:SetStartSize(math.Rand(1.9, 3.8) * PARTICLE_SCALE * SIZE_MULT)
        particle:SetEndSize(0)
        particle:SetStartLength(length * PARTICLE_SCALE * PARTICLE_START_LEN_MULT * SIZE_MULT)
        particle:SetEndLength(length * PARTICLE_SCALE * SIZE_MULT)
        particle:SetGravity(Vector(0, 0, -PARTICLE_GRAVITY))

        local baseVelocity = ent:GetForward() * -(PARTICLE_FORCE + effectSelf.ExtraForce) *
            effectSelf.CurrentStrenght * FORCE_MULT

        if SPREAD_ANGLE > 0 then
            local spreadRad = math.rad(SPREAD_ANGLE)
            local randPitch = math.Rand(-spreadRad, spreadRad)
            local randYaw   = math.Rand(-spreadRad, spreadRad)
            local fwd       = ent:GetForward()
            local right     = ent:GetRight()
            local up        = ent:GetUp()
            local spreadDir = fwd + right * math.sin(randYaw) + up * math.sin(randPitch)
            spreadDir:Normalize()
            baseVelocity = spreadDir * -baseVelocity:Length()
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
    self.ExtraForce      = PULSATE_MAX_FORCE * (1 + math.sin(CurTime() * PULSATE_SPEED_MULT))
    self.CurrentStrenght = 1
end

function EFFECT:Think()
    if timer.Exists(self.timerName) then
        local lifetime = CurTime() - self.StartTime
        local dieTime  = self.reps * (1 / PARTICLE_FPS)
        self.CurrentStrenght = math.Clamp(
            1 - (lifetime / dieTime) * (1 - MIN_STRENGTH),
            0, 1
        )
        self:UpdateExtraForce()
        return true
    end
    return false
end

function EFFECT:Render() end

effects.Register(EFFECT, "gekko_bloodstream")

hook.Add("EntityRemoved", "GekkoBloodStreamCleanup", function(ent)
    if ent.gekkoBloodTimerName then
        timer.Remove(ent.gekkoBloodTimerName)
    end
end)
