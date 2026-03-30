-- ============================================================
--  crouch_system.lua
--  Gekko VJ NPC — Crouch mechanic
--
--  Triggers (any one is enough to crouch):
--    1. VJ Base native crouch flag (VJ_IsBeingCrouched)   — immediate
--    2. Standing-hull lookahead (TraceHull forward)        — debounced
--    3. Random timed behaviour                             — timer-based
--
--  State machine (mirrors jump_system.lua pattern):
--
--    STANDING ──(wantCrouch)──► CROUCHING
--                                  │
--                                  │  hold >= CROUCH_HOLD_MIN
--                                  │  AND all triggers dropped
--                                  │  AND ceiling clear (one-shot)
--                                  ▼
--                               STANDING  (re-arm delay before
--                                          obstacle trace fires again)
--
--  KEY FIX vs old version:
--    The old TickCeiling toggled between RawObstacleCheck (standing)
--    and RawClearanceCheck (crouching) via _gekkoCrouching.  The
--    instant the NPC crouched the selector flipped, the clearance
--    trace found nothing in open air, ceilHit → false, the 0.35 s
--    lockout expired and the NPC stood back up — immediately
--    re-triggering the forward obstacle and looping forever.
--
--    Fix: obstacle lookahead is ONLY evaluated while standing and
--    ONLY after STAND_REARM_DELAY has elapsed since the last
--    stand-up.  Clearance is a one-shot check called inside the
--    exit-evaluation block, not the continuous trigger signal.
--
--  Called from:
--    ENT:Init()                 → self:GeckoCrouch_Init()
--    ENT:GekkoUpdateAnimation() → self:GeckoCrouch_Update()
-- ============================================================

-- ─────────────────────────────────────────────────────────────
--  Tuning constants
-- ─────────────────────────────────────────────────────────────

-- Minimum time the NPC must stay crouched before exit is evaluated.
-- Set to roughly match the cidle blend-in so the animation has
-- time to play before we consider standing back up.
local CROUCH_HOLD_MIN     = 0.8

-- After standing back up, how long before the forward obstacle
-- trace is allowed to fire again.  Prevents immediate re-trigger
-- on the very frame the NPC returns to standing height.
local STAND_REARM_DELAY   = 0.6

-- How far ahead to project the forward hull (units).
local HULL_LOOKAHEAD      = 80

-- Obstacle debounce: trace must report a hit for this long before
-- we commit to crouching.
local OBS_ON_DEBOUNCE     = 0.20

-- Hitbox heights
local HITBOX_STAND_H      = 200
local HITBOX_CROUCH_H     = 130
local HITBOX_HALF_W       = 64

-- Random crouch behaviour
local RAND_CHECK_MIN      = 4
local RAND_CHECK_MAX      = 12
local RAND_CHANCE         = 0.30
local RAND_DUR_MIN        = 3
local RAND_DUR_MAX        = 10

-- ─────────────────────────────────────────────────────────────
--  Hull shapes (computed once)
-- ─────────────────────────────────────────────────────────────
-- Forward lookahead: crouch-height hull so it only catches
-- obstacles that actually require ducking.
local HULL_FWD_MIN = Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0)
local HULL_FWD_MAX = Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_CROUCH_H)

-- Vertical clearance: the Z slice from crouched top → standing top.
-- Used as a one-shot check when evaluating whether it is safe to
-- stand back up.  Requires a non-zero sweep — use 1 unit upward.
local HULL_VERT_MIN  = Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, HITBOX_CROUCH_H)
local HULL_VERT_MAX  = Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_STAND_H)
local VERT_SWEEP_OFF = Vector(0, 0, 1)

-- ─────────────────────────────────────────────────────────────
--  RawObstacleCheck
--  Projects the crouch-height hull straight ahead while STANDING.
--  Returns true → something blocks the path at crouch height → crouch.
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
--  RawClearanceCheck  (one-shot, called only in exit evaluation)
--  Checks the Z slice from crouched top → standing top above NPC.
--  Returns true  → ceiling present → cannot stand yet.
--  Returns false → overhead is clear → safe to stand.
-- ─────────────────────────────────────────────────────────────
local function RawClearanceCheck(ent)
    local pos = ent:GetPos()
    local tr = util.TraceHull({
        start  = pos,
        endpos = pos + VERT_SWEEP_OFF,
        mins   = HULL_VERT_MIN,
        maxs   = HULL_VERT_MAX,
        filter = ent,
        mask   = MASK_SOLID,
    })
    return tr.Hit
