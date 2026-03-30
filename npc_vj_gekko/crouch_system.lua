-- ============================================================
--  crouch_system.lua
--  Gekko VJ NPC — Crouch mechanic
--
--  Triggers (any one is enough to crouch):
--    1. VJ Base native crouch flag (VJ_IsBeingCrouched)        — immediate
--    2. Standing-hull lookahead (TraceHull forward, STAND hull) — debounced
--       Projects the full STANDING collision box ahead while the NPC
--       is upright.  When crouching, a vertical clearance check
--       decides whether standing back up is safe.
--    3. Random timed behaviour                                  — timer-based
--
--  Called from:
--    ENT:Init()                 → self:GeckoCrouch_Init()
--    ENT:GekkoUpdateAnimation() → self:GeckoCrouch_Update()
-- ============================================================

-- ─────────────────────────────────────────────────────────────
--  Tuning constants
-- ─────────────────────────────────────────────────────────────
local CROUCH_EXIT_LOCKOUT = 0.35

-- How far ahead to project the standing hull (units)
local HULL_LOOKAHEAD      = 80

-- Ceiling debounce
local CEIL_ON_DEBOUNCE    = 0.20
local CEIL_OFF_DEBOUNCE   = 0.40

-- Hitbox heights
local HITBOX_STAND_H   = 200
local HITBOX_CROUCH_H  = 130
local HITBOX_HALF_W    = 64

-- Random crouch behaviour
local RAND_CHECK_MIN  = 4
local RAND_CHECK_MAX  = 12
local RAND_CHANCE     = 0.30
local RAND_DUR_MIN    = 3
local RAND_DUR_MAX    = 10

-- ─────────────────────────────────────────────────────────────
--  Hull shapes (computed once)
-- ─────────────────────────────────────────────────────────────
-- Forward lookahead uses the STANDING hull → detects low ceilings ahead
local HULL_STAND_MIN = Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0)
local HULL_STAND_MAX = Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_STAND_H)

-- Vertical clearance uses only the extra Z slice needed to go from
-- crouched height to standing height (avoids re-testing the floor)
local HULL_VERT_MIN  = Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, HITBOX_CROUCH_H)
local HULL_VERT_MAX  = Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_STAND_H)

-- ─────────────────────────────────────────────────────────────
--  RawObstacleCheck
--  Called while STANDING.  Projects the full standing hull forward.
--  Returns true  → something blocks the NPC at full height → crouch.
-- ─────────────────────────────────────────────────────────────
local function RawObstacleCheck(ent)
    local pos = ent:GetPos()
    local fwd = ent:GetForward()
    fwd.z = 0
    fwd:Normalize()

    local tr = util.TraceHull({
        start  = pos,
        endpos = pos + fwd * HULL_LOOKAHEAD,
        mins   = HULL_STAND_MIN,
        maxs   = HULL_STAND_MAX,
        filter = ent,
        mask   = MASK_SOLID,
    })

    return tr.Hit
end

-- ─────────────────────────────────────────────────────────────
--  RawClearanceCheck
--  Called while CROUCHING.  Checks if the Z slice from crouched
--  top to standing top is clear directly above the NPC.
--  Returns true  → ceiling is blocking → cannot stand yet.
--  Returns false → overhead is clear   → safe to stand.
-- ─────────────────────────────────────────────────────────────
local function RawClearanceCheck(ent)
    local pos = ent:GetPos()
    local tr = util.TraceHull({
        start  = pos,
        endpos = pos,   -- zero-length sweep; just tests the volume
        mins   = HULL_VERT_MIN,
        maxs   = HULL_VERT_MAX,
        filter = ent,
        mask   = MASK_SOLID,
    })

    return tr.Hit   -- true = blocked = cannot stand
end

-- ─────────────────────────────────────────────────────────────
--  Debounced obstacle / clearance check
-- ─────────────────────────────────────────────────────────────
local function TickCeiling(ent)
    local now = CurTime()
    local raw

    if ent._gekkoCrouching then
        -- While crouched: keep crouched if overhead isn't clear
        raw = RawClearanceCheck(ent)
    else
        -- While standing: crouch if a forward obstacle is detected
        raw = RawObstacleCheck(ent)
    end

    ent._gekkoCeilingHit = raw

    if raw then
        ent._gekkoCeilOffSince = nil
        if not ent._gekkoCeilOnSince then
            ent._gekkoCeilOnSince = now
            print("[GeckoCrouch] Hull HIT — debounce started (" ..
                (ent._gekkoCrouching and "clearance" or "lookahead") .. ")")
        elseif now - ent._gekkoCeilOnSince >= CEIL_ON_DEBOUNCE then
            if not ent._gekkoCeilDebounced then
                ent._gekkoCeilDebounced = true
                print(string.format("[GeckoCrouch] Hull CONFIRMED (held %.2fs)", now - ent._gekkoCeilOnSince))
            end
        end
    else
        ent._gekkoCeilOnSince = nil
        if ent._gekkoCeilDebounced then
            if not ent._gekkoCeilOffSince then
                ent._gekkoCeilOffSince = now
                print("[GeckoCrouch] Hull CLEAR — off-debounce started")
            elseif now - ent._gekkoCeilOffSince >= CEIL_OFF_DEBOUNCE then
                ent._gekkoCeilDebounced = false
                ent._gekkoCeilOffSince  = nil
                print("[GeckoCrouch] Hull trigger RELEASED")
            end
        else
            ent._gekkoCeilOffSince = nil
        end
    end

    return ent._gekkoCeilDebounced or false
