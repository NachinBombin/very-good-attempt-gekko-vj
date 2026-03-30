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
--  Animation contract  (matches the original mgs_mech pattern):
--    GeckoCrouch_AnimApply() is called EVERY think tick from
--    OnThink *after* VJBase has had its turn.
--
--    On the FIRST tick after entering crouch (_gekkoCrouchJustEntered
--    == true) we call ResetSequence(c_walk) + SetCycle(0) ONCE,
--    then clear the flag.
--
--    All subsequent ticks we ONLY call SetPlaybackRate — we never
--    call ResetSequence again unless the flag is raised again.
--    This is the same logic as the original vehicle's UpdateAnimation:
--      if sequence ~= currentSeqName then ResetSequence(sequence) end
--      self:SetPlaybackRate(arate)   -- every tick, no SetCycle
--
--  Movement contract:
--    EnterCrouch zeros physics velocity + sets MoveSpeed=0 + calls
--    StopMoving so the NPC actually halts instead of sliding.
--    ExitCrouch restores speeds from Start* cache.
--    NOTE: SetMaxSpeed() is a PLAYER-only method — never call it on NPCs.
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

-- Playback rate while the mech is stationary in crouch.
-- A very small non-zero value keeps the animation alive without
-- visibly cycling when standing still.
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
--
--  IMPORTANT: SetMaxSpeed() is a player-only method.
--  Do NOT call it on an NPC — it will crash.
--  To slow the NPC we zero the physics velocity, cancel the
--  nav path with StopMoving(), and set the VJBase speed vars
--  to 0 so the scheduler won't re-accelerate it.
-- ─────────────────────────────────────────────────────────────
local function EnterCrouch(ent, randDuration)
    local now = CurTime()
    ent._gekkoCrouching          = true
    -- Raise the flag — GeckoCrouch_AnimApply will call
    -- ResetSequence exactly once on the very next tick, then clear it.
    ent._gekkoCrouchJustEntered  = true
    local holdLen = CROUCH_HOLD_MIN
    if randDuration and randDuration > holdLen then
        holdLen = randDuration
    end
    ent._gekkoCrouchHoldUntil = now + holdLen
    ent._gekkoCrouchSeqSet    = -1
    ent._gekkoObsOnSince      = nil
    ent._gekkoObsDebounced    = false
    ent._gekkoObsHullHit      = false

    -- Resize collision hull
    ent:SetCollisionBounds(
        Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0),
        Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_CROUCH_H)
    )
    ent:SetNWBool("GekkoIsCrouching", true)

    -- Zero movement so the mech halts instead of sliding.
    -- NOTE: SetMaxSpeed() is player-only — do NOT call it here.
    ent:SetAbsVelocity(Vector(0, 0, 0))
    ent:StopMoving()
    ent.MoveSpeed = 0
    ent.RunSpeed  = 0
    ent.WalkSpeed = 0

    -- Patch translations so TranslateActivity agrees
    if ent.GekkoSeq_CrouchWalk and ent.GekkoSeq_CrouchWalk ~= -1 then
        PatchTranslationsForCrouch(ent, ent.GekkoSeq_CrouchWalk)
    end

    print(string.format("[GeckoCrouch] → Crouching h=%d  holdLen=%.1fs  holdUntil=%.2f",
        HITBOX_CROUCH_H, holdLen, ent._gekkoCrouchHoldUntil))
end

-- ─────────────────────────────────────────────────────────────
--  ExitCrouch
--
--  NOTE: SetMaxSpeed() is player-only — do NOT call it here.
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

    -- Restore collision hull
    ent:SetCollisionBounds(
        Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0),
        Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_STAND_H)
    )
    ent:SetNWBool("GekkoIsCrouching", false)

    -- Restore movement speeds from cached values.
    -- NOTE: SetMaxSpeed() is player-only — do NOT call it here.
    ent.MoveSpeed = ent.StartWalkSpeed or ent.StartMoveSpeed or 150
    ent.RunSpeed  = ent.StartRunSpeed  or 300
    ent.WalkSpeed = ent.StartWalkSpeed or 150

    RestoreTranslations(ent)
    print("[GeckoCrouch] → Standing h=" .. HITBOX_STAND_H)
end

-- ─────────────────────────────────────────────────────────────
--  GeckoCrouch_AnimApply
--
--  Called every think tick from OnThink, AFTER VJBase has run.
--
--  Pattern mirrors the original mgs_mech vehicle UpdateAnimation():
--    • ResetSequence is called ONCE — only on the first tick after
--      entering crouch (_gekkoCrouchJustEntered == true).
--    • Every subsequent tick we ONLY call SetPlaybackRate.
--    • We never call SetCycle(0) in a loop — that would freeze the
--      animation at frame 0 on every tick.
--
--  The GekkoOwnsAnimation() guards in MaintainIdleAnimation /
--  MaintainActivity / VJ_AnimationThink already prevent VJBase from
--  switching the sequence away from c_walk, so we do NOT need to
--  check GetSequence() != cwalk here and reset again.
-- ─────────────────────────────────────────────────────────────
function ENT:GeckoCrouch_AnimApply()
    local cwalk = self.GekkoSeq_CrouchWalk
    if not cwalk or cwalk == -1 then return end

    -- ── ONE-TIME sequence kick on entry ──────────────────────
    if self._gekkoCrouchJustEntered then
        self:ResetSequence(cwalk)
        self:SetCycle(0)
        self._gekkoCrouchSeqSet      = cwalk
        self.Gekko_LastSeqIdx        = cwalk
        self.Gekko_LastSeqName       = "c_walk"
        self._gekkoCrouchJustEntered = false
        print(string.format("[GeckoCrouch] Seq RESET → c_walk (%d)  (entry kick)", cwalk))
    end

    -- ── Every tick: correct playback rate only ────────────────
    -- Compute rate from actual XY velocity, same as the vehicle does
    -- with its MoveSpeed vector length.
    local vel    = self:GetVelocity()
    local speed2 = vel.x * vel.x + vel.y * vel.y
    local rate

    if speed2 > (16 * 16) then
        local speed  = math.sqrt(speed2)
        local maxSpd = (self.StartMoveSpeed and self.StartMoveSpeed > 0)
            and self.StartMoveSpeed or 150
        rate = math.Clamp(speed / maxSpd, 0.3, 1.5)
    else
        -- Stationary: keep a tiny non-zero rate so the model stays
        -- at its current frame instead of snapping to frame 0.
        rate = CWALK_STATIONARY_RATE
    end

    self:SetPlaybackRate(rate)
    self:SetPoseParameter("move_x", 0)
    self:SetPoseParameter("move_y", 0)
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
