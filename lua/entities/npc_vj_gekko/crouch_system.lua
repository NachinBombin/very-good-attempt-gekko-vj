-- ============================================================
--  crouch_system.lua
--  Gekko VJ NPC — Crouch mechanic
-- ============================================================

-- ─────────────────────────────────────────────────────────────
--  Tuning constants
-- ─────────────────────────────────────────────────────────────
local CROUCH_HOLD_MIN   = 10
local STAND_REARM_DELAY = 1.0
local HULL_LOOKAHEAD    = 196
local OBS_ON_DEBOUNCE   = 0.25
local HITBOX_STAND_H    = 200
local HITBOX_CROUCH_H   = 130
local HITBOX_HALF_W     = 64
local OBS_MIN_VELOCITY  = 20

local CEIL_CHECK_INTERVAL = 0.12
local CEIL_CLEARANCE      = 60
local CEIL_TRACE_EXTRA    = 80

local RAND_CHECK_MIN  = 6
local RAND_CHECK_MAX  = 8
local RAND_CHANCE     = 0.69
local RAND_DUR_MIN    = 4
local RAND_DUR_MAX    = 14

local DEFAULT_MOVE_SPEED    = 150
local CWALK_STATIONARY_RATE = 0.05
local CWALK_MOVING_THRESH   = 5

-- How far past _gekkoCrouchHoldUntil the dodge lock stays active.
-- This staggers _gekkoDodgeCrouchUntil AFTER _gekkoCrouchHoldUntil so
-- anyLock is still true when the hold-exit check fires, preventing the
-- premature ExitCrouch that caused the post-dodge up-down animation bob.
local DODGE_CROUCH_TAIL = 0.6

-- ─────────────────────────────────────────────────────────────
--  Hull shapes (obstacle check only)
-- ─────────────────────────────────────────────────────────────
local HULL_FWD_MIN = Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 12)
local HULL_FWD_MAX = Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_CROUCH_H)

-- ─────────────────────────────────────────────────────────────
--  RawObstacleCheck
-- ─────────────────────────────────────────────────────────────
local function RawObstacleCheck(ent)
    local pos = ent:GetPos()
    local fwd = ent:GetForward()
    fwd.z = 0
    fwd:Normalize()
    local tr = util.TraceHull({
        start  = pos,
        endpos = pos + fwd * HULL_LOOKAHEAD,
        mins   = HULL_FWD_MIN,
        maxs   = HULL_FWD_MAX,
        filter = ent,
        mask   = MASK_SOLID,
    })
    return tr.Hit
end

-- ─────────────────────────────────────────────────────────────
--  CeilingCheck  (debounced)
-- ─────────────────────────────────────────────────────────────
local function CeilingCheck(ent)
    local now = CurTime()
    if now < (ent._gekkoCeilNextT or 0) then
        return ent._gekkoCeilingHit or false
    end
    ent._gekkoCeilNextT = now + CEIL_CHECK_INTERVAL

    local pos   = ent:GetPos()
    local mins  = Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, HITBOX_CROUCH_H)
    local maxs  = Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_STAND_H + CEIL_TRACE_EXTRA)
    local tr    = util.TraceHull({
        start  = pos,
        endpos = pos + Vector(0, 0, CEIL_CLEARANCE),
        mins   = mins,
        maxs   = maxs,
        filter = ent,
        mask   = MASK_SOLID,
    })
    ent._gekkoCeilingHit = tr.Hit
    return tr.Hit
end

-- ─────────────────────────────────────────────────────────────
--  EnterCrouch / ExitCrouch  (internal)
-- ─────────────────────────────────────────────────────────────
local function EnterCrouch(ent, holdDuration, randDuration)
    local now = CurTime()

    -- Guard against re-entry when already crouching.
    -- A second EnterCrouch call resets _gekkoCrouchSeqSet = -1 and
    -- _gekkoCrouchJustEntered = true, forcing EnforceSequence to call
    -- ResetSequence again on the same tick — the visible post-dodge bob.
    -- If already crouching, only extend the hold timer.
    if ent._gekkoCrouching then
        local holdLen = holdDuration or CROUCH_HOLD_MIN
        if randDuration and randDuration > holdLen then holdLen = randDuration end
        local newUntil = now + holdLen
        if newUntil > (ent._gekkoCrouchHoldUntil or 0) then
            ent._gekkoCrouchHoldUntil = newUntil
        end
        return
    end

    ent._gekkoCrouching         = true
    ent._gekkoCrouchJustEntered = true

    local holdLen = holdDuration or CROUCH_HOLD_MIN
    if randDuration and randDuration > holdLen then
        holdLen = randDuration
    end
    ent._gekkoCrouchHoldUntil = now + holdLen
    ent._gekkoCrouchSeqSet    = -1
    ent._gekkoObsOnSince      = nil
    ent._gekkoObsDebounced    = false
    ent._gekkoObsHullHit      = false

    ent:SetCollisionBounds(
        Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0),
        Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_CROUCH_H)
    )
    ent:SetNWBool("GekkoIsCrouching", true)
    print(string.format("[GeckoCrouch] Enter | holdUntil=%.2f", ent._gekkoCrouchHoldUntil))
