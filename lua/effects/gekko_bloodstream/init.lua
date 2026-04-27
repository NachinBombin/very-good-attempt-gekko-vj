-- ============================================================
--  GEKKO BLOOD STREAM EFFECT  (client-side)  [DEBUG BUILD]
--  All values cranked to MAX for visibility testing.
--  Revert tunables when confirmed working.
-- ============================================================

-- ------------------------------------------------------------
--  TUNABLES  [DEBUG: everything huge]
-- ------------------------------------------------------------
local REPS_STREAM        = 600    -- DEBUG: double
local REPS_BURST         = 600    -- DEBUG: double
local REPS_MULTIPLIER    = 1.0
local SIZE_MULT          = 20.0   -- DEBUG: particles 20x larger
local FORCE_MULT         = 5.0    -- DEBUG: shoots far
local SPREAD_ANGLE       = 45     -- DEBUG: wide cone
local DENSITY            = 5.0    -- DEBUG: 5x more frequent

local PARTICLE_LENGTH_RAND     = { min = 500, max = 1000 }  -- DEBUG: very long
local PARTICLE_START_LEN_MULT  = 0.5                        -- DEBUG: fat start
local PARTICLE_SCALE           = 4.0                        -- DEBUG: 10x original
local PARTICLE_GRAVITY         = 400                        -- DEBUG: less gravity so stream flies far
local PARTICLE_FORCE           = 1500                       -- DEBUG: strong launch
local PULSATE_MAX_FORCE        = 500
local PULSATE_SPEED_MULT       = 8
local PARTICLE_FPS             = 60
local PARTICLE_LIFETIME        = 20   -- DEBUG: long lived
local DECAL_SCALE              = 5.0  -- DEBUG: huge decals
local IMPACT_CHANCE            = 1
local MIN_STRENGTH             = 0.1  -- DEBUG: stays strong longer

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

local function MakeMaterials(tbl)
    local out = {}
    for _, v in ipairs(tbl) do
        out[#out + 1] = (Material(v))
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
    if not IsValid(ent) then
        print("[GekkoBlood DEBUG] EFFECT:Init - entity invalid!")
        return
    end

    print("[GekkoBlood DEBUG] EFFECT:Init fired on", ent, "flags:", data:GetFlags())

    local flags = data:GetFlags()
    local repsBase   = (bit.band(flags, 1) == 1) and REPS_BURST or REPS_STREAM
    self.reps        = math.floor(repsBase * REPS_MULTIPLIER)

    local spurtDelay = math.Rand(0.01, 0.05) / (PARTICLE_FPS * DENSITY)  -- DEBUG: near-instant

    self.StartTime  = CurTime()
    self.CurrentPos = ent:GetPos()
    self:UpdateExtraForce()

    self.timerName = "GekkoBloodStreamTimer_" .. ent:EntIndex() .. "_" .. CurTime()

    local emitter = ParticleEmitter(self.CurrentPos, false)
    if not emitter then
        print("[GekkoBlood DEBUG] ParticleEmitter returned nil!")
        return
    end

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

        ent.CurrentPos = ent:GetPos()

        local length   = math.Rand(PARTICLE_LENGTH_RAND.min, PARTICLE_LENGTH_RAND.max)
        local particle = emitter:Add(table.Random(particleMats), ent.CurrentPos)
        if not particle then return end

        particle:SetDieTime(PARTICLE_LIFETIME * effectSelf.CurrentStrenght)
        particle:SetStartSize(math.Rand(40, 80) * PARTICLE_SCALE * SIZE_MULT)  -- DEBUG: huge
        particle:SetEndSize(math.Rand(10, 30) * SIZE_MULT)                     -- DEBUG: doesn't shrink to 0
        particle:SetStartLength(length * PARTICLE_SCALE * PARTICLE_START_LEN_MULT * SIZE_MULT)
        particle:SetEndLength(length * PARTICLE_SCALE * SIZE_MULT)
        particle:SetGravity(Vector(0, 0, -PARTICLE_GRAVITY))
        particle:SetColor(200, 0, 0)  -- DEBUG: explicit bright red
        particle:SetAlpha(255)        -- DEBUG: fully opaque

        -- DEBUG: shoot straight up so it's impossible to miss
        local upBlast = Vector(0, 0, 1) * PARTICLE_FORCE * FORCE_MULT * effectSelf.CurrentStrenght
        local fwdBlast = ent:GetForward() * -(PARTICLE_FORCE + effectSelf.ExtraForce) *
            effectSelf.CurrentStrenght * FORCE_MULT
        particle:SetVelocity(upBlast + fwdBlast)

        particle:SetCollide(true)
        particle:SetCollideCallback(function(_, pos, normal)
            local dSize = DECAL_SCALE * SIZE_MULT
            util.DecalEx(table.Random(decalMats), Entity(0), pos, normal,
                Color(255, 255, 255), dSize, dSize)
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
