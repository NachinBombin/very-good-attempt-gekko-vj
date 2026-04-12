include("shared.lua")

-- ============================================================
--  npc_vj_gekko_nikita  /  cl_init.lua
--
--  Visual phases:
--    0.0 - 1.9s  : WHITE SMOKE TRAIL only (fat missile plume, no flame/light)
--    1.9s+       : Full flame + sparks + dlight + stabilisers
--    1.9 - 2.9s  : Smoke trail continues, then naturally fades out
--                  (overlap = 1s, handled via _smokeFadeEnd timestamp)
-- ============================================================

-- ----------------------------------------------------------------
--  TIMING
-- ----------------------------------------------------------------
local FLAME_DELAY   = 1.9   -- seconds before flame / light turn on
local SMOKE_FADE    = 1.0   -- extra seconds smoke keeps emitting after flame starts
--  => smoke emits from t=0 to t=(FLAME_DELAY + SMOKE_FADE)

-- ----------------------------------------------------------------
--  SMOKE TRAIL TUNING  (pre-ignition / overlap period)
-- ----------------------------------------------------------------
local SMOKE_EMIT_CHANCE  = 0.85   -- probability per Think tick
local SMOKE_SIZE_MIN     = 55     -- large puff — missile-scale vs grenade
local SMOKE_SIZE_MAX     = 90
local SMOKE_END_MIN      = 110
local SMOKE_END_MAX      = 180
local SMOKE_ALPHA_START  = 200
local SMOKE_ALPHA_END    = 0
local SMOKE_SPEED_MIN    = 35
local SMOKE_SPEED_MAX    = 85
local SMOKE_DIE_MIN      = 0.55
local SMOKE_DIE_MAX      = 1.10
local SMOKE_SPREAD       = 14    -- lateral randomness on emit position
local SMOKE_BACK_OFFSET  = 55    -- same back-offset as the exhaust flame

-- ----------------------------------------------------------------
--  STABILIZER TUNING
-- ----------------------------------------------------------------
local STAB_NOZZLE_DIST   = 18
local STAB_NOZZLE_BACK   = 10
local STAB_JET_LEN       = 55
local STAB_JET_SPREAD    = 5
local STAB_SIZE_MIN      = 3.6
local STAB_SIZE_MAX      = 6.4
local STAB_ALPHA         = 210
local STAB_DIE_MIN       = 0.06
local STAB_DIE_MAX       = 0.14
local STAB_FIRE_CHANCE   = 0.35
local STAB_DRIFT_THRESH  = 30
local STAB_DRIFT_BOOST   = 0.70

function ENT:Initialize()
    self.NikitaEmitter  = ParticleEmitter(self:GetPos(), false)
    self.StabEmitter    = ParticleEmitter(self:GetPos(), false)
    self.SmokeEmitter   = ParticleEmitter(self:GetPos(), false)
    self._spawnTime     = CurTime()
end

function ENT:Draw()
    self:DrawModel()
end

