-- ============================================================
-- pedestal_dodge_system.lua
-- TWO MODES
--   1. Random strafe  -- NO crouch, no Z hop.
--   2. Reactive dodge -- FULL crouch, flat lateral slide + INVULN WINDOW.
--
-- FIX SUMMARY (vs previous version):
--   * MOVETYPE_FLY instead of MOVETYPE_FLYGRAVITY: removes the gravity-
--     induced vertical bounce/hop that was causing the up-down motion.
--   * _gekkoInvulnUntil is now written by BeginSlide. init.lua's
--     TraceAttack and OnTakeDamage guards check this to suppress all
--     damage, blood decals, and impact effects during the dodge window.
--   * Crouch hold duration uses a longer fixed window (2.5 s) so the
--     NPC stays crouched for the whole slide + stand-up blend.
--     Previously slideDur = 100/280 = 0.36 s which expired almost
--     immediately, losing the crouch lock before the slide finished.
--   * Flinch suppression moved into GeckoCrouch_Update itself (runs
--     every engine tick, ~100 Hz) instead of a 0.03 s recursive timer
--     (~33 Hz). The old timer left a race window where VJ Base could
--     set Flinching=true between ticks and win the sequence reassertion.
--   * FIX: Removed local Dodge_EnterCrouch / Dodge_ExitCrouch entirely.
--     The local Dodge_EnterCrouch set _gekkoDodgeCrouchForced = true,
--     then BeginSlide called ent:GeckoCrouch_Update() immediately after,
--     which hit the _gekkoDodgeCrouchForced branch and called EnterCrouch
--     a second time with nil holdDuration. That second call reset
--     _gekkoCrouchSeqSet = -1 and _gekkoCrouchJustEntered = true again,
--     causing EnforceSequence to call ResetSequence twice in the same
--     callstack — producing the post-dodge up-down bob.
--     BeginSlide now calls ent:Dodge_EnterCrouch(crouchHold) directly,
--     which is the single authoritative path in crouch_system.lua and
--     never sets _gekkoDodgeCrouchForced.
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

-- Crouch hold window: covers slide travel + stand-up blend.
-- Must be longer than slideDur (0.36 s). 2.5 s gives a full
-- crouched-slide look with smooth stand-up at the end.
local DODGE_CROUCH_HOLD   = 2.5

-- Tail: extra time AFTER the slide timer fires before releasing
-- _gekkoDodgeCrouch so the stand-up blend plays uninterrupted.
local DODGE_CROUCH_TAIL   = 0.6

-- Invuln pad: extra time after (slide + tail) to cover any
-- lingering blast-splash ticks.
local INVULN_PAD          = 0.3

local STAND_REARM_DELAY   = 1.0
local HITBOX_HALF_W       = 64
local HITBOX_CROUCH_H     = 130
local HITBOX_STAND_H      = 200
local RAND_CHECK_MIN      = 6
local RAND_CHECK_MAX      = 8

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
-- Crouch enter / exit
-- Delegated entirely to ENT:Dodge_EnterCrouch (crouch_system.lua).
-- The old local Dodge_EnterCrouch / Dodge_ExitCrouch are REMOVED.
-- Root cause of the post-dodge up-down bob:
--   The local Dodge_EnterCrouch set _gekkoDodgeCrouchForced = true.
--   BeginSlide then called ent:GeckoCrouch_Update() immediately after,
--   which hit the _gekkoDodgeCrouchForced branch and called
--   EnterCrouch() a second time (with nil holdDuration). That second
--   call reset _gekkoCrouchSeqSet = -1 and _gekkoCrouchJustEntered = true
--   again, forcing EnforceSequence to call ResetSequence twice in the
--   same callstack — which restarted the animation from frame 0 twice,
--   producing the visible bob. ENT:Dodge_EnterCrouch in crouch_system.lua
--   is the single authoritative entry point: it never sets
--   _gekkoDodgeCrouchForced, so EnterCrouch fires exactly once.
-- ============================================================

-- ============================================================
-- BeginSlide
-- ============================================================

