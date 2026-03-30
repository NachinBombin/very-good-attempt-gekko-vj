-- ============================================================
--  crouch_system.lua
--  Gekko VJ NPC — Crouch mechanic
--
--  Triggers (any one is enough to crouch):
--    1. VJ Base native crouch flag (VJ_IsBeingCrouched)   — immediate
--    2. Standing-hull lookahead (TraceHull forward)        — debounced
--    3. Random timed behaviour                             — timer-based
--
--  State machine:
--
--    STANDING ──(wantCrouch)──► CROUCHING
--                                  │
--                                  │  hold >= CROUCH_HOLD_MIN
--                                  │  AND all triggers dropped
--                                  ▼
--                               STANDING  (STAND_REARM_DELAY before
--                                          obstacle trace fires again)
--
--  Key design rules
--  ─────────────────
--  • Jump CANNOT interrupt a crouch while the hold timer is active.
--
--  • The obstacle trace fires ONLY while moving (vel > OBS_MIN_VELOCITY).
--    A stationary NPC never needs to duck under an obstacle it is not
--    approaching.  This prevents the flat-field false-positive loop.
--
--  • wantCrouch is evaluated AFTER TickObstacle so the hold timer is the
--    sole exit guard once the NPC has committed to a crouch.
--
--  • We do NOT call FrameAdvance() ourselves.  VJBase's own Think chain
--    owns the animation clock.  We only call ResetSequence() once when
--    the target sequence changes, then let VJBase tick the cycle forward.
--    Calling FrameAdvance() here AND letting VJBase call it too is what
--    produced the double-speed / invisible animation.
--
--  • We do NOT touch VJ_CanMoveThink.  Setting it false here then having
--    VJBase restore it on the same tick caused movement to flicker and
--    prevented the NPC from actually staying still while crouching.
--    Movement is suppressed the correct way: MoveSpeed/RunSpeed/WalkSpeed
--    are zeroed in EnterCrouch and restored in ExitCrouch.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
--  Tuning constants
-- ─────────────────────────────────────────────────────────────

-- Minimum time the NPC stays crouched regardless of trigger state.
local CROUCH_HOLD_MIN   = 2.0

-- After standing, delay before obstacle trace is re-armed.
local STAND_REARM_DELAY = 0.8

-- Forward lookahead distance (units).
local HULL_LOOKAHEAD    = 96

-- Obstacle debounce: trace must report hit for this long before crouching.
local OBS_ON_DEBOUNCE   = 0.25

-- Hitbox heights (units above foot origin).
local HITBOX_STAND_H    = 200
local HITBOX_CROUCH_H   = 130
local HITBOX_HALF_W     = 64

-- Velocity threshold below which the obstacle trace is skipped.
local OBS_MIN_VELOCITY  = 20

-- Random crouch behaviour
local RAND_CHECK_MIN    = 6
local RAND_CHECK_MAX    = 16
local RAND_CHANCE       = 0.25
local RAND_DUR_MIN      = 3
local RAND_DUR_MAX      = 10

-- ─────────────────────────────────────────────────────────────
--  Hull shapes (computed once)
-- ─────────────────────────────────────────────────────────────
-- mins.z = 12 so the hull does not clip the ground plane.
local HULL_FWD_MIN = Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 12)
local HULL_FWD_MAX = Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_CROUCH_H)