end


local function ExitCrouch(ent)
    local now = CurTime()
    -- Never exit while sliding
    if ent._pedestalSliding then return end

    ent._gekkoCrouching         = false
    ent._gekkoCrouchJustEntered = false
    ent._gekkoCrouchSeqSet      = -1
    -- Invalidate last-sequence cache so walk/idle re-stamps immediately.
    ent.Gekko_LastSeqIdx        = -1
    ent._gekkoDodgeCrouch       = false
    ent._gekkoDodgeCrouchUntil  = 0
    ent._gekkoDodgeCrouchForced = false
    ent._gekkoObsRearmT         = now + STAND_REARM_DELAY
    ent._gekkoObsOnSince        = nil
    ent._gekkoObsDebounced      = false
    ent._gekkoObsHullHit        = false
    ent._gekkoCeilingHit        = false
    ent._gekkoCeilNextT         = 0

    ent:SetCollisionBounds(
        Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0),
        Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_STAND_H)
    )
    ent:SetNWBool("GekkoIsCrouching", false)
    print("[GeckoCrouch] Exit | standing")
end

-- ─────────────────────────────────────────────────────────────
--  EnforceSequence  (called every tick while crouched)
-- ─────────────────────────────────────────────────────────────
local function EnforceSequence(ent)
    local speed    = ent:GetVelocity():Length2D()
    local isMoving = speed > CWALK_MOVING_THRESH

    -- FIX: was "c_walk" for both branches — c_idle was never used.
    local seqName  = isMoving and "c_walk" or "c_idle"
    local seqIdx   = ent:LookupSequence(seqName)

    -- Fall back to c_walk if c_idle doesn't exist on this model.
    if seqIdx < 0 then
        seqIdx = ent:LookupSequence("c_walk")
    end

    if seqIdx < 0 then return end

    if ent._gekkoCrouchSeqSet ~= seqIdx then
        ent:ResetSequence(seqIdx)
        ent._gekkoCrouchSeqSet      = seqIdx
        -- Clear just-entered flag so EnforceSequence does not re-stamp every tick.
        ent._gekkoCrouchJustEntered = false
    end

    local rate
    if isMoving then
        rate = math.Clamp(speed / DEFAULT_MOVE_SPEED, 0.4, 2.0)
    else
        rate = CWALK_STATIONARY_RATE
    end
    ent:SetPlaybackRate(rate)
end

-- ─────────────────────────────────────────────────────────────
--  ENT:Dodge_EnterCrouch  (called by pedestal_dodge_system BeginSlide)
--
--  FIX (bob): _gekkoDodgeCrouchUntil is now set to
--      now + slideDuration + DODGE_CROUCH_TAIL
--  instead of just now + slideDuration.
--
--  Previously both _gekkoDodgeCrouchUntil and _gekkoCrouchHoldUntil
--  were set to the same value (now + 2.5). On the tick they both
--  expired simultaneously:
--    - now >= _gekkoCrouchHoldUntil  → true  (exit check fires)
--    - dodgeActive = _gekkoDodgeCrouch and now < _gekkoDodgeCrouchUntil
--                  = true            and false  → FALSE
--    - anyLock = dodgeActive or slideActive or ceilHit = FALSE
--  So ExitCrouch fired, then the NPC immediately re-entered crouch
--  on the next want-crouch evaluation because VJ Base's movement AI
--  had been running since slideDur (0.36s) and was fighting
--  EnforceSequence's ResetSequence calls, causing the up-down bob.
--
--  With DODGE_CROUCH_TAIL = 0.6s stagger:
--    _gekkoCrouchHoldUntil  = now + 2.5   (hold expires first)
--    _gekkoDodgeCrouchUntil = now + 3.1   (tail keeps dodgeActive true)
--  When the hold-exit check fires at T+2.5:
--    dodgeActive = true (now < 3.1) → anyLock = true → ExitCrouch blocked.
--  GeckoCrouch_Update instead extends _gekkoCrouchHoldUntil by
--  CROUCH_HOLD_MIN so the posture holds cleanly. At T+3.1 dodgeActive
--  becomes false, anyLock becomes false, and ExitCrouch fires once,
--  smoothly, with no competition from VJ Base.
-- ─────────────────────────────────────────────────────────────
function ENT:Dodge_EnterCrouch(slideDuration)
    local now = CurTime()
    self._gekkoDodgeCrouch      = true
    -- Stagger the dodge-active expiry past the hold expiry by DODGE_CROUCH_TAIL
    -- so anyLock stays true during the stand-up blend window.
    self._gekkoDodgeCrouchUntil  = now + slideDuration + DODGE_CROUCH_TAIL
    self._gekkoDodgeCrouchForced = false   -- never set true: avoids double EnterCrouch
    -- Force GekkoUpdateAnimation to re-stamp the sequence on exit.
    self.Gekko_LastSeqIdx        = -1
    EnterCrouch(self, slideDuration, nil)
    print(string.format(
        "[GeckoCrouch] Dodge_EnterCrouch | holdUntil=%.2f dodgeUntil=%.2f (tail=%.1fs)",
        self._gekkoCrouchHoldUntil,
        self._gekkoDodgeCrouchUntil,
        DODGE_CROUCH_TAIL
    ))
