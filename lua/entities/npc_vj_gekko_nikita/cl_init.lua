include("shared.lua")

-- ============================================================
--  npc_vj_gekko_nikita  /  cl_init.lua
--
--  Visual phases:
--    0.0 - 1.9s  : WHITE SMOKE TRAIL only (fat missile plume, no flame/light)
--    1.9s+       : Full flame + sparks + dlight + stabilisers
--    1.9 - 2.9s  : Smoke trail continues, then naturally fades out
--                  (overlap = 1s, handled via _smokeFadeEnd timestamp)
--
--  Pre-detonation burst visuals:
--    NikitaMuzzleFlash  → muzzle ring + emitter flash at nose tip
--    NikitaPelletTracer → per-pellet beam drawn in PostDrawTranslucentRenderables
--                         (same pipeline as bushmaster: effects/laser1 beam +
--                          sprites/light_glow02_add tip glow, timed fade-out)
-- ============================================================

-- ----------------------------------------------------------------
--  TIMING
-- ----------------------------------------------------------------
local FLAME_DELAY   = 1.6
local SMOKE_FADE    = 0.4

-- ----------------------------------------------------------------
--  SMOKE TRAIL TUNING
-- ----------------------------------------------------------------
local SMOKE_EMIT_CHANCE  = 0.65
local SMOKE_SIZE_MIN     = 55
local SMOKE_SIZE_MAX     = 110
local SMOKE_END_MIN      = 110
local SMOKE_END_MAX      = 180
local SMOKE_ALPHA_START  = 200
local SMOKE_ALPHA_END    = 0
local SMOKE_SPEED_MIN    = 35
local SMOKE_SPEED_MAX    = 85
local SMOKE_DIE_MIN      = 0.55
local SMOKE_DIE_MAX      = 1.10
local SMOKE_SPREAD       = 14
local SMOKE_BACK_OFFSET  = 55

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

-- ----------------------------------------------------------------
--  PELLET TRACER TUNING
-- ----------------------------------------------------------------
-- How long each tracer beam is visible (seconds).
local TRACER_LIFE        = 0.29
-- Width of the bright core beam.
local TRACER_WIDTH_CORE  = 3
-- Width of the soft outer glow beam.
local TRACER_WIDTH_HALO  = 10
-- Tip glow sprite size.
local TRACER_GLOW_SIZE   = 22
-- Colour: bright yellow-white core, warm halo (shotgun pellet feel).
local TRACER_COLOR_CORE  = Color(255, 240, 200, 255)
local TRACER_COLOR_HALO  = Color(255, 160,  60, 120)
local TRACER_COLOR_GLOW  = Color(255, 200, 100, 200)

-- ----------------------------------------------------------------
--  MUZZLE FLASH TUNING
-- ----------------------------------------------------------------
-- Radius of the forward cone of flame particles.
local MF_PARTICLES       = 14
local MF_SPEED_MIN       = 250
local MF_SPEED_MAX       = 700
local MF_SPREAD          = 55
local MF_SIZE_MIN        = 10
local MF_SIZE_MAX        = 28
local MF_DIE_MIN         = 0.04
local MF_DIE_MAX         = 0.12
-- Dynamic light at muzzle.
local MF_DLIGHT_SIZE     = 220
local MF_DLIGHT_DUR      = 0.37

-- ----------------------------------------------------------------
--  SHARED MATERIALS (reuse bushmaster pipeline)
-- ----------------------------------------------------------------
local mat_beam = Material("effects/laser1")
local mat_glow = Material("sprites/light_glow02_add")

-- ----------------------------------------------------------------
--  TRACER DRAW LIST
--  Each entry: { startPos, endPos, dieTime }
--  Rendered every PostDrawTranslucentRenderables frame.
-- ----------------------------------------------------------------
local g_tracers = {}