end

-- ─────────────────────────────────────────────────────────────
--  TickObstacle
--  Runs ONLY while the NPC is standing AND the re-arm timer has
--  elapsed.  Applies a debounce so a fleeting brush does not
--  immediately trigger a crouch.
--  Returns true once the debounce confirms a sustained hit.
-- ─────────────────────────────────────────────────────────────
local function TickObstacle(ent)
    local now = CurTime()

    -- Not armed yet after last stand-up.
    if now < ent._gekkoObsRearmT then
        ent._gekkoObsOnSince = nil
        return false
    end

    local raw = RawObstacleCheck(ent)
    ent._gekkoCeilingHit = raw   -- expose for debug HUD in init.lua

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
    self._gekkoCrouching          = false
    -- Minimum hold timer: CurTime() at enter-crouch + CROUCH_HOLD_MIN
    self._gekkoCrouchHoldUntil    = 0
    -- Re-arm delay: set to CurTime() + STAND_REARM_DELAY each time
    -- the NPC returns to standing, so the obstacle trace doesn't
    -- fire on the same frame the NPC stands back up.
    self._gekkoObsRearmT          = 0
    self._gekkoObsOnSince         = nil
    self._gekkoObsDebounced       = false
    -- Exposed for the debug HUD in init.lua
    self._gekkoCeilingHit         = false
    self.GekkoSeq_CrouchIdle      = -1
    self.GekkoSeq_CrouchWalk      = -1
    self._gekkoCrouchSeqSet       = -1
    self._gekkoRandomCrouch       = false
    self._gekkoRandomCrouchEndT   = 0
    self._gekkoRandomCrouchNextT  = CurTime() + math.Rand(RAND_CHECK_MIN, RAND_CHECK_MAX)
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
--  Internal helpers
-- ─────────────────────────────────────────────────────────────
local function EnterCrouch(ent)
    ent._gekkoCrouching       = true
    ent._gekkoCrouchHoldUntil = CurTime() + CROUCH_HOLD_MIN
    ent._gekkoCrouchSeqSet    = -1
    -- Obstacle trace is irrelevant while crouching; disarm it so it
    -- does not accumulate a stale debounce during the crouch.
    ent._gekkoObsOnSince      = nil
    ent._gekkoObsDebounced    = false
    ent:SetCollisionBounds(
        Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0),
        Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_CROUCH_H)
    )
    ent.VJ_CanMoveThink = false
    print("[GeckoCrouch] → Crouching h=" .. HITBOX_CROUCH_H)
end

local function ExitCrouch(ent)
    ent._gekkoCrouching    = false
    ent._gekkoCrouchSeqSet = -1
    -- Start the re-arm delay so the obstacle trace doesn't fire
    -- on the exact frame we return to standing height.
    ent._gekkoObsRearmT    = CurTime() + STAND_REARM_DELAY
    ent._gekkoObsOnSince   = nil
    ent._gekkoObsDebounced = false
    ent:SetCollisionBounds(
        Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0),
        Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_STAND_H)
    )
    ent.VJ_CanMoveThink = true
    print("[GeckoCrouch] → Standing h=" .. HITBOX_STAND_H)
end