local function BeginSlide(ent, slideDir, withCrouch)
    if ent._pedestalSliding then return end
    ent._pedestalSliding = true

    local slideDur   = SLIDE_DIST / SLIDE_SPEED   -- ~0.357 s travel time
    local crouchHold = DODGE_CROUCH_HOLD           -- 2.5 s total crouch lock
    local invulnEnd  = CurTime() + crouchHold + INVULN_PAD

    -- ── SET INVULNERABILITY WINDOW ──────────────────────────────
    -- Written here, at the top, BEFORE any other state changes.
    -- init.lua's TraceAttack and OnTakeDamage both check:
    --     CurTime() < (self._gekkoInvulnUntil or 0)
    -- This suppresses all damage, blood decals, BloodImpact effects,
    -- and blast-splash ticks for the entire dodge + crouch window.
    -- ─────────────────────────────────────────────────────────
    ent._gekkoInvulnUntil = invulnEnd

    if withCrouch then
        -- Route through ENT:Dodge_EnterCrouch (crouch_system.lua).
        -- Single authoritative EnterCrouch call — _gekkoDodgeCrouchForced
        -- is never set true, so GeckoCrouch_Update below does NOT call
        -- EnterCrouch a second time. Bob is gone.
        ent:Dodge_EnterCrouch(crouchHold)

        -- Force-stamp the crouch sequence before SetMoveType fires.
        ent:GeckoCrouch_Update()
        ent.Flinching = false
    end

    -- FIX: Kill Flinching BEFORE SetSchedule. VJ Base processes SCHED_NONE on
    -- the same engine tick and may reassign a task that calls ResetSequence,
    -- overwriting the crouch sequence just stamped above. Suppressing Flinching
    -- here ensures GekkoUpdateAnimation is not gated out on the next think tick,
    -- so GeckoCrouch_Update can re-enforce the sequence immediately.
    ent.Flinching = false

    -- Lock VJ AI movement
    ent.VJ_IsMoving     = false
    ent.VJ_CanMoveThink = false
    ent:SetSchedule(SCHED_NONE)

    -- FIX: Kill Flinching again after SetSchedule in case VJ Base set it
    -- during schedule-task processing on this same tick.
    ent.Flinching = false
    if not withCrouch then
        ent._gekkoSuppressActivity = CurTime() + slideDur + 0.1
    end

    -- MOVETYPE_FLY (no gravity): flat lateral slide with zero vertical force.
    -- MOVETYPE_FLYGRAVITY (old) applied gravity every tick → visible up-down bounce.
    ent:SetMoveType(MOVETYPE_FLY)

    local vel = slideDir * SLIDE_SPEED
    vel.z     = 0
    ent:SetVelocity(vel)

    -- Spark on start
    local ed = EffectData()
    ed:SetOrigin(ent:GetPos() + Vector(0, 0, 30))
    ed:SetNormal(Vector(0, 0, 1))
    ed:SetScale(1)
    ed:SetMagnitude(1.5)
    util.Effect("ElectricSpark", ed)

    -- Stop the slide after travel time, restore MOVETYPE_STEP.
    -- _gekkoDodgeCrouch and _gekkoInvulnUntil are NOT cleared here;
    -- they expire naturally so the tail window is fully covered.
    timer.Simple(slideDur, function()
        if not IsValid(ent) then return end

        ent:SetVelocity(Vector(0, 0, 0))
        ent:SetMoveType(MOVETYPE_STEP)
        ent._pedestalSliding = false
        ent.VJ_CanMoveThink  = true

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
    self._pedestalSliding         = false
    self._strafeNextT             = CurTime() + math.Rand(STRAFE_INTERVAL_MIN, STRAFE_INTERVAL_MAX)
    self._dodgeChargesLeft        = DODGE_CHARGES
    self._dodgeWindowStart        = CurTime()
    self._dodgeVulnerable         = false
    self._dodgeVulnUntil          = 0
    self._dodgeCooldownUntil      = 0
    self._gekkoDodgeCrouch        = false
    self._gekkoDodgeCrouchUntil   = 0
    self._gekkoDodgeCrouchForced  = false
    self._gekkoInvulnUntil        = 0
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

    -- Already sliding or in crouch lock → ignore
    if self._pedestalSliding then return false end
    if self._gekkoDodgeCrouch and now < (self._gekkoDodgeCrouchUntil or 0) then
        return false
    end

    -- Cooldown between reactive dodges
    if now < (self._dodgeCooldownUntil or 0) then return false end

    -- Charge system
    if now - self._dodgeWindowStart > DODGE_WINDOW then
        self._dodgeChargesLeft = DODGE_CHARGES
        self._dodgeWindowStart = now
    end
    if self._dodgeChargesLeft <= 0 then
        self._dodgeVulnerable = true
        self._dodgeVulnUntil  = now + DODGE_VULN_DUR
        return false
    end

    -- Probabilistic gate
    if math.random() > DODGE_CHANCE then return false end

    -- Pick direction away from attacker
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

    -- Consume charge, arm cooldown
    self._dodgeChargesLeft = self._dodgeChargesLeft - 1
    self._dodgeCooldownUntil = now + math.Rand(DODGE_COOLDOWN_MIN, DODGE_COOLDOWN_MAX)

    -- Mark vulnerable if out of charges
    if self._dodgeChargesLeft <= 0 then
        self._dodgeVulnerable = true
        self._dodgeVulnUntil  = now + DODGE_VULN_DUR
        self:EmitSound("npc/turret_floor/die.wav", 75, 120)
    end

    BeginSlide(self, dir, true)
    return true
end
