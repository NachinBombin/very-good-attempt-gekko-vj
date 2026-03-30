-- ============================================================
--  crouch_system.lua
--  Gekko VJ NPC — Crouch mechanic
--
--  Triggers (any one is enough to crouch):
--    1. VJ Base native crouch flag (VJ_IsBeingCrouched)   — immediate
--    2. Standing-hull lookahead (TraceHull forward)        — debounced
--    3. Ceiling trace (TraceLine upward from head)         — immediate
--    4. Random timed behaviour                             — timer-based
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
--  Animation:
--    Always uses c_walk.  Playback rate is driven by XY speed so the
--    animation appears stationary when the Gekko is not moving.
--    cidle is never used from this system.
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

-- Ceiling check: fire a line straight up from the top of the standing hull.
--
-- CEIL_CLEARANCE: how many units of headroom we need above the hull top
--   before we consider the ceiling "not an issue".  If something is
--   within CEIL_CLEARANCE units above the hull top, wantCrouch becomes true.
--
-- CEIL_TRACE_EXTRA: extra units traced beyond CEIL_CLEARANCE so that
--   ceilings which are further away are still discovered and the NPC
--   has time to react before it actually clips.
--
--   The full trace travels:
--     from  pos.z + (HITBOX_STAND_H - 4)    ← just below hull top
--     to    pos.z + HITBOX_STAND_H + CEIL_CLEARANCE + CEIL_TRACE_EXTRA
--
--   Any hit whose HitPos is within CEIL_CLEARANCE above the hull top
--   triggers a crouch.  Hits further away are logged but ignored.
--
local CEIL_CHECK_INTERVAL = 0.12   -- seconds between ceiling traces
local CEIL_CLEARANCE      = 60     -- units: headroom needed to stay standing
local CEIL_TRACE_EXTRA    = 80     -- extra lookahead so the NPC pre-crouches

local RAND_CHECK_MIN    = 6
local RAND_CHECK_MAX    = 16
local RAND_CHANCE       = 0.25
local RAND_DUR_MIN      = 3
local RAND_DUR_MAX      = 10

-- Playback rate for c_walk when the Gekko is standing still while crouched.
-- Low enough that the animation crawls and reads as "idle".
local CWALK_STATIONARY_RATE = 0.05

-- ─────────────────────────────────────────────────────────────
--  Hull shapes
--  mins.z = 12 so the hull does not clip the ground plane.
-- ─────────────────────────────────────────────────────────────
local HULL_FWD_MIN = Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 12)
local HULL_FWD_MAX = Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_CROUCH_H)

