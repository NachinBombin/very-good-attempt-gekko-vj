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
        return ent._gekkoCeilingHit
    end
    ent._gekkoCeilNextT = now + CEIL_CHECK_INTERVAL

    local pos    = ent:GetPos()
    local startZ = pos.z + HITBOX_STAND_H - 4
    local endZ   = pos.z + HITBOX_STAND_H + CEIL_CLEARANCE + CEIL_TRACE_EXTRA

    local tr = util.TraceLine({
        start  = Vector(pos.x, pos.y, startZ),
        endpos = Vector(pos.x, pos.y, endZ),
        filter = ent,
        mask   = MASK_SOLID,
    })

    local hit = false
    if tr.Hit then
        local gap = tr.HitPos.z - (pos.z + HITBOX_STAND_H)
        hit = (gap <= CEIL_CLEARANCE)
        if hit then
            print(string.format(
                "[GeckoCrouch] CeilingTrace | gap=%.1f → CROUCHING",
                gap
            ))
        end
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
    self._gekkoCrouching           = false
    self._gekkoCrouchHoldUntil     = -1
    self._gekkoCrouchJustEntered   = false
    self._gekkoObsRearmT           = 0
    self._gekkoObsOnSince          = nil
    self._gekkoObsDebounced        = false
    self._gekkoObsHullHit          = false
    self._gekkoCeilingHit          = false
    self._gekkoCeilNextT           = 0
    self.GekkoSeq_CrouchWalk       = -1
    self.GekkoSeq_CrouchIdle       = -1
    self._gekkoCrouchSeqSet        = -1
    self._gekkoRandomCrouch        = false
    self._gekkoRandomCrouchEndT    = 0
    self._gekkoRandomDuration      = 0
    self._gekkoRandomCrouchNextT   = CurTime() + math.Rand(RAND_CHECK_MIN, RAND_CHECK_MAX)
    self._gekkoDodgeCrouch         = false
    self._gekkoDodgeCrouchUntil    = 0
    self._gekkoDodgeCrouchForced   = false
    print("[GeckoCrouch] Init() complete")
end

-- ─────────────────────────────────────────────────────────────
--  GeckoCrouch_CacheSeqs
-- ─────────────────────────────────────────────────────────────
function ENT:GeckoCrouch_CacheSeqs()
    local cwalk = self:LookupSequence("c_walk")
    local cidle = self:LookupSequence("cidle")
    self.GekkoSeq_CrouchWalk = (cwalk and cwalk ~= -1) and cwalk or -1
    self.GekkoSeq_CrouchIdle = (cidle and cidle ~= -1) and cidle or -1
    print(string.format(
        "[GeckoCrouch] CacheSeqs | c_walk=%d  cidle=%d",
        self.GekkoSeq_CrouchWalk, self.GekkoSeq_CrouchIdle
    ))
end

-- ─────────────────────────────────────────────────────────────
--  EnterCrouch
--  holdDuration: explicit lock duration (seconds). When called from
--  a dodge, pass the full slide duration so _gekkoCrouchHoldUntil
--  always covers the entire dodge window.
-- ─────────────────────────────────────────────────────────────
local function EnterCrouch(ent, randDuration, holdDuration)
    local now = CurTime()
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

    print(string.format("[GeckoCrouch] → Crouching holdLen=%.1fs  holdUntil=%.2f",
        holdLen, ent._gekkoCrouchHoldUntil))
end

