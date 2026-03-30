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
-- ============================================================

-- ─────────────────────────────────────────────────────────────
--  Tuning constants
-- ─────────────────────────────────────────────────────────────

local CROUCH_HOLD_MIN   = 2.0
local STAND_REARM_DELAY = 0.8
local HULL_LOOKAHEAD    = 96
local OBS_ON_DEBOUNCE   = 0.25
local HITBOX_STAND_H    = 200
local HITBOX_CROUCH_H   = 130
local HITBOX_HALF_W     = 64
local OBS_MIN_VELOCITY  = 20

local RAND_CHECK_MIN    = 6
local RAND_CHECK_MAX    = 16
local RAND_CHANCE       = 0.25
local RAND_DUR_MIN      = 3
local RAND_DUR_MAX      = 10

-- ─────────────────────────────────────────────────────────────
--  Hull shapes
--  mins.z = 12 so the hull does not clip the ground plane.
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
--  TickObstacle  (only while STANDING and moving)
-- ─────────────────────────────────────────────────────────────
local function TickObstacle(ent)
    local now = CurTime()

    if now < ent._gekkoObsRearmT then
        ent._gekkoObsOnSince  = nil
        ent._gekkoObsHullHit  = false
        return false
    end

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
--
--  FIX: The expire check must only use _gekkoCrouchHoldUntil
--  when the entity is actually crouching.  On the first tick
--  that random fires, _gekkoCrouchHoldUntil is still 0 (from
--  Init) because EnterCrouch hasn't run yet.  Without the
--  _gekkoCrouching guard, "now >= 0" is always true and the
--  random flag is immediately cleared before EnterCrouch can
--  stamp the hold — causing a sub-frame crouch.
-- ─────────────────────────────────────────────────────────────
local function TickRandom(ent)
    local now = CurTime()

    if ent._gekkoRandomCrouch then
        -- Expire only when:
        --   (a) our own random duration has elapsed, AND
        --   (b) either we are not yet crouching (pre-Enter tick),
        --       OR the mandatory hold has also elapsed.
        local holdDone = (not ent._gekkoCrouching) or (now >= ent._gekkoCrouchHoldUntil)
        if now >= ent._gekkoRandomCrouchEndT and holdDone then
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
        -- Honour at least CROUCH_HOLD_MIN even if dur < CROUCH_HOLD_MIN
        ent._gekkoRandomCrouchEndT = now + math.max(dur, CROUCH_HOLD_MIN)
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
    self._gekkoCrouchHoldUntil   = -1    -- Use -1 (not 0) so "now >= -1" is always
                                          -- true when not crouching, and the safety
                                          -- re-stamp guard never fires spuriously.
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
--  EnterCrouch
-- ─────────────────────────────────────────────────────────────
local function EnterCrouch(ent)
    local now = CurTime()
    ent._gekkoCrouching       = true
    -- Stamp hold NOW — this is the single authoritative write.
    ent._gekkoCrouchHoldUntil = now + CROUCH_HOLD_MIN
    ent._gekkoCrouchSeqSet    = -1
    ent._gekkoObsOnSince      = nil
    ent._gekkoObsDebounced    = false
    ent._gekkoObsHullHit      = false
    ent._gekkoCeilingHit      = false
    ent:SetCollisionBounds(
        Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0),
        Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_CROUCH_H)
    )
    ent:SetNWBool("GekkoIsCrouching", true)
    ent.MoveSpeed = 0
    ent.RunSpeed  = 0
    ent.WalkSpeed = 0
    print("[GeckoCrouch] → Crouching h=" .. HITBOX_CROUCH_H)
end

-- ─────────────────────────────────────────────────────────────
--  ExitCrouch
-- ─────────────────────────────────────────────────────────────
local function ExitCrouch(ent)
    local now = CurTime()
    ent._gekkoCrouching         = false
    -- Do NOT zero _gekkoCrouchHoldUntil here.  Leave it at its last
    -- stamped value (a time in the past) so the safety re-stamp guard
    -- inside GeckoCrouch_Update never fires on the re-entry tick.
    ent._gekkoCrouchSeqSet      = -1
    ent._gekkoObsRearmT         = now + STAND_REARM_DELAY
    ent._gekkoObsOnSince        = nil
    ent._gekkoObsDebounced      = false
    ent._gekkoObsHullHit        = false
    ent._gekkoCeilingHit        = false
    -- Clear random state so it cannot immediately re-trigger.
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
--  Returns true  → crouch active (caller must return early)
--  Returns false → crouch inactive
-- ─────────────────────────────────────────────────────────────
function ENT:GeckoCrouch_Update()
    local now = CurTime()

    -- ── Jump interrupt — only allowed when the hold has fully expired ──
    local jumpState  = self:GetGekkoJumpState()
    local jumpActive = jumpState == self.JUMP_RISING  or
                       jumpState == self.JUMP_FALLING or
                       jumpState == self.JUMP_LAND

    if jumpActive then
        if self._gekkoCrouching then
            -- Jump may break the crouch only after the mandatory hold.
            if now >= self._gekkoCrouchHoldUntil then
                ExitCrouch(self)
                return false
            end
            -- Hold still active: stay crouched but let jump animation run.
            -- Return false so GekkoUpdateAnimation handles jump seq.
            return false
        end
        return false
    end

    if self._gekkoSuppressActivity and now < self._gekkoSuppressActivity then
        return false
    end

    -- ── Tick sub-systems ─────────────────────────────────────────
    -- TickRandom first so _gekkoRandomCrouch is up to date before
    -- we evaluate wantCrouch below.
    TickRandom(self)

    local obsHit = false
    if not self._gekkoCrouching then
        obsHit = TickObstacle(self)
    end

    -- ── Evaluate triggers ────────────────────────────────────────
    local vjCrouch   = (self.VJ_IsBeingCrouched == true)
    local randActive = self._gekkoRandomCrouch
    local wantCrouch = vjCrouch or obsHit or randActive

    -- ── Diagnostics ──────────────────────────────────────────────
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

        -- Exit only when:
        --   (a) the mandatory hold has fully elapsed, AND
        --   (b) ALL triggers have dropped.
        if not wantCrouch and now >= self._gekkoCrouchHoldUntil then
            ExitCrouch(self)
            return false
        end
        -- Still crouching: fall through to animation block.
    end

    -- ── Crouch animation ──────────────────────────────────────────
    -- ResetSequence is called ONLY when the target sequence changes.
    -- Never called every tick — that resets the cycle to 0 each frame.
    if self.GekkoSeq_CrouchIdle == -1 then
        return true
    end

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

    self:SetPoseParameter("move_x", 0)
    self:SetPoseParameter("move_y", 0)
    return true
end
