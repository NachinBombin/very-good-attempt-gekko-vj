-- ============================================================
--  crouch_system.lua
--  Gekko VJ NPC — Crouch mechanic
--
--  THE PROBLEM (confirmed by log):
--    "Seq RECLAIMED" fires every single tick — something steals
--    the sequence back on every engine frame.  The culprit is
--    VJBase's global Think hook (registered via hook.Add in
--    VJ_SNPC_Base:Initialize).  That hook calls its own anim
--    function directly on the entity outside of OnThink, so our
--    MaintainActivity / MaintainIdleAnimation overrides are only
--    reached when VJBase chooses to call them — the global hook
--    bypasses them entirely.
--
--  COMPLETE FIX — three layers:
--
--    LAYER 1 — SetSequence override (lowest level, bulletproof)
--      We shadow self.SetSequence on the live entity instance.
--      Any call that tries to set a sequence other than c_walk
--      while crouching is silently dropped.  Only our own code
--      (GeckoCrouch_AnimApply) passes the _gekkoSeqAllowed flag
--      to bypass the guard.
--
--    LAYER 2 — VJ movement/schedule suppression
--      VJBase's thinker also drives NPC scheduling and movement
--      which can interrupt combat AI (causing the "stops fighting"
--      behaviour and the spins).  We freeze VJ_IsMoving,
--      VJ_CanMoveThink, and VJ_ScheduleEnded each think tick
--      while crouching so VJBase thinks the NPC is stationary
--      and doesn't reassign schedules or spin it to face new
--      directions mid-crouch.
--
--    LAYER 3 — hard constant speed restore on ExitCrouch
--      Rather than relying on Start* caches (which VJBase can
--      overwrite during a crouch), we restore from the module-
--      level speed constants that were valid at spawn.
--
--  Triggers (any one is enough to crouch):
--    1. VJ Base native crouch flag (VJ_IsBeingCrouched)   — immediate
--    2. Standing-hull lookahead (TraceHull forward)        — debounced
--    3. Ceiling trace (TraceLine upward from head)         — immediate
--    4. Random timed behaviour                             — timer-based
--
--  Animation contract:
--    GeckoCrouch_AnimApply() is called EVERY think tick from
--    OnThink *after* VJBase has had its turn.
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

local RAND_CHECK_MIN    = 6
local RAND_CHECK_MAX    = 16
local RAND_CHANCE       = 0.69
local RAND_DUR_MIN      = 3
local RAND_DUR_MAX      = 10

-- Default locomotion speeds — used for hard restore on ExitCrouch.
-- These must match the shared.lua / VJ ENT defaults for this NPC.
local DEFAULT_MOVE_SPEED = 150
local DEFAULT_RUN_SPEED  = 300
local DEFAULT_WALK_SPEED = 150

-- Playback rate while the mech is stationary in crouch.
local CWALK_STATIONARY_RATE = 0.05

-- ─────────────────────────────────────────────────────────────
--  Hull shapes
-- ─────────────────────────────────────────────────────────────
local HULL_FWD_MIN = Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 12)
local HULL_FWD_MAX = Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_CROUCH_H)

-- ─────────────────────────────────────────────────────────────
--  Activity list patched in AnimationTranslations while crouching
-- ─────────────────────────────────────────────────────────────
local CROUCH_OVERRIDE_ACTS = {
    ACT_IDLE,
    ACT_WALK,
    ACT_RUN,
    ACT_WALK_AIM,
    ACT_RUN_AIM,
    ACT_RANGE_ATTACK1,
    ACT_RANGE_ATTACK2,
    ACT_GESTURE_RANGE_ATTACK1,
    ACT_GESTURE_RANGE_ATTACK2,
    ACT_IDLE_ANGRY,
    ACT_COMBAT_IDLE,
}

-- ─────────────────────────────────────────────────────────────
--  LAYER 1 — SetSequence override
--
--  We store the engine's real SetSequence as a module-local and
--  install a shadow function on the entity *instance* (not the
--  class) in EnterCrouch.  The shadow blocks any sequence change
--  that isn't ours.  We remove the shadow in ExitCrouch.
--
--  _gekkoSeqAllowed is a one-shot flag: set it to true immediately
--  before our authoritative call, then it clears itself.
-- ─────────────────────────────────────────────────────────────
local _realSetSequence = nil   -- cached on first use