-- ─────────────────────────────────────────────────────────────
--  ExitCrouch
--  Guards: will NOT exit while any dodge/slide lock is active.
-- ─────────────────────────────────────────────────────────────
local function ExitCrouch(ent)
    local now = CurTime()
    -- FIX: guard on BOTH _pedestalSliding and _gekkoDodgeCrouchUntil
    if ent._pedestalSliding then return end
    if ent._gekkoDodgeCrouch and now < (ent._gekkoDodgeCrouchUntil or 0) then
        return
    end

    ent._gekkoCrouching           = false
    ent._gekkoCrouchJustEntered   = false
    ent._gekkoCrouchSeqSet        = -1
    ent._gekkoDodgeCrouch         = false
    ent._gekkoDodgeCrouchUntil    = 0
    ent._gekkoDodgeCrouchForced   = false
    ent._gekkoObsRearmT           = now + STAND_REARM_DELAY
    ent._gekkoObsOnSince          = nil
    ent._gekkoObsDebounced        = false
    ent._gekkoObsHullHit          = false
    ent._gekkoCeilingHit          = false
    ent._gekkoCeilNextT           = 0
    ent._gekkoRandomCrouch        = false
    ent._gekkoRandomCrouchEndT    = 0
    ent._gekkoRandomDuration      = 0
    ent._gekkoRandomCrouchNextT   = now + math.Rand(RAND_CHECK_MIN, RAND_CHECK_MAX)

    ent:SetCollisionBounds(
        Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0),
        Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_STAND_H)
    )

    ent:SetNWBool("GekkoIsCrouching", false)
    ent.VJ_CanMoveThink = true

    print("[GeckoCrouch] → Standing")
end

-- ─────────────────────────────────────────────────────────────
--  EnforceSequence  (shared between normal path and force-tick path)
--
--  Reads the current speed from the live physics velocity when in a
--  dodge slide (MOVETYPE_FLY), otherwise from the NWFloat.
--  Calls ResetSequence every tick to beat VJ Base's own reassertion.
-- ─────────────────────────────────────────────────────────────
local function EnforceSequence(ent)
    -- Lazy re-cache if model wasn't loaded yet at spawn time
    if ent.GekkoSeq_CrouchWalk == -1 then
        local cwalk = ent:LookupSequence("c_walk")
        local cidle = ent:LookupSequence("cidle")
        ent.GekkoSeq_CrouchWalk = (cwalk and cwalk ~= -1) and cwalk or -1
        ent.GekkoSeq_CrouchIdle = (cidle and cidle ~= -1) and cidle or -1
        if ent.GekkoSeq_CrouchWalk == -1 then
            ent.GekkoSeq_CrouchWalk = ent.GekkoSeq_Idle or 0
        end
        ent._gekkoCrouchSeqSet = -1
    end

    local speed = ent:GetNWFloat("GekkoSpeed", 0)
    if ent._pedestalSliding or ent._gekkoDodgeCrouch then
        local v = ent:GetVelocity()
        speed = math.sqrt(v.x * v.x + v.y * v.y)
    end

    local rate, targetSeq

    if speed > CWALK_MOVING_THRESH then
        rate      = math.Clamp(speed / DEFAULT_MOVE_SPEED, 0.3, 1.5)
        targetSeq = ent.GekkoSeq_CrouchWalk
    else
        rate      = CWALK_STATIONARY_RATE
        targetSeq = (ent.GekkoSeq_CrouchIdle ~= -1)
                    and ent.GekkoSeq_CrouchIdle
                    or  ent.GekkoSeq_CrouchWalk
    end

    if not targetSeq or targetSeq == -1 then
        targetSeq = ent.GekkoSeq_CrouchWalk
    end

    if targetSeq and targetSeq ~= -1 then
        if ent._gekkoCrouchSeqSet ~= targetSeq then
            ent:ResetSequence(targetSeq)
            ent._gekkoCrouchSeqSet = targetSeq
            print(string.format("[GeckoCrouch] SeqSwitch → %d (speed=%.1f)", targetSeq, speed))
        else
            ent:ResetSequence(targetSeq)
        end
        ent:SetPlaybackRate(rate)
    end

    ent:SetPoseParameter("move_x", 0)
    ent:SetPoseParameter("move_y", 0)
    ent.Gekko_LastSeqName = (targetSeq == ent.GekkoSeq_CrouchWalk) and "c_walk" or "cidle"
end