-- ─────────────────────────────────────────────────────────────
--  GeckoCrouch_Update
--  Returns true  → crouch active, caller must return early
--  Returns false → crouch inactive, caller runs normally
-- ─────────────────────────────────────────────────────────────
function ENT:GeckoCrouch_Update()
    local now = CurTime()

    -- ── Jump takes absolute priority ──────────────────────────────
    local jumpState = self:GetGekkoJumpState()
    if jumpState == self.JUMP_RISING  or
       jumpState == self.JUMP_FALLING or
       jumpState == self.JUMP_LAND    or
       (self._gekkoJustJumped and now < self._gekkoJustJumped) then
        if self._gekkoCrouching then
            -- Jump hard-resets crouch; random timer restarts from scratch.
            self._gekkoRandomCrouch      = false
            self._gekkoRandomCrouchEndT  = 0
            self._gekkoRandomCrouchNextT = now + math.Rand(RAND_CHECK_MIN, RAND_CHECK_MAX)
            ExitCrouch(self)
            print("[GeckoCrouch] Jump interrupted crouch")
        end
        return false
    end

    if self._gekkoSuppressActivity and now < self._gekkoSuppressActivity then
        return false
    end

    -- ── Tick sub-systems ──────────────────────────────────────────
    TickRandom(self)

    -- Obstacle lookahead only fires while standing.
    local obsHit = false
    if not self._gekkoCrouching then
        obsHit = TickObstacle(self)
    end

    -- ── Evaluate triggers ─────────────────────────────────────────
    local vjCrouch   = (self.VJ_IsBeingCrouched == true)
    local randActive = self._gekkoRandomCrouch
    local wantCrouch = vjCrouch or obsHit or randActive

    -- ── Periodic diagnostics ──────────────────────────────────────
    if not self._crouchDiagT or now > self._crouchDiagT then
        print(string.format(
            "[GeckoCrouch] Update | crouching=%s  want=%s  vj=%s  obs=%s  rand=%s  holdLeft=%.2f  rearmLeft=%.2f",
            tostring(self._gekkoCrouching), tostring(wantCrouch),
            tostring(vjCrouch), tostring(obsHit),
            tostring(randActive),
            math.max(0, self._gekkoCrouchHoldUntil - now),
            math.max(0, self._gekkoObsRearmT - now)
        ))
        self._crouchDiagT = now + 2
    end

    -- ── State machine ─────────────────────────────────────────────
    if not self._gekkoCrouching then
        -- STANDING: enter crouch if any trigger fires.
        if wantCrouch then
            EnterCrouch(self)
        else
            return false
        end
    else
        -- CROUCHING: evaluate exit only after minimum hold has elapsed.
        if not wantCrouch and now >= self._gekkoCrouchHoldUntil then
            -- One-shot clearance check: is there a ceiling preventing stand-up?
            local ceilingBlocked = RawClearanceCheck(self)
            self._gekkoCeilingHit = ceilingBlocked  -- update debug field

            if ceilingBlocked then
                -- Ceiling is present; stay crouched regardless of triggers.
                -- Extend hold so we re-check next frame without spamming exits.
                self._gekkoCrouchHoldUntil = now + 0.1
                print("[GeckoCrouch] Ceiling blocked stand-up — holding")
            else
                -- All triggers gone, hold elapsed, no ceiling — stand up.
                self._gekkoRandomCrouch      = false
                self._gekkoRandomCrouchEndT  = 0
                self._gekkoRandomCrouchNextT = now + math.Rand(RAND_CHECK_MIN, RAND_CHECK_MAX)
                ExitCrouch(self)
                return false
            end
        end
        -- Still crouching (hold active, or trigger still active, or ceiling).
    end

    -- ── Crouch is active: drive animation ─────────────────────────
    if self.GekkoSeq_CrouchIdle == -1 then return true end

    local vel    = self:GetVelocity()
    local speed2 = vel.x * vel.x + vel.y * vel.y
    local moving = speed2 > (16 * 16)
    local targetSeq = (moving and self.GekkoSeq_CrouchWalk ~= -1)
        and self.GekkoSeq_CrouchWalk or self.GekkoSeq_CrouchIdle

    if self._gekkoCrouchSeqSet ~= targetSeq then
        self._gekkoCrouchSeqSet = targetSeq
        self:ResetSequence(targetSeq)
        self:SetCycle(0)
        if moving then
            local speed  = math.sqrt(speed2)
            local maxSpd = (self.MoveSpeed and self.MoveSpeed > 0) and self.MoveSpeed or 150
            self:SetPlaybackRate(math.Clamp(speed / maxSpd, 0.3, 1.5))
        else
            self:SetPlaybackRate(1.0)
        end
        self.Gekko_LastSeqIdx  = targetSeq
        self.Gekko_LastSeqName = moving and "c_walk" or "cidle"
        print(string.format("[GeckoCrouch] Seq → %s (%d) moving=%s",
            self.Gekko_LastSeqName, targetSeq, tostring(moving)))
    else
        self:SetSequence(targetSeq)
    end

    self:SetPoseParameter("move_x", 0)
    self:SetPoseParameter("move_y", 0)
    self.VJ_IsMoving     = false
    self.VJ_CanMoveThink = false
    return true
end