end

-- ─────────────────────────────────────────────────────────────
--  ENT:GeckoCrouch_Init
-- ─────────────────────────────────────────────────────────────
function ENT:GeckoCrouch_Init()
    self._gekkoCrouching         = false
    self._gekkoCrouchJustEntered = false
    self._gekkoCrouchHoldUntil   = 0
    self._gekkoCrouchSeqSet      = -1
    self._gekkoObsOnSince        = nil
    self._gekkoObsDebounced      = false
    self._gekkoObsHullHit        = false
    self._gekkoObsRearmT         = 0
    self._gekkoCeilingHit        = false
    self._gekkoCeilNextT         = 0
    self._gekkoRandomCrouch      = false
    self._gekkoRandomCrouchEndT  = 0
    self._gekkoRandomDuration    = 0
    self._gekkoRandomCrouchNextT = CurTime() + math.Rand(RAND_CHECK_MIN, RAND_CHECK_MAX)
    self._gekkoDodgeCrouch       = false
    self._gekkoDodgeCrouchUntil  = 0
    self._gekkoDodgeCrouchForced = false
end

-- ─────────────────────────────────────────────────────────────
--  ENT:GeckoCrouch_CacheSeqs
-- ─────────────────────────────────────────────────────────────
function ENT:GeckoCrouch_CacheSeqs()
    local cw = self:LookupSequence("c_walk")
    local ci = self:LookupSequence("c_idle")
    self.GekkoSeq_CrouchWalk = (cw and cw ~= -1) and cw or -1
    self.GekkoSeq_CrouchIdle = (ci and ci ~= -1) and ci or -1
end