hook.Add("PostDrawTranslucentRenderables", "nikita_pellet_tracers", function(depth, skybox)
    if depth or skybox then return end
    local now = CurTime()
    local cam = EyePos()
    local i   = 1
    while i <= #g_tracers do
        local t = g_tracers[i]
        if now >= t.dieTime then
            table.remove(g_tracers, i)
        else
            local frac    = math.Clamp((t.dieTime - now) / TRACER_LIFE, 0, 1)
            local a_core  = math.floor(TRACER_COLOR_CORE.a  * frac)
            local a_halo  = math.floor(TRACER_COLOR_HALO.a  * frac)
            local a_glow  = math.floor(TRACER_COLOR_GLOW.a  * frac)
            local dist    = math.sqrt(cam:DistToSqr(t.startPos))
            local scale   = math.Clamp(dist / 1200, 1.0, 4.0)

            render.SetMaterial(mat_beam)
            render.DrawBeam(
                t.startPos, t.endPos,
                TRACER_WIDTH_CORE * scale, 0, 1,
                Color(TRACER_COLOR_CORE.r, TRACER_COLOR_CORE.g, TRACER_COLOR_CORE.b, a_core)
            )
            render.DrawBeam(
                t.startPos, t.endPos,
                TRACER_WIDTH_HALO * scale, 0, 1,
                Color(TRACER_COLOR_HALO.r, TRACER_COLOR_HALO.g, TRACER_COLOR_HALO.b, a_halo)
            )

            render.SetMaterial(mat_glow)
            render.DrawSprite(
                t.endPos,
                TRACER_GLOW_SIZE * scale, TRACER_GLOW_SIZE * scale,
                Color(TRACER_COLOR_GLOW.r, TRACER_COLOR_GLOW.g, TRACER_COLOR_GLOW.b, a_glow)
            )

            i = i + 1
        end
    end
end)

-- ----------------------------------------------------------------
--  NET: one tracer per pellet
-- ----------------------------------------------------------------
net.Receive("NikitaPelletTracer", function()
    local startPos = net.ReadVector()
    local endPos   = net.ReadVector()
    g_tracers[#g_tracers + 1] = {
        startPos = startPos,
        endPos   = endPos,
        dieTime  = CurTime() + TRACER_LIFE,
    }
end)

-- ----------------------------------------------------------------
--  NET: muzzle flash
-- ----------------------------------------------------------------
net.Receive("NikitaMuzzleFlash", function()
    local muzzlePos = net.ReadVector()
    local aimDir    = net.ReadVector()

    -- Particle emitter burst (forward-facing flame cone).
    local emitter = ParticleEmitter(muzzlePos, false)
    if emitter then
        for _ = 1, MF_PARTICLES do
            local p = emitter:Add("particles/flamelet" .. math.random(1, 5), muzzlePos)
            if p then
                local scatter = VectorRand() * MF_SPREAD
                local vel     = aimDir * math.Rand(MF_SPEED_MIN, MF_SPEED_MAX) + scatter
                p:SetVelocity(vel)
                p:SetLifeTime(0)
                p:SetDieTime(math.Rand(MF_DIE_MIN, MF_DIE_MAX))
                p:SetStartAlpha(math.random(180, 255))
                p:SetEndAlpha(0)
                p:SetStartSize(math.Rand(MF_SIZE_MIN, MF_SIZE_MAX))
                p:SetEndSize(0)
                p:SetColor(255, math.random(140, 220), math.random(0, 60))
                p:SetRoll(math.Rand(0, 360))
                p:SetRollDelta(math.Rand(-3, 3))
                p:SetGravity(Vector(0, 0, 30))
                p:SetCollide(false)
            end
        end
        emitter:Finish()
    end

    -- Standard GMod muzzle flash effect at the nose.
    local ed = EffectData()
    ed:SetOrigin(muzzlePos)
    ed:SetNormal(aimDir)
    ed:SetScale(1.4)
    util.Effect("MuzzleEffect", ed)

    -- Dynamic light flash.
    local dl = DynamicLight(0)
    if dl then
        dl.pos        = muzzlePos
        dl.r          = 255
        dl.g          = 200
        dl.b          = 80
        dl.brightness = 6
        dl.Size       = MF_DLIGHT_SIZE
        dl.Decay      = MF_DLIGHT_SIZE / MF_DLIGHT_DUR
        dl.DieTime    = CurTime() + MF_DLIGHT_DUR
    end
end)

-- ================================================================
--  ENT CALLBACKS
-- ================================================================
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
    --  WHITE SMOKE TRAIL
    -- --------------------------------------------------------
    if smokeOn and IsValid(self.SmokeEmitter) then
        if math.random() < SMOKE_EMIT_CHANCE then
            local spread = VectorRand() * SMOKE_SPREAD
            spread.x = spread.x * 0.4
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

    if not flameOn then return end

    -- --------------------------------------------------------
    --  Dynamic light
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
    --  Fuchsia flame layer
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
    --  Smoke wisp during flame phase
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