-- ─────────────────────────────────────────────────────────────
--  RawObstacleCheck  (forward hull)
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
--  CeilingCheck
--
--  Fires a line from just below the top of the standing hull
--  upward by (CEIL_CLEARANCE + CEIL_TRACE_EXTRA) units.
--
--  A hit whose HitPos.z is within CEIL_CLEARANCE of the hull
--  top means the ceiling is too close — return true (crouch).
--
--  Throttled by CEIL_CHECK_INTERVAL for performance.
-- ─────────────────────────────────────────────────────────────
local function CeilingCheck(ent)
    local now = CurTime()
    if now < (ent._gekkoCeilNextT or 0) then
        return ent._gekkoCeilingHit
    end
    ent._gekkoCeilNextT = now + CEIL_CHECK_INTERVAL

    local pos = ent:GetPos()

    -- Start just inside the hull top to avoid false hits on sloped floors.
    local startZ = pos.z + HITBOX_STAND_H - 4
    -- End far enough above to catch ceilings the NPC is approaching.
    local endZ   = pos.z + HITBOX_STAND_H + CEIL_CLEARANCE + CEIL_TRACE_EXTRA

    local tr = util.TraceLine({
        start  = Vector(pos.x, pos.y, startZ),
        endpos = Vector(pos.x, pos.y, endZ),
        filter = ent,
        mask   = MASK_SOLID,
    })

    local hit = false
    if tr.Hit then
        -- Only trigger if the ceiling is within CEIL_CLEARANCE of the hull top.
        local ceilZ    = tr.HitPos.z
        local hullTopZ = pos.z + HITBOX_STAND_H
        local gap      = ceilZ - hullTopZ
        hit = (gap <= CEIL_CLEARANCE)

        print(string.format(
            "[GeckoCrouch] CeilingTrace | hit=true  ceilZ=%.1f  hullTopZ=%.1f  gap=%.1f  TRIGGERING=%s",
            ceilZ, hullTopZ, gap, tostring(hit)
        ))
    end

    ent._gekkoCeilingHit = hit
    return hit
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
-- ─────────────────────────────────────────────────────────────
local function TickRandom(ent)
    local now = CurTime()

    if ent._gekkoRandomCrouch then return end
    if now < ent._gekkoRandomCrouchNextT then return end

    if math.random() < RAND_CHANCE then
        local dur = math.Rand(RAND_DUR_MIN, RAND_DUR_MAX)
        ent._gekkoRandomCrouch     = true
        ent._gekkoRandomCrouchEndT = now + dur
        ent._gekkoRandomDuration   = dur
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
    self._gekkoCrouchHoldUntil   = -1
    self._gekkoObsRearmT         = 0
    self._gekkoObsOnSince        = nil
    self._gekkoObsDebounced      = false
    self._gekkoObsHullHit        = false
    self._gekkoCeilingHit        = false
    self._gekkoCeilNextT         = 0
    self.GekkoSeq_CrouchWalk     = -1
    self._gekkoCrouchSeqSet      = -1
    self._gekkoRandomCrouch      = false
    self._gekkoRandomCrouchEndT  = 0
    self._gekkoRandomDuration    = 0
    self._gekkoRandomCrouchNextT = CurTime() + math.Rand(RAND_CHECK_MIN, RAND_CHECK_MAX)
    print("[GeckoCrouch] Init() — state vars created")
end

-- ─────────────────────────────────────────────────────────────
--  GeckoCrouch_CacheSeqs
--  Only c_walk is needed. cidle is intentionally not cached.
-- ─────────────────────────────────────────────────────────────
function ENT:GeckoCrouch_CacheSeqs()
    local cwalk = self:LookupSequence("c_walk")
    self.GekkoSeq_CrouchWalk = (cwalk and cwalk ~= -1) and cwalk or -1
    print(string.format(
        "[GeckoCrouch] CacheSeqs | c_walk=%d  (cidle not used)",
        self.GekkoSeq_CrouchWalk
    ))
end

-- ─────────────────────────────────────────────────────────────
--  EnterCrouch
-- ─────────────────────────────────────────────────────────────
local function EnterCrouch(ent, randDuration)
    local now = CurTime()
    ent._gekkoCrouching    = true
    local holdLen = CROUCH_HOLD_MIN
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
    ent.MoveSpeed = 0
    ent.RunSpeed  = 0
    ent.WalkSpeed = 0
    print(string.format("[GeckoCrouch] → Crouching h=%d  holdLen=%.1fs  holdUntil=%.2f",
        HITBOX_CROUCH_H, holdLen, ent._gekkoCrouchHoldUntil))
end