-- ─────────────────────────────────────────────────────────────
--  RawObstacleCheck  (standing + moving only)
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
--  TickObstacle
--  Only runs while STANDING and moving fast enough.
-- ─────────────────────────────────────────────────────────────
local function TickObstacle(ent)
    local now = CurTime()

    -- Re-arm guard
    if now < ent._gekkoObsRearmT then
        ent._gekkoObsOnSince  = nil
        ent._gekkoObsHullHit  = false
        return false
    end

    -- Skip if the NPC is essentially stationary.
    local vel = ent:GetVelocity()
    local spd = vel.x * vel.x + vel.y * vel.y
    if spd < OBS_MIN_VELOCITY * OBS_MIN_VELOCITY then
        ent._gekkoObsOnSince  = nil
        ent._gekkoObsHullHit  = false
        return false
    end

    local raw = RawObstacleCheck(ent)
    ent._gekkoObsHullHit = raw

    if raw then
        if not ent._gekkoObsOnSince then
            ent._gekkoObsOnSince = now
            print("[GeckoCrouch] Obstacle HIT — debounce started")
        elseif now - ent._gekkoObsOnSince >= OBS_ON_DEBOUNCE then
            if not ent._gekkoObsDebounced then
                ent._gekkoObsDebounced = true
                print(string.format("[GeckoCrouch] Obstacle CONFIRMED (held %.2fs)",
                    now - ent._gekkoObsOnSince))
            end
        end
    else
        ent._gekkoObsOnSince   = nil
        ent._gekkoObsDebounced = false
    end

    return ent._gekkoObsDebounced or false
end

-- ─────────────────────────────────────────────────────────────
--  TickRandom
-- ─────────────────────────────────────────────────────────────
local function TickRandom(ent)
    local now = CurTime()
    if ent._gekkoRandomCrouch then
        if now >= ent._gekkoRandomCrouchEndT then
            ent._gekkoRandomCrouch      = false
            ent._gekkoRandomCrouchEndT  = 0
            ent._gekkoRandomCrouchNextT = now + math.Rand(RAND_CHECK_MIN, RAND_CHECK_MAX)
            print(string.format("[GeckoCrouch] Random EXPIRED — next roll in %.1fs",
                ent._gekkoRandomCrouchNextT - now))
        end
        return
    end
    if now < ent._gekkoRandomCrouchNextT then return end
    if math.random() < RAND_CHANCE then
        local dur = math.Rand(RAND_DUR_MIN, RAND_DUR_MAX)
        ent._gekkoRandomCrouch     = true
        ent._gekkoRandomCrouchEndT = now + dur
        print(string.format("[GeckoCrouch] Random TRIGGERED — holding for %.1fs", dur))
    else
        ent._gekkoRandomCrouchNextT = now + math.Rand(RAND_CHECK_MIN, RAND_CHECK_MAX)
        print(string.format("[GeckoCrouch] Random FAILED — next in %.1fs",
            ent._gekkoRandomCrouchNextT - now))
    end
end

-- ─────────────────────────────────────────────────────────────
--  GeckoCrouch_Init
-- ─────────────────────────────────────────────────────────────
function ENT:GeckoCrouch_Init()
    self._gekkoCrouching         = false
    self._gekkoCrouchHoldUntil   = 0
    self._gekkoObsRearmT         = 0
    self._gekkoObsOnSince        = nil
    self._gekkoObsDebounced      = false
    self._gekkoObsHullHit        = false
    self._gekkoCeilingHit        = false
    self.GekkoSeq_CrouchIdle     = -1
    self.GekkoSeq_CrouchWalk     = -1
    self._gekkoCrouchSeqSet      = -1
    self._gekkoRandomCrouch      = false
    self._gekkoRandomCrouchEndT  = 0
    self._gekkoRandomCrouchNextT = CurTime() + math.Rand(RAND_CHECK_MIN, RAND_CHECK_MAX)
    print("[GeckoCrouch] Init() — state vars created")
end

-- ─────────────────────────────────────────────────────────────
--  GeckoCrouch_CacheSeqs
-- ─────────────────────────────────────────────────────────────
function ENT:GeckoCrouch_CacheSeqs()
    local cidle = self:LookupSequence("cidle")
    local cwalk = self:LookupSequence("c_walk")
    self.GekkoSeq_CrouchIdle = (cidle and cidle ~= -1) and cidle or -1
    self.GekkoSeq_CrouchWalk = (cwalk and cwalk ~= -1) and cwalk or -1
    print(string.format(
        "[GeckoCrouch] CacheSeqs | cidle=%d  c_walk=%d",
        self.GekkoSeq_CrouchIdle, self.GekkoSeq_CrouchWalk
    ))
end

