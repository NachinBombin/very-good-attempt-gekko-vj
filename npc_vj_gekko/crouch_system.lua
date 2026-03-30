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
--  Exit gate is timer-only.  A ceiling clearance check was attempted
--  in earlier revisions but produced false-positives on flat ground
--  because TraceLine from (pos+CROUCH_H) to (pos+STAND_H) clips into
--  world/skybox brushes on most maps.  For a walking tank on terrain
--  a simple hold timer is the correct and sufficient guard.
--
--  Called from:
--    ENT:Init()                 → self:GeckoCrouch_Init()
--    ENT:GekkoUpdateAnimation() → self:GeckoCrouch_Update()
-- ============================================================

-- ─────────────────────────────────────────────────────────────
--  Tuning constants
-- ─────────────────────────────────────────────────────────────

-- Minimum time the NPC must stay crouched before exit is evaluated.
local CROUCH_HOLD_MIN   = 1.2

-- After standing back up, delay before the forward obstacle trace
-- is re-armed.  Prevents the trace from firing on the same frame
-- the NPC returns to standing height.
local STAND_REARM_DELAY = 0.6

-- Forward lookahead distance (units).
local HULL_LOOKAHEAD    = 80

-- Obstacle debounce: trace must report a hit for this long before
-- committing to a crouch.
local OBS_ON_DEBOUNCE   = 0.20

-- Hitbox heights (units above entity origin / foot level).
local HITBOX_STAND_H    = 200
local HITBOX_CROUCH_H   = 130
local HITBOX_HALF_W     = 64

-- Random crouch behaviour
local RAND_CHECK_MIN    = 4
local RAND_CHECK_MAX    = 12
local RAND_CHANCE       = 0.30
local RAND_DUR_MIN      = 3
local RAND_DUR_MAX      = 10

-- ─────────────────────────────────────────────────────────────
--  Hull shapes (computed once)
-- ─────────────────────────────────────────────────────────────
-- Forward obstacle trace: crouch-height hull so it only catches
-- obstacles low enough to actually require ducking.
local HULL_FWD_MIN = Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0)
local HULL_FWD_MAX = Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_CROUCH_H)

-- ─────────────────────────────────────────────────────────────
--  RawObstacleCheck  (standing only)
--  Projects the crouch-height hull straight ahead.
--  Returns true → something blocks the path at crouch height.
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
--  Runs ONLY while standing AND the re-arm timer has elapsed.
--  Debounces the raw trace result before committing to a crouch.
--  Returns true once a sustained hit is confirmed.
--
--  NOTE: writes _gekkoObsHullHit (NOT _gekkoCeilingHit) for the
--  debug HUD.  Keeping these two fields separate prevents obstacle
--  trace results from bleeding into stand-up decisions.
-- ─────────────────────────────────────────────────────────────
local function TickObstacle(ent)
    local now = CurTime()

    if now < ent._gekkoObsRearmT then
        ent._gekkoObsOnSince  = nil
        ent._gekkoObsHullHit  = false
        return false
    end

    local raw = RawObstacleCheck(ent)
    ent._gekkoObsHullHit = raw   -- debug HUD only — never used for exit decisions

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
    self._gekkoObsHullHit        = false   -- debug HUD: forward obstacle trace result
    self._gekkoCeilingHit        = false   -- debug HUD: kept for init.lua compat, always false now
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
--  EnterCrouch / ExitCrouch  — state transition helpers
-- ─────────────────────────────────────────────────────────────
local function EnterCrouch(ent)
    local now = CurTime()
    ent._gekkoCrouching       = true
    ent._gekkoCrouchHoldUntil = now + CROUCH_HOLD_MIN
    ent._gekkoCrouchSeqSet    = -1
    ent._gekkoObsOnSince      = nil
    ent._gekkoObsDebounced    = false
    ent._gekkoObsHullHit      = false   -- clear stale obstacle data from standing phase
    ent._gekkoCeilingHit      = false   -- clear for HUD consistency
    ent:SetCollisionBounds(
        Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0),
        Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_CROUCH_H)
    )
    ent.VJ_CanMoveThink = false
    print("[GeckoCrouch] → Crouching h=" .. HITBOX_CROUCH_H)
end

local function ExitCrouch(ent)
    local now = CurTime()
    ent._gekkoCrouching    = false
    ent._gekkoCrouchSeqSet = -1
    ent._gekkoObsRearmT    = now + STAND_REARM_DELAY
    ent._gekkoObsOnSince   = nil
    ent._gekkoObsDebounced = false
    ent._gekkoObsHullHit   = false
    ent._gekkoCeilingHit   = false
    ent:SetCollisionBounds(
        Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0),
        Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_STAND_H)
    )
    ent.VJ_CanMoveThink = true
    print("[GeckoCrouch] → Standing h=" .. HITBOX_STAND_H)
end

-- ─────────────────────────────────────────────────────────────
--  GeckoCrouch_Update
--  Returns true  → crouch is active, caller must return early
--  Returns false → crouch is inactive, caller continues normally
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

    -- Obstacle lookahead only runs while STANDING.
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
        -- STANDING → only enter if a trigger is active.
        if wantCrouch then
            EnterCrouch(self)
            -- Fall through to animation block on this same tick.
        else
            return false
        end
    else
        -- CROUCHING.

        -- Safety stamp: guard against any edge case where the hold
        -- was never set (e.g. jump interrupt re-entry).
        if self._gekkoCrouchHoldUntil <= 0 then
            self._gekkoCrouchHoldUntil = now + CROUCH_HOLD_MIN
            print("[GeckoCrouch] Hold re-stamped (was zero)")
        end

        -- Exit only after the minimum hold AND all triggers have dropped.
        -- No clearance trace — timer-only gate is correct for this NPC.
        if not wantCrouch and now >= self._gekkoCrouchHoldUntil then
            self._gekkoRandomCrouch      = false
            self._gekkoRandomCrouchEndT  = 0
            self._gekkoRandomCrouchNextT = now + math.Rand(RAND_CHECK_MIN, RAND_CHECK_MAX)
            ExitCrouch(self)
            return false
        end
        -- Still crouching: hold active or a trigger is still live.
    end

    -- ── Crouch is active: drive the animation ─────────────────────
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