-- ─────────────────────────────────────────────────────────────
--  ExitCrouch
-- ─────────────────────────────────────────────────────────────
local function ExitCrouch(ent)
    local now = CurTime()
    ent._gekkoCrouching         = false
    ent._gekkoCrouchSeqSet      = -1
    ent._gekkoObsRearmT         = now + STAND_REARM_DELAY
    ent._gekkoObsOnSince        = nil
    ent._gekkoObsDebounced      = false
    ent._gekkoObsHullHit        = false
    ent._gekkoCeilingHit        = false
    ent._gekkoCeilNextT         = 0   -- force a fresh ceiling check next tick
    ent._gekkoRandomCrouch      = false
    ent._gekkoRandomCrouchEndT  = 0
    ent._gekkoRandomDuration    = 0
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

    -- Jump interrupt
    local jumpState  = self:GetGekkoJumpState()
    local jumpActive = jumpState == self.JUMP_RISING  or
                       jumpState == self.JUMP_FALLING or
                       jumpState == self.JUMP_LAND

    if jumpActive then return false end

    if self._gekkoSuppressActivity and now < self._gekkoSuppressActivity then
        return false
    end

    -- Sub-systems
    TickRandom(self)

    -- Ceiling check runs regardless of crouch state so we STAY crouched
    -- while overhead clearance is insufficient.
    local ceilHit = CeilingCheck(self)

    local obsHit = false
    if not self._gekkoCrouching then
        obsHit = TickObstacle(self)
    end

    -- Evaluate triggers
    local vjCrouch   = (self.VJ_IsBeingCrouched == true)
    local randActive = self._gekkoRandomCrouch
    local wantCrouch = vjCrouch or obsHit or ceilHit or randActive

    -- Diagnostics (throttled)
    if not self._crouchDiagT or now > self._crouchDiagT then
        print(string.format(
            "[GeckoCrouch] Update | crouching=%s  want=%s  vj=%s  obs=%s  ceil=%s  rand=%s  holdLeft=%.2f  rearmLeft=%.2f",
            tostring(self._gekkoCrouching), tostring(wantCrouch),
            tostring(vjCrouch), tostring(obsHit), tostring(ceilHit), tostring(randActive),
            math.max(0, self._gekkoCrouchHoldUntil - now),
            math.max(0, self._gekkoObsRearmT - now)
        ))
        self._crouchDiagT = now + 2
    end

    -- State machine
    if not self._gekkoCrouching then
        if wantCrouch then
            local randDur = randActive and self._gekkoRandomDuration or nil
            EnterCrouch(self, randDur)
            -- Fall through to animation block on this same tick.
        else
            return false
        end
    else
        -- CROUCHING.
        -- Ceiling still present → keep re-stamping the hold timer.
        if ceilHit then
            self._gekkoCrouchHoldUntil = now + CROUCH_HOLD_MIN
        end

        if now >= self._gekkoCrouchHoldUntil then
            -- Hold elapsed. Disarm random flag if it was the trigger.
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
            -- Another trigger still active — re-stamp to avoid flicker.
            self._gekkoCrouchHoldUntil = now + CROUCH_HOLD_MIN
        end
        -- Still crouching: fall through to animation block.
    end

    -- ─────────────────────────────────────────────────────────
    --  Crouch animation — always c_walk, rate drives appearance.
    --
    --  Moving  → rate proportional to XY speed  (0.3 – 1.5)
    --  Still   → CWALK_STATIONARY_RATE (very slow crawl = reads as idle)
    -- ─────────────────────────────────────────────────────────
    local cwalk = self.GekkoSeq_CrouchWalk
    if cwalk == -1 then return true end  -- no sequence found, crouch is still active

    -- Set the sequence once and let the engine advance the cycle.
    if self._gekkoCrouchSeqSet ~= cwalk then
        self._gekkoCrouchSeqSet = cwalk
        self:ResetSequence(cwalk)
        self:SetCycle(0)
        self.Gekko_LastSeqIdx  = cwalk
        self.Gekko_LastSeqName = "c_walk"
        print(string.format("[GeckoCrouch] Seq → c_walk (%d)", cwalk))
    end

    -- Update playback rate every tick so it tracks velocity smoothly.
    local vel    = self:GetVelocity()
    local speed2 = vel.x * vel.x + vel.y * vel.y
    if speed2 > (16 * 16) then
        local speed  = math.sqrt(speed2)
        local maxSpd = (self.StartMoveSpeed and self.StartMoveSpeed > 0)
            and self.StartMoveSpeed or 150
        self:SetPlaybackRate(math.Clamp(speed / maxSpd, 0.3, 1.5))
    else
        self:SetPlaybackRate(CWALK_STATIONARY_RATE)
    end

    self:SetPoseParameter("move_x", 0)
    self:SetPoseParameter("move_y", 0)
    return true
end
