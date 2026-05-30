-- ============================================================
-- pedestal_dodge_system.lua
-- TWO MODES
--   1. Random strafe  -- NO crouch, no Z hop.
--   2. Reactive dodge -- crouch + invuln window.
--
-- Crouch is handled entirely by the existing crouch_system.lua
-- path. BeginSlide calls ENT:GeckoCrouch_BeginDodge(holdDuration)
-- which is just EnterCrouch with a dodge-lock flag. No new
-- timers, no new sequence logic — the same code the
-- obstacle/ceiling system already uses.
-- ============================================================

local SLIDE_DIST          = 100
local SLIDE_SPEED         = 280      -- units/sec

local STRAFE_INTERVAL_MIN = 1.5
local STRAFE_INTERVAL_MAX = 4.5

local DODGE_CHARGES       = 3
local DODGE_WINDOW        = 6.0
local DODGE_CHANCE        = 0.72
local DODGE_COOLDOWN_MIN  = 0.8
local DODGE_COOLDOWN_MAX  = 2.0
local DODGE_VULN_DUR      = 4.0

-- How long the NPC stays crouched during a dodge.
-- slideDur = SLIDE_DIST/SLIDE_SPEED ≈ 0.36 s, so 2.5 s covers
-- the full slide + stand-up blend with room to spare.
local DODGE_CROUCH_HOLD   = 2.5

-- _gekkoInvulnUntil covers the whole crouch window plus a small pad.
local INVULN_PAD          = 0.3

-- ============================================================
-- Internal helpers
-- ============================================================

local function CanFitAt(ent, worldPos)
    local mins = ent:OBBMins()
    local maxs = ent:OBBMaxs()
    local fit = util.TraceHull({
        start  = worldPos + Vector(0, 0, 1),
        endpos = worldPos + Vector(0, 0, 1),
        mins   = mins,
        maxs   = maxs,
        filter = ent,
        mask   = MASK_NPCSOLID,
    })
    return not fit.StartSolid and not fit.AllSolid and not fit.Hit
end

local function PathIsClear(ent, destPos)
    local center = ent:OBBCenter()
    local mins   = ent:OBBMins()
    local maxs   = ent:OBBMaxs()
    local tr = util.TraceHull({
        start  = ent:GetPos() + center,
        endpos = destPos      + center,
        mins   = Vector(mins.x, mins.y, mins.z - center.z),
        maxs   = Vector(maxs.x, maxs.y, maxs.z - center.z),
        filter = ent,
        mask   = MASK_NPCSOLID,
    })
    return not tr.Hit or tr.Fraction > 0.85
end

local function PickSlideDir(ent, preferRight)
    local right  = ent:GetRight()
    local origin = ent:GetPos()
    local dirs   = preferRight and { 1, -1 } or { -1, 1 }
    for _, sign in ipairs(dirs) do
        local candidate = origin + right * (sign * SLIDE_DIST)
        if CanFitAt(ent, candidate) and PathIsClear(ent, candidate) then
            return right * sign
        end
        for _, frac in ipairs({ 0.75, 0.5 }) do
            local shorter = origin + right * (sign * SLIDE_DIST * frac)
            if CanFitAt(ent, shorter) and PathIsClear(ent, shorter) then
                return right * sign
            end
        end
    end
    return nil
end

-- ============================================================
-- BeginSlide
-- ============================================================

local function BeginSlide(ent, slideDir, withCrouch)
    if ent._pedestalSliding then return end
    ent._pedestalSliding = true

    local slideDur = SLIDE_DIST / SLIDE_SPEED   -- ~0.357 s travel time

    if withCrouch then
        -- Set invuln window BEFORE entering crouch so init.lua's
        -- TraceAttack/OnTakeDamage guards are active immediately.
        ent._gekkoInvulnUntil = CurTime() + DODGE_CROUCH_HOLD + INVULN_PAD

        -- Enter crouch using the shared crouch_system path.
        -- This is exactly how obstacle/ceiling/random crouches work.
        -- GeckoCrouch_BeginDodge sets a dodge-lock flag so
        -- GeckoCrouch_Update keeps the NPC crouched for DODGE_CROUCH_HOLD
        -- seconds, then exits cleanly via the normal ExitCrouch path.
        ent:GeckoCrouch_BeginDodge(DODGE_CROUCH_HOLD)

        ent.Flinching = false
    end

    -- Lock VJ AI movement for the slide duration.
    ent.VJ_IsMoving     = false
    ent.VJ_CanMoveThink = false
    ent:SetSchedule(SCHED_NONE)
    ent.Flinching = false

    if not withCrouch then
        ent._gekkoSuppressActivity = CurTime() + slideDur + 0.1
    end

    -- Flat lateral slide, no gravity bounce.
    ent:SetMoveType(MOVETYPE_FLY)
    local vel = slideDir * SLIDE_SPEED
    vel.z = 0
    ent:SetVelocity(vel)

    -- Spark on slide start.
    local ed = EffectData()
    ed:SetOrigin(ent:GetPos() + Vector(0, 0, 30))
    ed:SetNormal(Vector(0, 0, 1))
    ed:SetScale(1)
    ed:SetMagnitude(1.5)
    util.Effect("ElectricSpark", ed)

    -- Stop sliding after travel time. The crouch hold continues
    -- independently — ExitCrouch in crouch_system.lua restores
    -- VJ_CanMoveThink when the hold expires naturally.
    timer.Simple(slideDur, function()
        if not IsValid(ent) then return end
        ent:SetVelocity(Vector(0, 0, 0))
        ent:SetMoveType(MOVETYPE_STEP)
        ent._pedestalSliding = false
        -- Only restore movement here for non-crouch slides;
        -- crouch slides let ExitCrouch handle the restore.
        if not withCrouch then
            ent.VJ_CanMoveThink = true
        end

        local ed2 = EffectData()
        ed2:SetOrigin(ent:GetPos() + Vector(0, 0, 20))
        ed2:SetNormal(Vector(0, 0, 1))
        ed2:SetScale(0.8)
        ed2:SetMagnitude(1)
        util.Effect("ElectricSpark", ed2)
    end)