local function InstallSetSequenceGuard(ent)
    -- Cache the real engine method once.
    if not _realSetSequence then
        _realSetSequence = ent.SetSequence
    end

    -- Shadow on the instance table (overrides the class method).
    ent.SetSequence = function(self, seq)
        if self._gekkoCrouching then
            if self._gekkoSeqAllowed then
                self._gekkoSeqAllowed = false  -- consume the pass
                _realSetSequence(self, seq)
            end
            -- Silent drop — VJBase, engine activities, etc. are blocked.
            return
        end
        -- Not crouching — pass through normally.
        _realSetSequence(self, seq)
    end

    ent._gekkoSetSeqGuardInstalled = true
end

local function RemoveSetSequenceGuard(ent)
    if not ent._gekkoSetSeqGuardInstalled then return end
    -- Restore the class method by nilling the instance key.
    ent.SetSequence = nil
    ent._gekkoSetSeqGuardInstalled = false
end

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
--  CeilingCheck
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
    self._gekkoCrouchSeqSet        = -1
    self._gekkoRandomCrouch        = false
    self._gekkoRandomCrouchEndT    = 0
    self._gekkoRandomDuration      = 0
    self._gekkoRandomCrouchNextT   = CurTime() + math.Rand(RAND_CHECK_MIN, RAND_CHECK_MAX)
    self._gekkoSeqAllowed          = false
    self._gekkoSetSeqGuardInstalled = false
    print("[GeckoCrouch] Init() — state vars created")
end

-- ─────────────────────────────────────────────────────────────
--  GeckoCrouch_CacheSeqs
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
--  PatchTranslationsForCrouch
-- ─────────────────────────────────────────────────────────────
local function PatchTranslationsForCrouch(ent, cwalk)
    if not ent.AnimationTranslations then
        ent.AnimationTranslations = {}
    end
    if not ent._gekkoOrigTranslations then
        ent._gekkoOrigTranslations = {}
        for _, act in ipairs(CROUCH_OVERRIDE_ACTS) do
            ent._gekkoOrigTranslations[act] = ent.AnimationTranslations[act]
        end
    end
    for _, act in ipairs(CROUCH_OVERRIDE_ACTS) do
        ent.AnimationTranslations[act] = cwalk
    end
end

-- ─────────────────────────────────────────────────────────────
--  RestoreTranslations
-- ─────────────────────────────────────────────────────────────
local function RestoreTranslations(ent)
    if not ent._gekkoOrigTranslations then return end
    if not ent.AnimationTranslations then
        ent.AnimationTranslations = {}
    end
    for _, act in ipairs(CROUCH_OVERRIDE_ACTS) do
        ent.AnimationTranslations[act] = ent._gekkoOrigTranslations[act]
    end
    ent._gekkoOrigTranslations = nil
end

-- ─────────────────────────────────────────────────────────────
--  EnterCrouch
-- ─────────────────────────────────────────────────────────────
local function EnterCrouch(ent, randDuration)
    local now = CurTime()
    ent._gekkoCrouching          = true
    ent._gekkoCrouchJustEntered  = true   -- AnimApply will SetCycle(0) once
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

    ent:SetAbsVelocity(Vector(0, 0, 0))
    ent:StopMoving()
    ent.MoveSpeed = 0
    ent.RunSpeed  = 0
    ent.WalkSpeed = 0

    -- LAYER 2: Freeze VJBase movement thinkers so it stops trying to
    -- assign schedules and spin the NPC while crouching.
    ent.VJ_IsMoving      = false
    ent.VJ_CanMoveThink  = false

    if ent.GekkoSeq_CrouchWalk and ent.GekkoSeq_CrouchWalk ~= -1 then
        PatchTranslationsForCrouch(ent, ent.GekkoSeq_CrouchWalk)
    end

    -- LAYER 1: Install the SetSequence guard AFTER patching translations
    -- so the very first ResetSequence call from AnimApply goes through.
    InstallSetSequenceGuard(ent)

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

    -- LAYER 1: Remove the SetSequence guard first so the reset below
    -- goes through the real engine function.
    RemoveSetSequenceGuard(ent)

    ent:SetCollisionBounds(
        Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0),
        Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_STAND_H)
    )
    ent:SetNWBool("GekkoIsCrouching", false)

    -- LAYER 3: Hard restore from constants, not from Start* caches
    -- (VJBase may have clobbered them during the crouch).
    ent.MoveSpeed = DEFAULT_MOVE_SPEED
    ent.RunSpeed  = DEFAULT_RUN_SPEED
    ent.WalkSpeed = DEFAULT_WALK_SPEED

    -- LAYER 2: Re-enable VJBase movement thinkers.
    ent.VJ_CanMoveThink = true

    RestoreTranslations(ent)
    print("[GeckoCrouch] → Standing h=" .. HITBOX_STAND_H)