function ENT:Think()
    if not IsValid(self.NikitaEmitter) then return end

    local now        = CurTime()
    local age        = now - (self._spawnTime or now)
    local flameOn    = age >= FLAME_DELAY
    local smokeOn    = age < (FLAME_DELAY + SMOKE_FADE)

    local pos        = self:GetPos()
    local fwd        = self:GetForward()
    local backDir    = -fwd
    local exhaustPos = pos + backDir * SMOKE_BACK_OFFSET
    local boost      = self:GetNWFloat("NikitaBoost", 0)

    self.NikitaEmitter:SetPos(pos)
    if IsValid(self.SmokeEmitter) then
        self.SmokeEmitter:SetPos(pos)
    end

    -- --------------------------------------------------------
    --  WHITE SMOKE TRAIL  (active before flame; overlaps 1s after)
    -- --------------------------------------------------------
    if smokeOn and IsValid(self.SmokeEmitter) then
        if math.random() < SMOKE_EMIT_CHANCE then
            local spread = VectorRand() * SMOKE_SPREAD
            spread.x = spread.x * 0.4   -- tighten spread along fwd axis
            local part = self.SmokeEmitter:Add(
                "particle/particle_smokegrenade",
                exhaustPos + spread
            )
            if part then
                part:SetVelocity(backDir * math.Rand(SMOKE_SPEED_MIN, SMOKE_SPEED_MAX)
                                 + VectorRand() * 10)
                part:SetDieTime(math.Rand(SMOKE_DIE_MIN, SMOKE_DIE_MAX))
                part:SetStartAlpha(SMOKE_ALPHA_START)
                part:SetEndAlpha(SMOKE_ALPHA_END)
                part:SetStartSize(math.Rand(SMOKE_SIZE_MIN, SMOKE_SIZE_MAX))
                part:SetEndSize(math.Rand(SMOKE_END_MIN, SMOKE_END_MAX))
                part:SetColor(240, 240, 240)
                part:SetRoll(math.Rand(0, 360))
                part:SetRollDelta(math.Rand(-1.5, 1.5))
                part:SetGravity(Vector(0, 0, 22))
                part:SetCollide(false)
            end
        end
    end

    -- Everything below this point only runs after FLAME_DELAY
    if not flameOn then return end

    -- --------------------------------------------------------
    --  Dynamic light: orange core, swells during boost
    -- --------------------------------------------------------
    local dlight = DynamicLight(self:EntIndex())
    if dlight then
        dlight.pos        = exhaustPos
        dlight.r          = 255
        dlight.g          = 120
        dlight.b          = 20
        dlight.brightness = 3
        dlight.Decay      = 1200
        dlight.Size       = Lerp(boost, 180, 260)
        dlight.DieTime    = CurTime() + 0.05
    end

    -- --------------------------------------------------------
    --  Orange flame core
    -- --------------------------------------------------------
    for i = 1, 4 do
        local part = self.NikitaEmitter:Add(
            "particles/flamelet" .. math.random(1, 5),
            exhaustPos + VectorRand() * 6
        )
        if part then
            part:SetVelocity(backDir * math.Rand(80, 200) + VectorRand() * 18)
            part:SetDieTime(math.Rand(0.08, 0.18))
            part:SetStartAlpha(220)
            part:SetEndAlpha(0)
            part:SetStartSize(math.Rand(18, 32))
            part:SetEndSize(math.Rand(4, 10))
            part:SetColor(255, math.random(100, 180), 0)
            part:SetRoll(math.Rand(0, 360))
            part:SetRollDelta(math.Rand(-2, 2))
            part:SetGravity(Vector(0, 0, 12))
            part:SetCollide(false)
        end
    end

    -- --------------------------------------------------------
    --  Fuchsia flame layer (swells +10 at full boost)
    -- --------------------------------------------------------
    local fuchsiaMin = Lerp(boost, 35, 45)
    local fuchsiaMax = Lerp(boost, 45, 55)

    for i = 1, 3 do
        local part = self.NikitaEmitter:Add(
            "particles/flamelet" .. math.random(1, 5),
            exhaustPos + VectorRand() * 8
        )
        if part then
            part:SetVelocity(backDir * math.Rand(60, 160) + VectorRand() * 22)
            part:SetDieTime(math.Rand(0.10, 0.22))
            part:SetStartAlpha(180)
            part:SetEndAlpha(0)
            part:SetStartSize(math.Rand(fuchsiaMin, fuchsiaMax))
            part:SetEndSize(math.Rand(2, 8))
            part:SetColor(220, 0, 200)
            part:SetRoll(math.Rand(0, 360))
            part:SetRollDelta(math.Rand(-3, 3))
            part:SetGravity(Vector(0, 0, 8))
            part:SetCollide(false)
        end
    end

    -- --------------------------------------------------------
    --  Sparks
    -- --------------------------------------------------------
    for i = 1, 3 do
        local part = self.NikitaEmitter:Add(
            "effects/spark",
            exhaustPos + VectorRand() * 4
        )
        if part then
            part:SetVelocity(backDir * math.Rand(200, 500) + VectorRand() * 40)
            part:SetDieTime(math.Rand(0.12, 0.30))
            part:SetStartAlpha(255)
            part:SetEndAlpha(0)
            part:SetStartSize(math.Rand(1, 3))
            part:SetEndSize(0)
            part:SetColor(255, 230, 180)
            part:SetGravity(Vector(0, 0, -280))
            part:SetCollide(true)
            part:SetBounce(0.2)
        end
    end

    -- --------------------------------------------------------
    --  Smoke wisp during flame phase (1-in-3 chance per tick)
    --  (lighter accent wisps, smaller than the pre-ignition plume)
    -- --------------------------------------------------------
    if math.random(1, 3) == 1 then
        local part = self.NikitaEmitter:Add(
            "particle/particle_smokegrenade",
            exhaustPos + backDir * math.Rand(5, 20)
        )
        if part then
            part:SetVelocity(backDir * math.Rand(20, 60) + VectorRand() * 10)
            part:SetDieTime(math.Rand(0.4, 0.8))
            part:SetStartAlpha(40)
            part:SetEndAlpha(0)
            part:SetStartSize(math.Rand(8, 16))
            part:SetEndSize(math.Rand(20, 40))
            part:SetColor(180, 180, 180)
            part:SetRoll(math.Rand(0, 360))
            part:SetRollDelta(math.Rand(-1, 1))
            part:SetGravity(Vector(0, 0, 20))
            part:SetCollide(false)
        end
    end

    -- --------------------------------------------------------
    --  STABILIZER THRUSTERS
    -- --------------------------------------------------------
    if not IsValid(self.StabEmitter) then return end
    self.StabEmitter:SetPos(pos)

    local right = self:GetRight()
    local up    = self:GetUp()
    local nozzleBase = pos + backDir * STAB_NOZZLE_BACK

    local nozzles = {
        {  right,  nozzleBase + right * STAB_NOZZLE_DIST },
        { -right,  nozzleBase - right * STAB_NOZZLE_DIST },
        {  up,     nozzleBase + up    * STAB_NOZZLE_DIST },
        { -up,     nozzleBase - up    * STAB_NOZZLE_DIST },
    }

    local vel      = self:GetVelocity()
    local driftX   = vel.x
    local driftY   = vel.y
    local driftLen = math.sqrt(driftX * driftX + driftY * driftY)
    local driftVec = Vector(0, 0, 0)
    if driftLen > STAB_DRIFT_THRESH then
        driftVec = Vector(driftX / driftLen, driftY / driftLen, 0)
    end

    for idx, nozzle in ipairs(nozzles) do
        local outDir  = nozzle[1]
        local nozzPos = nozzle[2]
        local drift2D = Vector(outDir.x, outDir.y, 0)
        local dot     = drift2D:Dot(driftVec)
        local chance  = STAB_FIRE_CHANCE
        if dot < -0.35 then chance = chance + STAB_DRIFT_BOOST end

        if math.random() < chance then
            local part = self.StabEmitter:Add(
                "particles/flamelet" .. math.random(1, 5),
                nozzPos + VectorRand() * 2
            )
            if part then
                local jitter = Vector(
                    math.Rand(-STAB_JET_SPREAD, STAB_JET_SPREAD),
                    math.Rand(-STAB_JET_SPREAD, STAB_JET_SPREAD),
                    math.Rand(-STAB_JET_SPREAD, STAB_JET_SPREAD)
                )
                part:SetVelocity(outDir * math.Rand(STAB_JET_LEN * 0.7, STAB_JET_LEN) + jitter)
                part:SetDieTime(math.Rand(STAB_DIE_MIN, STAB_DIE_MAX))
                part:SetStartAlpha(STAB_ALPHA)
                part:SetEndAlpha(0)
                part:SetStartSize(math.Rand(STAB_SIZE_MIN, STAB_SIZE_MAX))
                part:SetEndSize(0)
                part:SetColor(255, 255, 255)
                part:SetRoll(math.Rand(0, 360))
                part:SetRollDelta(math.Rand(-2, 2))
                part:SetGravity(Vector(0, 0, 0))
                part:SetCollide(false)
            end
        end
    end
end

function ENT:OnRemove()
    if IsValid(self.NikitaEmitter) then
        self.NikitaEmitter:Finish()
    end
    if IsValid(self.StabEmitter) then
        self.StabEmitter:Finish()
    end
    if IsValid(self.SmokeEmitter) then
        self.SmokeEmitter:Finish()
    end
end