-- ─────────────────────────────────────────────────────────────
--  EnterCrouch / ExitCrouch
-- ─────────────────────────────────────────────────────────────
local function EnterCrouch(ent)
    local now = CurTime()
    ent._gekkoCrouching       = true
    ent._gekkoCrouchHoldUntil = now + CROUCH_HOLD_MIN
    ent._gekkoCrouchSeqSet    = -1   -- force a ResetSequence on first animation tick
    ent._gekkoObsOnSince      = nil
    ent._gekkoObsDebounced    = false
    ent._gekkoObsHullHit      = false
    ent._gekkoCeilingHit      = false
    ent:SetCollisionBounds(
        Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0),
        Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_CROUCH_H)
    )
    ent:SetNWBool("GekkoIsCrouching", true)
    -- Zero movement so the NPC holds still while crouched.
    -- Do NOT touch VJ_CanMoveThink — VJBase will fight it and win every tick.
    ent.MoveSpeed = 0
    ent.RunSpeed  = 0
    ent.WalkSpeed = 0
    print("[GeckoCrouch] → Crouching h=" .. HITBOX_CROUCH_H)
end

local function ExitCrouch(ent)
    local now = CurTime()
    ent._gekkoCrouching         = false
    ent._gekkoCrouchSeqSet      = -1
    ent._gekkoObsRearmT         = now + STAND_REARM_DELAY
    ent._gekkoObsOnSince        = nil
    ent._gekkoObsDebounced      = false
    ent._gekkoObsHullHit        = false
    ent._gekkoCeilingHit        = false
    ent._gekkoRandomCrouch      = false
    ent._gekkoRandomCrouchEndT  = 0
    ent._gekkoRandomCrouchNextT = now + math.Rand(RAND_CHECK_MIN, RAND_CHECK_MAX)
    ent:SetCollisionBounds(
        Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0),
        Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_STAND_H)
    )
    ent:SetNWBool("GekkoIsCrouching", false)
    ent.MoveSpeed = ent.StartMoveSpeed or 150
    ent.RunSpeed  = ent.StartRunSpeed  or 300
    ent.WalkSpeed = ent.StartWalkSpeed or 150
    print("[GeckoCrouch] → Standing h=" .. HITBOX_STAND_H)
end