end

-- ============================================================
-- INIT
-- ============================================================

function ENT:PedestalDodge_Init()
    self._pedestalSliding    = false
    self._strafeNextT        = CurTime() + math.Rand(STRAFE_INTERVAL_MIN, STRAFE_INTERVAL_MAX)
    self._dodgeChargesLeft   = DODGE_CHARGES
    self._dodgeWindowStart   = CurTime()
    self._dodgeVulnerable    = false
    self._dodgeVulnUntil     = 0
    self._dodgeCooldownUntil = 0
    self._gekkoInvulnUntil   = 0
end

-- ============================================================
-- RANDOM STRAFE TICK  (no crouch, no invuln)
-- ============================================================

function ENT:PedestalDodge_ThinkStrafe()
    if self._dodgeVulnerable and CurTime() >= self._dodgeVulnUntil then
        self._dodgeVulnerable  = false
        self._dodgeChargesLeft = DODGE_CHARGES
        self._dodgeWindowStart = CurTime()
    end

    if self._pedestalSliding then return end
    if self._dodgeVulnerable then return end
    if CurTime() < self._strafeNextT then return end
    if not IsValid(self) then return end

    local enemy = self.VJ_TheEnemy
    if not IsValid(enemy) then
        local ok, result = pcall(function() return self:GetEnemy() end)
        if ok and IsValid(result) then enemy = result end
    end
    if not IsValid(enemy) then return end

    local preferRight = math.random() > 0.5
    local dir = PickSlideDir(self, preferRight)
    if not dir then return end

    BeginSlide(self, dir, false)
    self._strafeNextT = CurTime() + math.Rand(STRAFE_INTERVAL_MIN, STRAFE_INTERVAL_MAX)
end

-- ============================================================
-- REACTIVE DODGE ON HIT  (with crouch + invuln)
-- ============================================================

function ENT:PedestalDodge_OnHit(dmginfo)
    local now = CurTime()

    -- Already sliding or in a dodge-crouch lock → ignore.
    if self._pedestalSliding then return false end
    if self._gekkoDodgeCrouching and now < (self._gekkoDodgeCrouchUntil or 0) then
        return false
    end

    -- Cooldown between reactive dodges.
    if now < (self._dodgeCooldownUntil or 0) then return false end

    -- Charge system.
    if now - self._dodgeWindowStart > DODGE_WINDOW then
        self._dodgeChargesLeft = DODGE_CHARGES
        self._dodgeWindowStart = now
    end
    if self._dodgeChargesLeft <= 0 then
        self._dodgeVulnerable = true
        self._dodgeVulnUntil  = now + DODGE_VULN_DUR
        return false
    end

    -- Probabilistic gate.
    if math.random() > DODGE_CHANCE then return false end

    -- Pick direction away from attacker.
    local attacker = dmginfo:GetAttacker()
    local preferRight = true
    if IsValid(attacker) then
        local toAtk = (attacker:GetPos() - self:GetPos()):GetNormalized()
        preferRight = self:GetRight():Dot(toAtk) < 0
    end

    local dir = PickSlideDir(self, preferRight)
    if not dir then
        dir = PickSlideDir(self, not preferRight)
    end
    if not dir then return false end

    -- Consume charge, arm cooldown.
    self._dodgeChargesLeft = self._dodgeChargesLeft - 1
    self._dodgeCooldownUntil = now + math.Rand(DODGE_COOLDOWN_MIN, DODGE_COOLDOWN_MAX)

    if self._dodgeChargesLeft <= 0 then
        self._dodgeVulnerable = true
        self._dodgeVulnUntil  = now + DODGE_VULN_DUR
        self:EmitSound("npc/turret_floor/die.wav", 75, 120)
    end

    BeginSlide(self, dir, true)
    return true
end