end

-- ─────────────────────────────────────────────────────────────
--  GeckoCrouch_Init
-- ─────────────────────────────────────────────────────────────
function ENT:GeckoCrouch_Init()
    self._gekkoCrouching          = false
    self._gekkoCrouchExitTime     = 0
    self._gekkoCeilingHit         = false
    self._gekkoCeilDebounced      = false
    self._gekkoCeilOnSince        = nil
    self._gekkoCeilOffSince       = nil
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
--  TickRandom
-- ─────────────────────────────────────────────────────────────
local function TickRandom(ent)
    local now = CurTime()
    if ent._gekkoRandomCrouch then
        if now >= ent._gekkoRandomCrouchEndT then
            ent._gekkoRandomCrouch      = false
            ent._gekkoRandomCrouchEndT  = 0
            ent._gekkoRandomCrouchNextT = now + math.Rand(RAND_CHECK_MIN, RAND_CHECK_MAX)
            print(string.format("[GeckoCrouch] Random EXPIRED — next roll in %.1fs", ent._gekkoRandomCrouchNextT - now))
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
        print(string.format("[GeckoCrouch] Random FAILED — next in %.1fs", ent._gekkoRandomCrouchNextT - now))
    end
end

-- ─────────────────────────────────────────────────────────────
--  GeckoCrouch_Update
--  Returns true  → crouch active, caller must return early
--  Returns false → crouch inactive, caller runs normally
-- ─────────────────────────────────────────────────────────────
function ENT:GeckoCrouch_Update()

    -- ── Jump takes absolute priority ──────────────────────────────
    local jumpState = self:GetGekkoJumpState()
    if jumpState == self.JUMP_RISING  or
       jumpState == self.JUMP_FALLING or
       jumpState == self.JUMP_LAND    or
       (self._gekkoJustJumped and CurTime() < self._gekkoJustJumped) then
        if self._gekkoCrouching then
            self._gekkoCrouching          = false
            self._gekkoCrouchExitTime     = 0
            self._gekkoCrouchSeqSet       = -1
            self._gekkoRandomCrouch       = false
            self._gekkoRandomCrouchEndT   = 0
            self._gekkoRandomCrouchNextT  = CurTime() + math.Rand(RAND_CHECK_MIN, RAND_CHECK_MAX)
            self._gekkoCeilDebounced      = false
            self._gekkoCeilOnSince        = nil
            self._gekkoCeilOffSince       = nil
            self.VJ_CanMoveThink          = true
            self:SetCollisionBounds(
                Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0),
                Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_STAND_H)
            )
            print("[GeckoCrouch] Jump interrupted crouch")
        end
        return false
    end

    if self._gekkoSuppressActivity and CurTime() < self._gekkoSuppressActivity then
        return false
    end

    -- ── Tick sub-systems ──────────────────────────────────────────
    TickRandom(self)
    local ceilHit = TickCeiling(self)

    -- ── Evaluate triggers ─────────────────────────────────────────
    local vjCrouch   = (self.VJ_IsBeingCrouched == true)
    local randActive = self._gekkoRandomCrouch
    local wantCrouch = vjCrouch or ceilHit or randActive

    if not self._crouchDiagT or CurTime() > self._crouchDiagT then
        print(string.format(
            "[GeckoCrouch] Update | crouching=%s  want=%s  vj=%s  hull=%s(raw=%s)  rand=%s  randEndsIn=%.1f",
            tostring(self._gekkoCrouching), tostring(wantCrouch),
            tostring(vjCrouch), tostring(ceilHit), tostring(self._gekkoCeilingHit),
            tostring(randActive),
            self._gekkoRandomCrouch and (self._gekkoRandomCrouchEndT - CurTime()) or 0
        ))
        self._crouchDiagT = CurTime() + 2
    end

    -- ── Exit with lockout ─────────────────────────────────────────
    if not wantCrouch then
        if self._gekkoCrouching then
            if self._gekkoCrouchExitTime == 0 then
                self._gekkoCrouchExitTime = CurTime() + CROUCH_EXIT_LOCKOUT
                print("[GeckoCrouch] All triggers dropped — exit lockout")
            end
            if CurTime() < self._gekkoCrouchExitTime then
                wantCrouch = true
            else
                self._gekkoCrouching      = false
                self._gekkoCrouchExitTime = 0
                self._gekkoCrouchSeqSet   = -1
                self.VJ_CanMoveThink      = true
                self:SetCollisionBounds(
                    Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0),
                    Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_STAND_H)
                )
                print("[GeckoCrouch] → Standing h=" .. HITBOX_STAND_H)
                return false
            end
        else
            return false
        end
    else
        self._gekkoCrouchExitTime = 0
    end

    -- ── Enter crouch ──────────────────────────────────────────────
    if not self._gekkoCrouching then
        self._gekkoCrouching = true
        self:SetCollisionBounds(
            Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0),
            Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_CROUCH_H)
        )
        print("[GeckoCrouch] → Crouching h=" .. HITBOX_CROUCH_H)
    end

    if self.GekkoSeq_CrouchIdle == -1 then return false end

    -- ── Pick cidle or c_walk ──────────────────────────────────────
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
