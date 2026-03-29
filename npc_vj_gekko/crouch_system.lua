-- ============================================================
--  crouch_system.lua
--  Gekko VJ NPC — Crouch mechanic
--
--  Sequences:
--    cidle  (seq 3) — crouched idle
--    c_walk (seq 5) — crouched walk
--
--  Triggers (any one is enough to crouch):
--    1. VJ Base native crouch flag (VJ_IsBeingCrouched)  — immediate
--    2. Solid ceiling — debounced: must be present for CEIL_ON_DEBOUNCE
--       seconds before activating, must be absent for CEIL_OFF_DEBOUNCE
--       seconds before releasing (prevents flicker on obstacles)
--    3. Random timed behaviour — fires every few seconds by chance,
--       holds crouch for 3–10 seconds, then releases
--
--  Called from:
--    ENT:Init()                 → self:GeckoCrouch_Init()
--    ENT:GekkoUpdateAnimation() → self:GeckoCrouch_Update()
--    ENT:MaintainActivity()     → already guarded by _gekkoCrouching
--    ENT:VJ_AnimationThink()    → already guarded by _gekkoCrouching
-- ============================================================

-- ───────────────────────────────────────────────────────────
--  Tuning constants
-- ───────────────────────────────────────────────────────────
local CROUCH_CEIL_HEIGHT  = 52    -- units above origin to trace for low ceiling
local CROUCH_EXIT_LOCKOUT = 0.35  -- seconds to hold crouch after ALL triggers drop

-- Ceiling debounce: prevents flicker when geometry changes tick-to-tick
local CEIL_ON_DEBOUNCE    = 0.30  -- ceil must stay TRUE  this long before crouch fires
local CEIL_OFF_DEBOUNCE   = 0.50  -- ceil must stay FALSE this long before trigger clears

-- Hitbox heights
local HITBOX_STAND_H  = 200
local HITBOX_CROUCH_H = 130
local HITBOX_HALF_W   = 64

-- Random crouch behaviour
local RAND_CHECK_MIN  = 4
local RAND_CHECK_MAX  = 12
local RAND_CHANCE     = 0.30
local RAND_DUR_MIN    = 3
local RAND_DUR_MAX    = 10

-- ───────────────────────────────────────────────────────────
--  Raw ceiling trace (returns instant bool)
-- ───────────────────────────────────────────────────────────
local function RawCeilingCheck(ent)
    local pos = ent:GetPos()
    local tr  = util.TraceLine({
        start  = pos + Vector(0, 0, 4),
        endpos = pos + Vector(0, 0, CROUCH_CEIL_HEIGHT),
        filter = ent,
        mask   = MASK_SOLID_BRUSHONLY,
    })
    return tr.Hit
end

-- ───────────────────────────────────────────────────────────
--  Debounced ceiling check
--  Updates _gekkoCeilDebounced (the stable bool used as trigger)
-- ───────────────────────────────────────────────────────────
local function TickCeiling(ent)
    local now = CurTime()
    local raw = RawCeilingCheck(ent)
    ent._gekkoCeilingHit = raw   -- expose raw value for debug line

    if raw then
        -- Raw is high — reset the "off" timer, advance the "on" timer
        ent._gekkoCeilOffSince = nil
        if not ent._gekkoCeilOnSince then
            ent._gekkoCeilOnSince = now
            print("[GeckoCrouch] Ceiling trace HIT — debounce started")
        elseif now - ent._gekkoCeilOnSince >= CEIL_ON_DEBOUNCE then
            if not ent._gekkoCeilDebounced then
                ent._gekkoCeilDebounced = true
                print("[GeckoCrouch] Ceiling trigger CONFIRMED (held " ..  string.format("%.2f", now - ent._gekkoCeilOnSince) .. "s)")
            end
        end
    else
        -- Raw is low — reset the "on" timer, advance the "off" timer
        ent._gekkoCeilOnSince = nil
        if ent._gekkoCeilDebounced then
            if not ent._gekkoCeilOffSince then
                ent._gekkoCeilOffSince = now
                print("[GeckoCrouch] Ceiling trace CLEAR — off-debounce started")
            elseif now - ent._gekkoCeilOffSince >= CEIL_OFF_DEBOUNCE then
                ent._gekkoCeilDebounced = false
                ent._gekkoCeilOffSince  = nil
                print("[GeckoCrouch] Ceiling trigger RELEASED")
            end
        else
            ent._gekkoCeilOffSince = nil
        end
    end

    return ent._gekkoCeilDebounced or false
