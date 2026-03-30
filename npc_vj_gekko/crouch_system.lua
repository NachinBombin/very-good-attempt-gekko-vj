-- ============================================================
--  crouch_system.lua
--  Gekko VJ NPC — Crouch mechanic  (clean rewrite)
--
--  STRATEGY (confirmed against VJBase source):
--
--    The previous approach installed a SetSequence shadow and
--    froze VJ_IsMoving every tick.  The shadow never worked
--    because GMod entity userdata does not support instance-level
--    method shadowing for engine-bound functions, and freezing
--    VJ_IsMoving broke combat AI.
--
--    The correct approach is to redirect VJBase's own systems
--    BEFORE they produce the wrong sequence, not fight them after:
--
--    FIX 1 — TranslateActivity override  (in init.lua)
--      VJBase calls TranslateActivity(act) every time the engine
--      resolves an activity to a sequence number.  While crouching
--      we redirect ACT_WALK / ACT_RUN / ACT_WALK_AIM / ACT_RUN_AIM
--      to c_walk (seq 5) and ACT_IDLE to cidle (seq 3).
--      ACT_DO_NOT_DISTURB (used by PlaySequence / all attack anims)
--      never passes through TranslateActivity — attacks are
--      completely unaffected and work in full crouched pose.
--
--    FIX 2 — MaintainIdleAnimation override  (in init.lua)
--      VJBase registers a global Think hook (funcAnimThink) that
--      calls MaintainIdleAnimation every single engine frame.
--      When crouching and stationary that would re-assert ACT_IDLE
--      → seq "idle".  We override MaintainIdleAnimation so it
--      directly sets the cidle sequence and loops it, and skips
--      the base call entirely.  The ACT_DO_NOT_DISTURB guard
--      ensures attack sequences are never interrupted.
--
--    Hull resize, speed zeroing, and all triggers (VJ native,
--    ceiling, obstacle, random) are preserved from the previous
--    version unchanged.
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
local RAND_CHECK_MAX  = 16
local RAND_CHANCE     = 0.69
local RAND_DUR_MIN    = 3
local RAND_DUR_MAX    = 10

local DEFAULT_MOVE_SPEED = 150
local DEFAULT_RUN_SPEED  = 300
local DEFAULT_WALK_SPEED = 150

local CWALK_STATIONARY_RATE = 0.05

-- ─────────────────────────────────────────────────────────────
--  Hull shapes
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

    -- Stop movement so entry does not look like a running slide.
    ent:SetAbsVelocity(Vector(0, 0, 0))
    ent:StopMoving()
    ent.MoveSpeed = 0
    ent.RunSpeed  = 0
    ent.WalkSpeed = 0

    -- _gekkoCrouching is now true, so TranslateActivity will return
    -- cidle for ACT_IDLE.  Force MaintainIdleAnimation to apply it now.
    ent:MaintainIdleAnimation(true)

    print(string.format("[GeckoCrouch] → Crouching h=%d  holdLen=%.1fs  holdUntil=%.2f",
        HITBOX_CROUCH_H, holdLen, ent._gekkoCrouchHoldUntil))
end

-- ─────────────────────────────────────────────────────────────
--  ExitCrouch
-- ─────────────────────────────────────────────────────────────
local function ExitCrouch(ent)
    local now = CurTime()
    ent._gekkoCrouching           = false
    ent._gekkoCrouchJustEntered   = false
    ent._gekkoCrouchSeqSet        = -1
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

    -- Restore locomotion speeds from constants (VJBase may have
    -- overwritten the Start* caches during the crouch).
    ent.MoveSpeed = DEFAULT_MOVE_SPEED
    ent.RunSpeed  = DEFAULT_RUN_SPEED
    ent.WalkSpeed = DEFAULT_WALK_SPEED

    -- Re-enable VJBase's movement thinkers.
    ent.VJ_CanMoveThink = true

    -- _gekkoCrouching is now false, so TranslateActivity returns
    -- normal activities again.  Force idle system to refresh.
    ent:MaintainIdleAnimation(true)

    print("[GeckoCrouch] → Standing h=" .. HITBOX_STAND_H)
end

-- ─────────────────────────────────────────────────────────────
--  GeckoCrouch_Update
--  Called every tick from GekkoUpdateAnimation().
--  Returns true  → crouch active this tick
--  Returns false → crouch inactive
-- ─────────────────────────────────────────────────────────────
function ENT:GeckoCrouch_Update()
    local now = CurTime()

    -- Never crouch during a jump.
    local jumpState  = self:GetGekkoJumpState()
    local jumpActive = jumpState == self.JUMP_RISING  or
                       jumpState == self.JUMP_FALLING or
                       jumpState == self.JUMP_LAND
    if jumpActive then return false end

    if self._gekkoSuppressActivity and now < self._gekkoSuppressActivity then
        return false
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

    if not self._gekkoCrouching then
        if wantCrouch then
            local randDur = randActive and self._gekkoRandomDuration or nil
            EnterCrouch(self, randDur)
        else
            return false
        end
    else
        -- Extend hold while ceiling is still low.
        if ceilHit then
            self._gekkoCrouchHoldUntil = now + CROUCH_HOLD_MIN
        end

        if now >= self._gekkoCrouchHoldUntil then
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
            -- Another trigger still active; keep crouching.
            self._gekkoCrouchHoldUntil = now + CROUCH_HOLD_MIN
        end
    end

    -- While crouching: manage playback rate.
    -- TranslateActivity handles which sequence plays; we only set speed.
    local vel    = self:GetVelocity()
    local speed2 = vel.x * vel.x + vel.y * vel.y
    local rate

    if speed2 > (16 * 16) then
        rate = math.Clamp(math.sqrt(speed2) / DEFAULT_MOVE_SPEED, 0.3, 1.5)
    else
        rate = CWALK_STATIONARY_RATE
    end

    self:SetPlaybackRate(rate)
    self:SetPoseParameter("move_x", 0)
    self:SetPoseParameter("move_y", 0)
    self.Gekko_LastSeqName = "c_walk"

    return true
end
