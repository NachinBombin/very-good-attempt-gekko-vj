-- ============================================================
--  crouch_system.lua  (DEBUG BUILD)
--  Visual trace beams are drawn every tick while this is loaded.
--  Green line = miss, Red line = hit.
--  Remove debugoverlay calls once ceiling detection is confirmed working.
-- ============================================================

local CROUCH_EXIT_LOCKOUT = 0.35

-- Overhead trace parameters — tune these until raw=true fires
local CEIL_UP_Z_START   = 40    -- start of upward trace above origin
local CEIL_UP_Z_END     = 150   -- end of upward trace (increase if obstacle is high)
local CEIL_FWD_DIST     = 120   -- how far forward the forward probe looks
local CEIL_FWD_Z_LOW    = 40    -- forward probe low Z (sweep covers low obstacles)
local CEIL_FWD_Z_HIGH   = 150   -- forward probe high Z

-- Ceiling debounce
local CEIL_ON_DEBOUNCE  = 0.20
local CEIL_OFF_DEBOUNCE = 0.40

local HITBOX_STAND_H  = 200
local HITBOX_CROUCH_H = 130
local HITBOX_HALF_W   = 64

local RAND_CHECK_MIN  = 4
local RAND_CHECK_MAX  = 12
local RAND_CHANCE     = 0.30
local RAND_DUR_MIN    = 3
local RAND_DUR_MAX    = 10

-- ───────────────────────────────────────────────────────────
--  Raw overhead check — 3 traces with visual debug
-- ───────────────────────────────────────────────────────────
local function RawCeilingCheck(ent)
    local pos = ent:GetPos()
    local fwd = ent:GetForward()
    fwd.z = 0
    fwd:Normalize()

    -- Trace A: straight up from mid-torso
    local upStart = pos + Vector(0, 0, CEIL_UP_Z_START)
    local upEnd   = pos + Vector(0, 0, CEIL_UP_Z_END)
    local trUp    = util.TraceLine({
        start  = upStart,
        endpos = upEnd,
        filter = ent,
        mask   = MASK_SOLID,
    })
    debugoverlay.Line(upStart, trUp.HitPos, 0.05,
        trUp.Hit and Color(255,0,0) or Color(0,255,0), true)

    if trUp.Hit then return true, "up" end

    -- Trace B: forward probe at low head height
    local fwdStartLow = pos + Vector(0, 0, CEIL_FWD_Z_LOW)
    local fwdEndLow   = fwdStartLow + fwd * CEIL_FWD_DIST
    local trFwdLow    = util.TraceLine({
        start  = fwdStartLow,
        endpos = fwdEndLow,
        filter = ent,
        mask   = MASK_SOLID,
    })
    debugoverlay.Line(fwdStartLow, trFwdLow.HitPos, 0.05,
        trFwdLow.Hit and Color(255,128,0) or Color(0,200,255), true)

    if trFwdLow.Hit then return true, "fwd_low" end

    -- Trace C: forward probe at upper head height
    local fwdStartHigh = pos + Vector(0, 0, CEIL_FWD_Z_HIGH)
    local fwdEndHigh   = fwdStartHigh + fwd * CEIL_FWD_DIST
    local trFwdHigh    = util.TraceLine({
        start  = fwdStartHigh,
        endpos = fwdEndHigh,
        filter = ent,
        mask   = MASK_SOLID,
    })
    debugoverlay.Line(fwdStartHigh, trFwdHigh.HitPos, 0.05,
        trFwdHigh.Hit and Color(255,0,255) or Color(200,200,0), true)

    if trFwdHigh.Hit then return true, "fwd_high" end

    return false, "none"
end

-- ───────────────────────────────────────────────────────────
--  Debounced ceiling check
-- ───────────────────────────────────────────────────────────
local function TickCeiling(ent)
    local now = CurTime()
    local raw, src = RawCeilingCheck(ent)
    ent._gekkoCeilingHit = raw

    -- Log exact trace geometry occasionally so we can verify Z heights
    if not ent._ceilPosLogT or now > ent._ceilPosLogT then
        local pos = ent:GetPos()
        print(string.format(
            "[GeckoCrouch] TracePos | origin=%.0f,%.0f,%.0f  upZ=%.0f..%.0f  fwdZ=%.0f..%.0f  raw=%s(%s)",
            pos.x, pos.y, pos.z,
            pos.z + CEIL_UP_Z_START, pos.z + CEIL_UP_Z_END,
            pos.z + CEIL_FWD_Z_LOW,  pos.z + CEIL_FWD_Z_HIGH,
            tostring(raw), src
        ))
        ent._ceilPosLogT = now + 3
    end

    if raw then
        ent._gekkoCeilOffSince = nil
        if not ent._gekkoCeilOnSince then
            ent._gekkoCeilOnSince = now
            print("[GeckoCrouch] Ceiling HIT (" .. src .. ") — debounce started")
        elseif now - ent._gekkoCeilOnSince >= CEIL_ON_DEBOUNCE then
            if not ent._gekkoCeilDebounced then
                ent._gekkoCeilDebounced = true
                print(string.format("[GeckoCrouch] Ceiling CONFIRMED via '%s' (held %.2fs)", src, now - ent._gekkoCeilOnSince))
            end
        end
    else
        ent._gekkoCeilOnSince = nil
        if ent._gekkoCeilDebounced then
            if not ent._gekkoCeilOffSince then
                ent._gekkoCeilOffSince = now
                print("[GeckoCrouch] Ceiling CLEAR — off-debounce started")
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

-- ───────────────────────────────────────────────────────────
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

-- ───────────────────────────────────────────────────────────
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

-- ───────────────────────────────────────────────────────────
function ENT:GeckoCrouch_Update()

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

    TickRandom(self)
    local ceilHit = TickCeiling(self)

    local vjCrouch   = (self.VJ_IsBeingCrouched == true)
    local randActive = self._gekkoRandomCrouch
    local wantCrouch = vjCrouch or ceilHit or randActive

    if not self._crouchDiagT or CurTime() > self._crouchDiagT then
        print(string.format(
            "[GeckoCrouch] Update | crouching=%s  want=%s  vj=%s  ceil=%s(raw=%s)  rand=%s  randEndsIn=%.1f",
            tostring(self._gekkoCrouching), tostring(wantCrouch),
            tostring(vjCrouch), tostring(ceilHit), tostring(self._gekkoCeilingHit),
            tostring(randActive),
            self._gekkoRandomCrouch and (self._gekkoRandomCrouchEndT - CurTime()) or 0
        ))
        self._crouchDiagT = CurTime() + 2
    end

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

    if not self._gekkoCrouching then
        self._gekkoCrouching = true
        self:SetCollisionBounds(
            Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0),
            Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_CROUCH_H)
        )
        print("[GeckoCrouch] → Crouching h=" .. HITBOX_CROUCH_H)
    end

    if self.GekkoSeq_CrouchIdle == -1 then return false end

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