-- ─────────────────────────────────────────────────────────────
--  Dodge_EnterCrouch
--  Called by pedestal_dodge_system.lua before BeginSlide fires.
--  Sets both the dodge flags AND calls EnterCrouch with the explicit
--  slide duration so _gekkoCrouchHoldUntil covers the full dodge.
-- ─────────────────────────────────────────────────────────────
function ENT:Dodge_EnterCrouch(slideDuration)
    local now = CurTime()
    self._gekkoDodgeCrouch       = true
    self._gekkoDodgeCrouchUntil  = now + slideDuration
    self._gekkoDodgeCrouchForced = true
    -- Pass slideDuration as holdDuration so the hold timer is set to at
    -- least the slide length regardless of CROUCH_HOLD_MIN.
    EnterCrouch(self, nil, slideDuration)
    print(string.format("[GeckoCrouch] Dodge_EnterCrouch | dur=%.2fs  holdUntil=%.2f",
        slideDuration, self._gekkoCrouchHoldUntil))
end

-- ─────────────────────────────────────────────────────────────
--  GeckoCrouch_Update
--  Called every tick from GekkoUpdateAnimation().
--  Returns true  → crouch active this tick (caller must return)
--  Returns false → crouch inactive
-- ─────────────────────────────────────────────────────────────
function ENT:GeckoCrouch_Update()
    local now = CurTime()

    -- ── DODGE LOCK: extend hold timer every tick while active ────
    -- This is the primary fix. Every tick that the dodge or slide is
    -- active we push _gekkoCrouchHoldUntil forward, so the expiry
    -- path inside the crouching branch can NEVER reach ExitCrouch.
    local dodgeActive    = self._gekkoDodgeCrouch and now < (self._gekkoDodgeCrouchUntil or 0)
    local slideActive    = self._pedestalSliding
    local anyLock        = dodgeActive or slideActive
    if anyLock and self._gekkoCrouching then
        -- Keep the hold timer at least 0.5 s ahead so it cannot expire
        -- mid-dodge even if a frame takes longer than expected.
        local needed = now + 0.5
        if (self._gekkoCrouchHoldUntil or 0) < needed then
            self._gekkoCrouchHoldUntil = needed
        end
    end
    -- ─────────────────────────────────────────────────────────

    -- ── FORCE-TICK PATH ──────────────────────────────────────
    -- Called directly by BeginSlide BEFORE SetMoveType(FLY).
    -- _gekkoCrouching and _gekkoDodgeCrouch are already set by
    -- Dodge_EnterCrouch. Skip all guards; stamp the sequence now
    -- in the same callstack so VJ Base cannot win the reassertion race.
    if self._gekkoDodgeCrouchForced then
        self._gekkoDodgeCrouchForced = false
        EnforceSequence(self)
        return true
    end
    -- ─────────────────────────────────────────────────────────

    local jumpState  = self:GetGekkoJumpState()
    local jumpActive = jumpState == self.JUMP_RISING  or
                       jumpState == self.JUMP_FALLING or
                       jumpState == self.JUMP_LAND

    if jumpActive and not anyLock then return false end

    if not self._gekkoCrouching then
        if self._gekkoSuppressActivity and now < self._gekkoSuppressActivity then
            return false
        end
    end

    TickRandom(self)
    local ceilHit = CeilingCheck(self)
    local obsHit  = false
    if not self._gekkoCrouching then
        obsHit = TickObstacle(self)
    end

    local vjCrouch   = (self.VJ_IsBeingCrouched == true)
    local randActive = self._gekkoRandomCrouch
    local wantCrouch = vjCrouch or obsHit or ceilHit or randActive or anyLock

    if not self._crouchDiagT or now > self._crouchDiagT then
        print(string.format(
            "[GeckoCrouch] Update | crouching=%s  want=%s  vj=%s  obs=%s  ceil=%s  rand=%s  dodge=%s  slide=%s  holdLeft=%.2f  rearmLeft=%.2f",
            tostring(self._gekkoCrouching), tostring(wantCrouch),
            tostring(vjCrouch), tostring(obsHit), tostring(ceilHit), tostring(randActive),
            tostring(dodgeActive), tostring(slideActive),
            math.max(0, self._gekkoCrouchHoldUntil - now),
            math.max(0, self._gekkoObsRearmT - now)
        ))
        self._crouchDiagT = now + 2
    end

    if not self._gekkoCrouching then
        if wantCrouch then
            local randDur = randActive and self._gekkoRandomDuration or nil
            EnterCrouch(self, randDur, nil)
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