-- ─────────────────────────────────────────────────────────────
--  ENT:GeckoCrouch_Update  (called every OnThink via GekkoUpdateAnimation)
-- ─────────────────────────────────────────────────────────────
function ENT:GeckoCrouch_Update()
    local now = CurTime()

    -- Kill Flinching at the top of every call while any dodge or slide
    -- lock is active. Last-resort guard so EnforceSequence is never
    -- blocked by a stale flinch flag.
    do
        local _dA = self._gekkoDodgeCrouch and now < (self._gekkoDodgeCrouchUntil or 0)
        local _sA = self._pedestalSliding
        if _dA or _sA then self.Flinching = false end
    end

    -- ── DODGE / SLIDE LOCK ──────────────────────────────────────
    -- dodgeActive stays true until _gekkoDodgeCrouchUntil (now + 2.5 + 0.6 = 3.1s).
    -- slideActive is true only during the 0.36s travel window.
    local dodgeActive = self._gekkoDodgeCrouch and now < (self._gekkoDodgeCrouchUntil or 0)
    local slideActive = self._pedestalSliding

    -- Force-tick: kept for safety but should never fire with the current
    -- dodge path since _gekkoDodgeCrouchForced is never set true.
    if self._gekkoDodgeCrouchForced then
        self._gekkoDodgeCrouchForced = false
        if not self._gekkoCrouching then
            EnterCrouch(self, nil, nil)
        end
        EnforceSequence(self)
        return true
    end

    -- ── VJ BASE CROUCH FLAG ─────────────────────────────────────
    local vjCrouch = self.VJ_IsCrouching or false

    -- ── OBSTACLE CHECK ──────────────────────────────────────────
    local vel     = self:GetVelocity():Length2D()
    local moving  = vel > OBS_MIN_VELOCITY
    local rearmOk = now >= (self._gekkoObsRearmT or 0)
    local obsHit  = false

    if moving and rearmOk then
        local raw = RawObstacleCheck(self)
        if raw then
            if not self._gekkoObsDebounced then
                if not self._gekkoObsOnSince then
                    self._gekkoObsOnSince = now
                end
                if now - self._gekkoObsOnSince >= OBS_ON_DEBOUNCE then
                    self._gekkoObsDebounced = true
                    self._gekkoObsHullHit   = true
                end
            end
        else
            self._gekkoObsOnSince   = nil
            self._gekkoObsDebounced = false
            self._gekkoObsHullHit   = false
        end
        obsHit = self._gekkoObsHullHit
    else
        self._gekkoObsOnSince   = nil
        self._gekkoObsDebounced = false
        self._gekkoObsHullHit   = false
    end

    -- ── CEILING CHECK ───────────────────────────────────────────
    local ceilHit = self._gekkoCrouching and CeilingCheck(self)

    -- ── RANDOM CROUCH TICK ──────────────────────────────────────
    if not self._gekkoCrouching then
        if now >= (self._gekkoRandomCrouchNextT or 0) then
            if math.random() < RAND_CHANCE then
                local dur = math.Rand(RAND_DUR_MIN, RAND_DUR_MAX)
                self._gekkoRandomCrouch     = true
                self._gekkoRandomCrouchEndT = now + dur
                self._gekkoRandomDuration   = dur
                print(string.format("[GeckoCrouch] Random ENTER | dur=%.1f", dur))
            else
                self._gekkoRandomCrouchNextT = now + math.Rand(RAND_CHECK_MIN, RAND_CHECK_MAX)
            end
        end
    else
        if self._gekkoRandomCrouch and now >= self._gekkoRandomCrouchEndT then
            -- random expired — handled in exit-guard below
        end
    end

    -- ── WANT-CROUCH AGGREGATION ─────────────────────────────────
    local wantCrouch = vjCrouch or obsHit or ceilHit
        or self._gekkoRandomCrouch
        or dodgeActive
        or slideActive

    -- ── ANY-LOCK (prevents exit even when hold timer expires) ───
    -- dodgeActive remains true until T+3.1 (hold=2.5 + tail=0.6).
    -- This is the critical change: the hold check at T+2.5 sees anyLock=true
    -- and extends rather than exits, so ExitCrouch fires exactly once at T+3.1.
    local anyLock = dodgeActive or slideActive or ceilHit

    -- ── ENTER PATH ──────────────────────────────────────────────
    if not self._gekkoCrouching then
        if wantCrouch then
            local holdDur = nil
            if self._gekkoRandomCrouch then holdDur = self._gekkoRandomDuration end
            EnterCrouch(self, holdDur, nil)
        else
            return false
        end
    else
        if ceilHit then
            if not anyLock then
                self._gekkoCrouchHoldUntil = now + CROUCH_HOLD_MIN
            end
        end

        if now >= self._gekkoCrouchHoldUntil and not anyLock then
            -- Hold expired and no lock active — process random-crouch expiry
            -- and decide whether to exit.
            if self._gekkoRandomCrouch then
                self._gekkoRandomCrouch      = false
                self._gekkoRandomCrouchEndT  = 0
                self._gekkoRandomDuration    = 0
                self._gekkoRandomCrouchNextT = now + math.Rand(RAND_CHECK_MIN, RAND_CHECK_MAX)
                print(string.format("[GeckoCrouch] Random EXPIRED — next roll in %.1fs",
                    self._gekkoRandomCrouchNextT - now))
                wantCrouch = vjCrouch or obsHit or ceilHit
            end

            if not wantCrouch then
                ExitCrouch(self)
                return false
            end
            self._gekkoCrouchHoldUntil = now + CROUCH_HOLD_MIN

        elseif now >= self._gekkoCrouchHoldUntil and anyLock then
            -- FIX: Hold expired but a lock (dodge tail) is still active.
            -- Extend the hold by CROUCH_HOLD_MIN so the NPC stays crouched
            -- cleanly until the lock releases, then ExitCrouch fires once.
            self._gekkoCrouchHoldUntil = now + CROUCH_HOLD_MIN
        end
    end

    EnforceSequence(self)
    return true
end