-- ─────────────────────────────────────────────────────────────
--  GeckoCrouch_Update
--  Returns true  → crouch active, caller must return early.
--  Returns false → crouch inactive, caller continues normally.
-- ─────────────────────────────────────────────────────────────
function ENT:GeckoCrouch_Update()
    local now = CurTime()

    -- ── Jump interrupt — only allowed when hold has already expired ───
    local jumpState = self:GetGekkoJumpState()
    local jumpActive = jumpState == self.JUMP_RISING  or
                       jumpState == self.JUMP_FALLING or
                       jumpState == self.JUMP_LAND    or
                       (self._gekkoJustJumped and now < self._gekkoJustJumped)

    if jumpActive and self._gekkoCrouching then
        -- Only allow jump to break the crouch if the hold has fully expired.
        if now >= self._gekkoCrouchHoldUntil then
            ExitCrouch(self)
            print("[GeckoCrouch] Jump interrupted crouch (hold expired)")
            return false
        end
        -- Hold still active: fall through and keep crouched.
    elseif jumpActive then
        return false
    end

    if self._gekkoSuppressActivity and now < self._gekkoSuppressActivity then
        return false
    end

    -- ── Tick sub-systems ──────────────────────────────────────────
    TickRandom(self)

    local obsHit = false
    if not self._gekkoCrouching then
        obsHit = TickObstacle(self)
    end

    -- ── Evaluate entry triggers ───────────────────────────────────
    local vjCrouch   = (self.VJ_IsBeingCrouched == true)
    local randActive = self._gekkoRandomCrouch
    local wantCrouch = vjCrouch or obsHit or randActive

    -- ── Periodic diagnostics ──────────────────────────────────────
    if not self._crouchDiagT or now > self._crouchDiagT then
        print(string.format(
            "[GeckoCrouch] Update | crouching=%s  want=%s  vj=%s  obs=%s  rand=%s  holdLeft=%.2f  rearmLeft=%.2f",
            tostring(self._gekkoCrouching), tostring(wantCrouch),
            tostring(vjCrouch), tostring(obsHit), tostring(randActive),
            math.max(0, self._gekkoCrouchHoldUntil - now),
            math.max(0, self._gekkoObsRearmT - now)
        ))
        self._crouchDiagT = now + 2
    end

    -- ── State machine ─────────────────────────────────────────────
    if not self._gekkoCrouching then
        if wantCrouch then
            EnterCrouch(self)
            -- Fall through to animation block on this same tick.
        else
            return false
        end
    else
        -- CROUCHING.

        -- Safety: guard against hold timer never being set.
        if self._gekkoCrouchHoldUntil <= 0 then
            self._gekkoCrouchHoldUntil = now + CROUCH_HOLD_MIN
            print("[GeckoCrouch] Hold re-stamped (was zero)")
        end

        -- Exit only when the hold has fully elapsed AND all triggers dropped.
        if not wantCrouch and now >= self._gekkoCrouchHoldUntil then
            ExitCrouch(self)
            return false
        end
        -- Still crouching: fall through to animation block.
    end

    -- ── Crouch is active: set the correct sequence ────────────────
    --
    --  IMPORTANT: We call ResetSequence() ONLY when the target sequence
    --  changes (guarded by _gekkoCrouchSeqSet).  We do NOT call
    --  FrameAdvance() — VJBase's own Think hook owns the animation clock.
    --  Calling both FrameAdvance here AND letting VJBase tick the cycle
    --  causes the animation to advance twice per game tick, which makes it
    --  run at double speed and appear broken/invisible.
    --
    if self.GekkoSeq_CrouchIdle == -1 then
        -- Sequences not cached yet — still block VJBase from overriding.
        return true
    end

    local vel    = self:GetVelocity()
    local speed2 = vel.x * vel.x + vel.y * vel.y
    local moving = speed2 > (16 * 16)
    local targetSeq = (moving and self.GekkoSeq_CrouchWalk ~= -1)
        and self.GekkoSeq_CrouchWalk or self.GekkoSeq_CrouchIdle

    -- Only call ResetSequence when the sequence actually changes.
    -- Never call it every tick — that resets the cycle to 0 each frame,
    -- which is what caused the rapid up-down flicker in the old code.
    if self._gekkoCrouchSeqSet ~= targetSeq then
        self._gekkoCrouchSeqSet = targetSeq
        self:ResetSequence(targetSeq)
        self:SetCycle(0)
        if moving then
            local speed  = math.sqrt(speed2)
            local maxSpd = (self.StartMoveSpeed and self.StartMoveSpeed > 0)
                and self.StartMoveSpeed or 150
            self:SetPlaybackRate(math.Clamp(speed / maxSpd, 0.3, 1.5))
        else
            self:SetPlaybackRate(1.0)
        end
        self.Gekko_LastSeqIdx  = targetSeq
        self.Gekko_LastSeqName = moving and "c_walk" or "cidle"
        print(string.format("[GeckoCrouch] Seq → %s (%d) moving=%s",
            self.Gekko_LastSeqName, targetSeq, tostring(moving)))
    end

    -- Do NOT call self:FrameAdvance(FrameTime()) here.
    -- VJBase's funcAnimThink hook (registered in ENTITY:Initialize via
    -- hook.Add("Think", self, funcAnimThink)) already calls FrameAdvance
    -- every tick.  Calling it a second time here doubles the playback
    -- speed and prevents the animation from being visible.

    self:SetPoseParameter("move_x", 0)
    self:SetPoseParameter("move_y", 0)
    -- Do NOT set VJ_CanMoveThink = false here.
    -- VJBase restores this flag every tick in its own Think chain.
    -- The race condition between our false-set and VJBase's true-restore
    -- caused movement to flicker and never actually stop.
    -- Movement is already suppressed via MoveSpeed/RunSpeed/WalkSpeed = 0
    -- in EnterCrouch, which VJBase respects.
    return true
end