end

-- ───────────────────────────────────────────────────────────
--  GeckoCrouch_Init
-- ───────────────────────────────────────────────────────────
function ENT:GeckoCrouch_Init()
    self._gekkoCrouching          = false
    self._gekkoCrouchExitTime     = 0
    self._gekkoCeilingHit         = false
    self._gekkoCeilDebounced      = false   -- stable debounced ceiling bool
    self._gekkoCeilOnSince        = nil     -- when raw went high
    self._gekkoCeilOffSince       = nil     -- when raw went low after debounce was active
    self.GekkoSeq_CrouchIdle      = -1
    self.GekkoSeq_CrouchWalk      = -1
    self._gekkoCrouchSeqSet       = -1
    -- Random crouch state
    self._gekkoRandomCrouch       = false
    self._gekkoRandomCrouchEndT   = 0
    self._gekkoRandomCrouchNextT  = CurTime() + math.Rand(RAND_CHECK_MIN, RAND_CHECK_MAX)
    print("[GeckoCrouch] Init() — state vars created")
end

-- ───────────────────────────────────────────────────────────
--  GeckoCrouch_CacheSeqs
-- ───────────────────────────────────────────────────────────
function ENT:GeckoCrouch_CacheSeqs()
    local cidle = self:LookupSequence("cidle")
    local cwalk = self:LookupSequence("c_walk")
    self.GekkoSeq_CrouchIdle = (cidle and cidle ~= -1) and cidle or -1
    self.GekkoSeq_CrouchWalk = (cwalk and cwalk ~= -1) and cwalk or -1
    print(string.format(
        "[GeckoCrouch] CacheSeqs | cidle=%d  c_walk=%d  (expected 3 and 5)",
        self.GekkoSeq_CrouchIdle, self.GekkoSeq_CrouchWalk
    ))
    if self.GekkoSeq_CrouchIdle == -1 then
        print("[GeckoCrouch] WARNING: 'cidle' sequence NOT FOUND")
    end
    if self.GekkoSeq_CrouchWalk == -1 then
        print("[GeckoCrouch] WARNING: 'c_walk' sequence NOT FOUND")
    end
end

-- ───────────────────────────────────────────────────────────
--  TickRandom — manages the random crouch timer
-- ───────────────────────────────────────────────────────────
local function TickRandom(ent)
    local now = CurTime()

    if ent._gekkoRandomCrouch then
        if now >= ent._gekkoRandomCrouchEndT then
            ent._gekkoRandomCrouch      = false
            ent._gekkoRandomCrouchEndT  = 0
            ent._gekkoRandomCrouchNextT = now + math.Rand(RAND_CHECK_MIN, RAND_CHECK_MAX)
            print(string.format(
                "[GeckoCrouch] Random crouch EXPIRED — next roll in %.1fs",
                ent._gekkoRandomCrouchNextT - now
            ))
        end
        return
    end

    if now < ent._gekkoRandomCrouchNextT then return end

    if math.random() < RAND_CHANCE then
        local dur = math.Rand(RAND_DUR_MIN, RAND_DUR_MAX)
        ent._gekkoRandomCrouch     = true
        ent._gekkoRandomCrouchEndT = now + dur
        print(string.format(
            "[GeckoCrouch] Random crouch TRIGGERED — will hold for %.1fs",
            dur
        ))
    else
        ent._gekkoRandomCrouchNextT = now + math.Rand(RAND_CHECK_MIN, RAND_CHECK_MAX)
        print(string.format(
            "[GeckoCrouch] Random crouch roll FAILED — next attempt in %.1fs",
            ent._gekkoRandomCrouchNextT - now
        ))
    end