end

-- ─────────────────────────────────────────────────────────────
--  GeckoCrouch_AnimApply
--
--  Called every think tick from OnThink, AFTER VJBase has run.
--
--  With the SetSequence guard installed, "stolen recovery" lines
--  should vanish entirely — no other code can change the sequence
--  while crouching.  This function only needs to:
--    1. On fresh entry: issue ResetSequence(c_walk) + SetCycle(0).
--    2. Every tick: keep playback rate correct.
--
--  We still keep the GetSequence() != cwalk safety check as a
--  belt-and-suspenders fallback (e.g. sequence reset by engine
--  console commands, map transitions, etc.).
-- ─────────────────────────────────────────────────────────────
function ENT:GeckoCrouch_AnimApply()
    local cwalk = self.GekkoSeq_CrouchWalk
    if not cwalk or cwalk == -1 then return end

    -- ── Reassert sequence if needed ──────────────────────────
    if self:GetSequence() ~= cwalk then
        -- Authorised write — set the pass flag before calling.
        self._gekkoSeqAllowed = true
        self:ResetSequence(cwalk)
        -- Guard may not have been installed yet on the very first tick;
        -- ensure the flag is always cleared.
        self._gekkoSeqAllowed = false

        if self._gekkoCrouchJustEntered then
            self:SetCycle(0)
            self._gekkoCrouchJustEntered = false
            print(string.format("[GeckoCrouch] Seq RESET → c_walk (%d)  (entry kick)", cwalk))
        else
            print(string.format("[GeckoCrouch] Seq RECLAIMED → c_walk (%d)  (stolen recovery)", cwalk))
        end

        self._gekkoCrouchSeqSet   = cwalk
        self.Gekko_LastSeqIdx     = cwalk
        self.Gekko_LastSeqName    = "c_walk"
    else
        if self._gekkoCrouchJustEntered then
            self._gekkoCrouchJustEntered = false
        end
    end

    -- ── LAYER 2 tick: keep VJBase movement thinkers frozen ───
    -- VJBase resets these flags internally on each of its own ticks,
    -- so we must re-freeze them every think tick while crouching.
    self.VJ_IsMoving     = false
    self.VJ_CanMoveThink = false

    -- ── Every tick: update playback rate ─────────────────────
    local vel    = self:GetVelocity()
    local speed2 = vel.x * vel.x + vel.y * vel.y
    local rate

    if speed2 > (16 * 16) then
        local speed  = math.sqrt(speed2)
        rate = math.Clamp(speed / DEFAULT_MOVE_SPEED, 0.3, 1.5)
    else
        rate = CWALK_STATIONARY_RATE
    end

    self:SetPlaybackRate(rate)
    self:SetPoseParameter("move_x", 0)
    self:SetPoseParameter("move_y", 0)

    self.Gekko_LastSeqName = "c_walk"
end

-- ─────────────────────────────────────────────────────────────
--  GeckoCrouch_Update
--  Returns true  → crouch active
--  Returns false → crouch inactive
-- ─────────────────────────────────────────────────────────────
function ENT:GeckoCrouch_Update()
    local now = CurTime()

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
            self._gekkoCrouchHoldUntil = now + CROUCH_HOLD_MIN
        end
    end

    return true
end
