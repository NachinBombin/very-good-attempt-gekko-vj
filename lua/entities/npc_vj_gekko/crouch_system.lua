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

    -- FIX: Guard against re-entry when already crouching.
    -- A second EnterCrouch call resets _gekkoCrouchSeqSet = -1 and
    -- _gekkoCrouchJustEntered = true, which forces EnforceSequence to
    -- call ResetSequence again on the same tick → the visible post-dodge
    -- up-down bob. If already crouching, only extend the hold timer.
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

    -- holdDuration (explicit) takes priority; fall back to random then minimum.
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
    -- FIX: Invalidate last-sequence cache so walk/idle re-stamps immediately.
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
    local seqName  = isMoving and "c_walk" or "c_walk"   -- same seq; split point for future
    local seqIdx   = ent:LookupSequence(seqName)

    if seqIdx < 0 then return end

    if ent._gekkoCrouchSeqSet ~= seqIdx then
        ent:ResetSequence(seqIdx)
        ent._gekkoCrouchSeqSet      = seqIdx
        -- FIX: Clear just-entered flag so EnforceSequence does not re-stamp every tick.
        ent._gekkoCrouchJustEntered = false
    end

    -- Continuously drive playback rate so VJ Base can't starve it.
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
--  FIX: Do NOT set _gekkoDodgeCrouchForced = true here.
--  The old code set it true, then BeginSlide called GeckoCrouch_Update()
--  immediately after, which hit the _gekkoDodgeCrouchForced branch and
--  called EnterCrouch a second time with nil holdDuration. That second
--  call reset _gekkoCrouchSeqSet = -1 and _gekkoCrouchJustEntered = true
--  again, causing EnforceSequence to fire ResetSequence twice in the
--  same callstack — producing the visible post-dodge up-down bob.
--
--  Now EnterCrouch is called exactly once (here) with the correct
--  holdDur. The immediate GeckoCrouch_Update() in BeginSlide takes
--  the normal update path (dodgeActive = true → EnforceSequence)
--  without any second EnterCrouch.
-- ─────────────────────────────────────────────────────────────
function ENT:Dodge_EnterCrouch(slideDuration)
    local now = CurTime()
    self._gekkoDodgeCrouch       = true
    self._gekkoDodgeCrouchUntil  = now + slideDuration
    self._gekkoDodgeCrouchForced = false   -- never set true: avoids double EnterCrouch
    -- FIX: Force GekkoUpdateAnimation to re-stamp the sequence on exit,
    -- since its guard (targetSeq ~= Gekko_LastSeqIdx) would otherwise
    -- skip the walk/idle ResetSequence after the dodge window ends.
    self.Gekko_LastSeqIdx        = -1
    EnterCrouch(self, slideDuration, nil)
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
--  Looks up and caches the crouch animation sequence indices.
--  Called from Init (deferred timer) and from GekkoUpdateAnimation
--  whenever GekkoSeq_CrouchWalk is nil or -1.
--  GekkoSeq_CrouchWalk  : "c_walk"  (primary crouch anim)
--  GekkoSeq_CrouchIdle  : "c_idle"  (stationary crouch; falls back to c_walk)
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

    -- ── FIX: Self-healing Flinching kill ────────────────────────
    -- Kill Flinching at the very top of every GeckoCrouch_Update call
    -- while any dodge or slide lock is active. This is a last-resort
    -- guard: even if GekkoUpdateAnimation's Flinching check was somehow
    -- skipped (e.g. called directly from BeginSlide), the sequence
    -- enforcement below can never be blocked by a stale flinch flag.
    do
        local _dA = self._gekkoDodgeCrouch and now < (self._gekkoDodgeCrouchUntil or 0)
        local _sA = self._pedestalSliding
        if _dA or _sA then self.Flinching = false end
    end
    -- ─────────────────────────────────────────────────────────────

    -- ── DODGE LOCK: extend hold timer every tick while active ────
    local dodgeActive = self._gekkoDodgeCrouch and now < (self._gekkoDodgeCrouchUntil or 0)
    local slideActive = self._pedestalSliding

    -- ── FORCE-TICK: kept for safety but should never fire for dodge
    -- entry now that Dodge_EnterCrouch no longer sets this flag.
    -- ─────────────────────────────────────────────────────────────
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

        -- ExitCrouch only when hold expired AND no lock is active.
        -- ExitCrouch itself also guards on _pedestalSliding, double safety.
        if now >= self._gekkoCrouchHoldUntil and not anyLock then
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
        end
    end

    EnforceSequence(self)
    return true
end