end

-- ───────────────────────────────────────────────────────────
--  GeckoCrouch_Update
--  Returns true  → crouch active, caller must return early
--  Returns false → crouch inactive, caller runs normally
-- ───────────────────────────────────────────────────────────
function ENT:GeckoCrouch_Update()

    -- ── Jump takes absolute priority ─────────────────────────────
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
            print("[GeckoCrouch] Jump interrupted crouch — forced stand hitbox")
        end
        return false
    end

    -- ── Suppress active ─────────────────────────────────────────
    if self._gekkoSuppressActivity and CurTime() < self._gekkoSuppressActivity then
        return false
    end

    -- ── Tick sub-systems ─────────────────────────────────────────
    TickRandom(self)
    local ceilHit  = TickCeiling(self)   -- debounced

    -- ── Evaluate all triggers ─────────────────────────────────
    local vjCrouch   = (self.VJ_IsBeingCrouched == true)
    local randActive = self._gekkoRandomCrouch
    local wantCrouch = vjCrouch or ceilHit or randActive

    -- Throttled diagnostic
    if not self._crouchDiagT or CurTime() > self._crouchDiagT then
        print(string.format(
            "[GeckoCrouch] Update | crouching=%s  want=%s  vj=%s  ceil=%s(raw=%s)  rand=%s  randEndsIn=%.1f",
            tostring(self._gekkoCrouching),
            tostring(wantCrouch),
            tostring(vjCrouch),
            tostring(ceilHit),
            tostring(self._gekkoCeilingHit),
            tostring(randActive),
            self._gekkoRandomCrouch and (self._gekkoRandomCrouchEndT - CurTime()) or 0
        ))
        self._crouchDiagT = CurTime() + 2
    end

    -- ── Handle exit with lockout ──────────────────────────────
    if not wantCrouch then
        if self._gekkoCrouching then
            if self._gekkoCrouchExitTime == 0 then
                self._gekkoCrouchExitTime = CurTime() + CROUCH_EXIT_LOCKOUT
                print("[GeckoCrouch] All triggers dropped — starting exit lockout")
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
                print("[GeckoCrouch] → Standing | hitbox restored h=" .. HITBOX_STAND_H)
                return false
            end
        else
            return false
        end
    else
        self._gekkoCrouchExitTime = 0
    end

    -- ── Enter crouch ─────────────────────────────────────────
    if not self._gekkoCrouching then
        self._gekkoCrouching = true
        self:SetCollisionBounds(
            Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0),
            Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_CROUCH_H)
        )
        print("[GeckoCrouch] → Crouching | hitbox h=" .. HITBOX_CROUCH_H)
    end

    -- ── Sequences not yet cached ──────────────────────────────
    if self.GekkoSeq_CrouchIdle == -1 then return false end

    -- ── Pick cidle or c_walk ──────────────────────────────────
    local vel    = self:GetVelocity()
    local speed2 = vel.x * vel.x + vel.y * vel.y
    local moving = speed2 > (16 * 16)

    local targetSeq
    if moving and self.GekkoSeq_CrouchWalk ~= -1 then
        targetSeq = self.GekkoSeq_CrouchWalk
    else
        targetSeq = self.GekkoSeq_CrouchIdle
    end

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
        print(string.format(
            "[GeckoCrouch] Sequence set → %s (seq %d)  moving=%s",
            self.Gekko_LastSeqName, targetSeq, tostring(moving)
        ))
    else
        self:SetSequence(targetSeq)
    end

    self:SetPoseParameter("move_x", 0)
    self:SetPoseParameter("move_y", 0)
    self.VJ_IsMoving     = false
    self.VJ_CanMoveThink = false

    return true
end
