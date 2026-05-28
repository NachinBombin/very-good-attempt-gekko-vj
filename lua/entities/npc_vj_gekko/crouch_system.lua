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
    -- Dodge-crouch dedicated flag (set by pedestal_dodge_system)
    self._gekkoDodgeCrouch         = false
    self._gekkoDodgeCrouchUntil    = 0
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
-- ─────────────────────────────────────────────────────────────
local function EnterCrouch(ent, randDuration)
    local now = CurTime()
    ent._gekkoCrouching         = true
    ent._gekkoCrouchJustEntered = true
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

    print(string.format("[GeckoCrouch] → Crouching holdLen=%.1fs  holdUntil=%.2f",
        holdLen, ent._gekkoCrouchHoldUntil))
end

-- ─────────────────────────────────────────────────────────────
--  ExitCrouch
-- ─────────────────────────────────────────────────────────────
local function ExitCrouch(ent)
    local now = CurTime()
    ent._gekkoCrouching           = false
    ent._gekkoCrouchJustEntered   = false
    ent._gekkoCrouchSeqSet        = -1
    ent._gekkoDodgeCrouch         = false
    ent._gekkoDodgeCrouchUntil    = 0
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
--  GeckoCrouch_Update
--  Called every tick from GekkoUpdateAnimation().
--  Returns true  → crouch active this tick (caller must return)
--  Returns false → crouch inactive
-- ─────────────────────────────────────────────────────────────
function ENT:GeckoCrouch_Update()
    local now = CurTime()

    local jumpState  = self:GetGekkoJumpState()
    local jumpActive = jumpState == self.JUMP_RISING  or
                       jumpState == self.JUMP_FALLING or
                       jumpState == self.JUMP_LAND
    if jumpActive then return false end

    -- Suppress guard: skip entry logic ONLY when not already crouching.
    -- A dodge slide sets _gekkoCrouching=true AND _gekkoSuppressActivity,
    -- so we must let the crouch sequence block run even while suppressed.
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
    local wantCrouch = vjCrouch or obsHit or ceilHit or randActive

    -- A dodge-triggered crouch is authoritative for its entire window.
    -- It does not need any of the normal wantCrouch conditions to be true.
    -- This prevents the race condition where _pedestalSliding clears on the
    -- same tick that _gekkoCrouchHoldUntil expires, causing a premature exit
    -- before the sequence block ever runs with the correct physics velocity.
    local dodgeActive = self._gekkoDodgeCrouch and now < (self._gekkoDodgeCrouchUntil or 0)
    if dodgeActive then
        wantCrouch = true
    end

    if not self._crouchDiagT or now > self._crouchDiagT then
        print(string.format(
            "[GeckoCrouch] Update | crouching=%s  want=%s  vj=%s  obs=%s  ceil=%s  rand=%s  dodge=%s  holdLeft=%.2f  rearmLeft=%.2f",
            tostring(self._gekkoCrouching), tostring(wantCrouch),
            tostring(vjCrouch), tostring(obsHit), tostring(ceilHit), tostring(randActive),
            tostring(dodgeActive),
            math.max(0, self._gekkoCrouchHoldUntil - now),
            math.max(0, self._gekkoObsRearmT - now)
        ))
        self._crouchDiagT = now + 2
    end

    if not self._gekkoCrouching then
        if wantCrouch then
            local randDur = randActive and self._gekkoRandomDuration or nil
            EnterCrouch(self, randDur)
        else
            return false
        end
    else
        if ceilHit then
            if not self._pedestalSliding then
                self._gekkoCrouchHoldUntil = now + CROUCH_HOLD_MIN
            end
        end

        if now >= self._gekkoCrouchHoldUntil and not self._pedestalSliding and not dodgeActive then
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

    -- ── Sequence enforcement ──────────────────────────────────
    -- ResetSequence is called every tick to beat VJ base's own
    -- per-frame ResetSequence calls. SetSequence alone is not
    -- enough — VJ reasserts its chosen sequence immediately after.
    --
    -- During a reactive dodge slide the NPC is on MOVETYPE_FLYGRAVITY
    -- with VJ locomotion frozen, so GekkoSpeed (NWFloat) may lag by one
    -- tick. Read the live physics velocity instead so c_walk is correctly
    -- selected for the full slide duration.
    --
    -- Lazy re-cache: GeckoCrouch_CacheSeqs() runs in a deferred timer at
    -- spawn. If the workshop model hasn't finished loading yet, LookupSequence
    -- returns -1. Re-attempt every tick until we get a valid sequence index.
    if self.GekkoSeq_CrouchWalk == -1 then
        local cwalk = self:LookupSequence("c_walk")
        local cidle = self:LookupSequence("cidle")
        self.GekkoSeq_CrouchWalk = (cwalk and cwalk ~= -1) and cwalk or -1
        self.GekkoSeq_CrouchIdle = (cidle and cidle ~= -1) and cidle or -1
        if self.GekkoSeq_CrouchWalk == -1 then
            -- Model has no c_walk at all; fall back to stand-idle so at
            -- least the NPC holds a valid pose rather than T-posing.
            self.GekkoSeq_CrouchWalk = self.GekkoSeq_Idle or 0
        end
        self._gekkoCrouchSeqSet = -1  -- force ResetSequence on next tick
    end

    local speed = self:GetNWFloat("GekkoSpeed", 0)
    if self._pedestalSliding or dodgeActive then
        local v = self:GetVelocity()
        speed = math.sqrt(v.x * v.x + v.y * v.y)
    end

    local rate, targetSeq

    if speed > CWALK_MOVING_THRESH then
        rate      = math.Clamp(speed / DEFAULT_MOVE_SPEED, 0.3, 1.5)
        targetSeq = self.GekkoSeq_CrouchWalk
    else
        rate      = CWALK_STATIONARY_RATE
        targetSeq = (self.GekkoSeq_CrouchIdle ~= -1)
                    and self.GekkoSeq_CrouchIdle
                    or  self.GekkoSeq_CrouchWalk
    end

    if not targetSeq or targetSeq == -1 then
        targetSeq = self.GekkoSeq_CrouchWalk
    end

    if targetSeq and targetSeq ~= -1 then
        if self._gekkoCrouchSeqSet ~= targetSeq then
            -- Switched crouch sequence (walk↔idle): hard reset + log
            self:ResetSequence(targetSeq)
            self._gekkoCrouchSeqSet = targetSeq
            print(string.format("[GeckoCrouch] SeqSwitch → %d (speed=%.1f)", targetSeq, speed))
        else
            -- Same sequence: reset every tick to overwrite VJ's reassertion
            self:ResetSequence(targetSeq)
        end
        self:SetPlaybackRate(rate)
    end

    self:SetPoseParameter("move_x", 0)
    self:SetPoseParameter("move_y", 0)
    self.Gekko_LastSeqName = (targetSeq == self.GekkoSeq_CrouchWalk) and "c_walk" or "cidle"

    return true
end
