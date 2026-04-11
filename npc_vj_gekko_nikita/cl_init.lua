include("shared.lua")

-- ============================================================
--  npc_vj_gekko_nikita  /  cl_init.lua
--
--  Exhaust FX ported from entities/sent_gekko_nikita/cl_init.lua
--  (nikita-pathfinder-v2 branch).
--
--  Layers:
--    1. Orange flame core        (flamelet1-5, 4 particles/tick)
--    2. Fuchsia flame layer      (flamelet1-5, 3 particles/tick,
--                                  swells +10 units at NikitaBoost=1)
--    3. Sparks                   (effects/spark, 3/tick, gravity+bounce)
--    4. Smoke wisps              (particle_smokegrenade, 1-in-3 chance)
--    5. Dynamic light            (orange core, size 180->260 with boost)
--    6. Stabilizer thrusters     (4 cardinal nozzles, white flamelets,
--                                  fire opposite to XY drift, random flicker)
-- ============================================================

-- ----------------------------------------------------------------
--  STABILIZER TUNING
-- ----------------------------------------------------------------
local STAB_NOZZLE_DIST   = 18      -- radial offset from missile centre
local STAB_NOZZLE_BACK   = 10      -- how far back along the body axis
local STAB_JET_LEN       = 55      -- how far the particle travels outward
local STAB_JET_SPREAD    = 5       -- lateral randomness
local STAB_SIZE_MIN      = 3.6     -- 0.2 * 18  (main flame min = 18)
local STAB_SIZE_MAX      = 6.4     -- 0.2 * 32  (main flame max = 32)
local STAB_ALPHA         = 210
local STAB_DIE_MIN       = 0.06
local STAB_DIE_MAX       = 0.14
local STAB_FIRE_CHANCE   = 0.35    -- base probability per nozzle per tick
local STAB_DRIFT_THRESH  = 30      -- min XY speed before drift steering kicks in
local STAB_DRIFT_BOOST   = 0.70    -- extra chance boost on the opposing nozzle

function ENT:Initialize()
    self.NikitaEmitter  = ParticleEmitter(self:GetPos(), false)
    self.StabEmitter    = ParticleEmitter(self:GetPos(), false)
end

function ENT:Draw()
    self:DrawModel()
end

function ENT:Think()
    if not IsValid(self.NikitaEmitter) then return end

    local pos        = self:GetPos()
    local fwd        = self:GetForward()
    local backDir    = -fwd
    local exhaustPos = pos + backDir * 55
    local boost      = self:GetNWFloat("NikitaBoost", 0)

    self.NikitaEmitter:SetPos(pos)

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
    --  Smoke wisp (1-in-3 chance per tick)
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
    --
    --  4 nozzles at cardinal offsets in missile local space:
    --    right (+right), left (-right), up (+up), down (-up)
    --
    --  Each nozzle fires radially outward (away from missile axis).
    --  The nozzle(s) OPPOSING the current XY velocity drift get a
    --  probability boost, mimicking spacecraft attitude correction.
    --  Pure white flamelet, 0.2x the main flame size. No light.
    -- --------------------------------------------------------
    if not IsValid(self.StabEmitter) then return end
    self.StabEmitter:SetPos(pos)

    local right = self:GetRight()
    local up    = self:GetUp()

    -- Nozzle base position: slightly behind the missile midpoint
    local nozzleBase = pos + backDir * STAB_NOZZLE_BACK

    -- 4 cardinal directions in local space: outward direction + offset
    -- { outward world-dir, nozzle world-pos }
    local nozzles = {
        {  right,  nozzleBase + right * STAB_NOZZLE_DIST },   -- [1] right
        { -right,  nozzleBase - right * STAB_NOZZLE_DIST },   -- [2] left
        {  up,     nozzleBase + up    * STAB_NOZZLE_DIST },   -- [3] up
        { -up,     nozzleBase - up    * STAB_NOZZLE_DIST },   -- [4] down
    }

    -- Measure XY drift direction from velocity (server NW or predicted)
    -- We use GetAbsVelocity on the client prediction copy.
    local vel    = self:GetVelocity()
    local driftX = vel.x
    local driftY = vel.y
    local driftLen = math.sqrt(driftX * driftX + driftY * driftY)

    -- Flat drift vector in world XY, projected onto each nozzle's outward dir
    -- A nozzle "opposes" drift when its outward direction dot driftVec < -threshold
    local driftVec = Vector(0, 0, 0)
    if driftLen > STAB_DRIFT_THRESH then
        driftVec = Vector(driftX / driftLen, driftY / driftLen, 0)
    end

    for idx, nozzle in ipairs(nozzles) do
        local outDir  = nozzle[1]
        local nozzPos = nozzle[2]

        -- Dot of outward nozzle direction against flat drift
        -- Negative dot = nozzle is on the side opposing the drift
        local drift2D = Vector(outDir.x, outDir.y, 0)
        local dot     = drift2D:Dot(driftVec)

        -- Fire chance: base + boost if opposing drift
        local chance = STAB_FIRE_CHANCE
        if dot < -0.35 then
            chance = chance + STAB_DRIFT_BOOST
        end

        if math.random() < chance then
            local part = self.StabEmitter:Add(
                "particles/flamelet" .. math.random(1, 5),
                nozzPos + VectorRand() * 2
            )
            if part then
                -- Jet fires radially outward from missile body
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
                -- Pure white
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
end
