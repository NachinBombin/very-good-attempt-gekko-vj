-- ============================================================
--  crouch_system.lua
--  Gekko VJ NPC — Crouch mechanic
--
--  Sequences:
--    cidle  (seq 3) — crouched idle
--    c_walk (seq 5) — crouched walk
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
local CROUCH_EXIT_LOCKOUT = 0.35  -- seconds to hold crouch after trigger drops
                                  -- prevents flickering when barely clearing geometry

-- ───────────────────────────────────────────────────────────
--  Ceiling trace
--  Returns true if there is solid brush geometry within
--  CROUCH_CEIL_HEIGHT units above the NPC's origin.
-- ───────────────────────────────────────────────────────────
local function CeilingCheck(ent)
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
--  GeckoCrouch_Init
--  Call from ENT:Init() after jump init.
-- ───────────────────────────────────────────────────────────
function ENT:GeckoCrouch_Init()
    self._gekkoCrouching      = false
    self._gekkoCrouchExitTime = 0
    -- Sequence indices — populated in the deferred timer.Simple block
    -- alongside GekkoSeq_Walk / Run / Idle
    self.GekkoSeq_CrouchIdle = -1
    self.GekkoSeq_CrouchWalk = -1
    print("[GeckoCrouch] Init()")
end

-- ───────────────────────────────────────────────────────────
--  GeckoCrouch_CacheSeqs
--  Call from inside the timer.Simple(0, ...) deferred block
--  in ENT:Init(), after the walk/run/idle lookups.
-- ───────────────────────────────────────────────────────────
function ENT:GeckoCrouch_CacheSeqs()
    local cidle = self:LookupSequence("cidle")
    local cwalk = self:LookupSequence("c_walk")
    self.GekkoSeq_CrouchIdle = (cidle and cidle ~= -1) and cidle or -1
    self.GekkoSeq_CrouchWalk = (cwalk and cwalk ~= -1) and cwalk or -1
    print(string.format("[GeckoCrouch] Sequences cached | cidle=%d c_walk=%d",
        self.GekkoSeq_CrouchIdle, self.GekkoSeq_CrouchWalk))
end

-- ───────────────────────────────────────────────────────────
--  GeckoCrouch_Update
--  Call at the TOP of ENT:GekkoUpdateAnimation(), before any
--  walk/idle/run logic.
--
--  Returns true  → crouch is active, caller must return early
--  Returns false → crouch is inactive, caller runs normally
-- ───────────────────────────────────────────────────────────
function ENT:GeckoCrouch_Update()

    -- ── Jump system takes absolute priority ──────────────────
    local jumpState = self:GetGekkoJumpState()
    if jumpState == self.JUMP_RISING  or
       jumpState == self.JUMP_FALLING or
       jumpState == self.JUMP_LAND    or
       (self._gekkoJustJumped and CurTime() < self._gekkoJustJumped) then
        -- Silently drop crouch if it was active when we jumped
        if self._gekkoCrouching then
            self._gekkoCrouching      = false
            self._gekkoCrouchExitTime = 0
        end
        return false
    end

    -- ── Suppress active (landing grace etc.) ─────────────────
    if self._gekkoSuppressActivity and CurTime() < self._gekkoSuppressActivity then
        return false
    end

    -- ── Decide if we WANT to crouch ──────────────────────────
    -- Trigger 1: VJ Base set its native crouch flag
    -- Trigger 2: physical ceiling overhead
    local wantCrouch = (self.VJ_IsBeingCrouched == true) or CeilingCheck(self)

    -- ── Handle exit with lockout ──────────────────────────────
    if not wantCrouch then
        if self._gekkoCrouching then
            -- Begin exit countdown if not already started
            if self._gekkoCrouchExitTime == 0 then
                self._gekkoCrouchExitTime = CurTime() + CROUCH_EXIT_LOCKOUT
            end
            if CurTime() < self._gekkoCrouchExitTime then
                -- Still inside lockout — keep crouching
                wantCrouch = true
            else
                -- Lockout expired — stand up
                self._gekkoCrouching      = false
                self._gekkoCrouchExitTime = 0
                print("[GeckoCrouch] → Standing")
                return false
            end
        else
            -- Not crouching and no trigger — nothing to do
            return false
        end
    else
        -- Trigger is active — reset exit timer
        self._gekkoCrouchExitTime = 0
    end

    -- ── Enter crouch if not already in it ────────────────────
    if not self._gekkoCrouching then
        self._gekkoCrouching = true
        print("[GeckoCrouch] → Crouching")
    end

    -- ── Sequences not yet cached (pre-deferred-timer) ────────
    if self.GekkoSeq_CrouchIdle == -1 then
        return false
    end

    -- ── Pick cidle or c_walk based on horizontal speed ───────
    local vel    = self:GetVelocity()
    local speed2 = vel.x * vel.x + vel.y * vel.y
    local moving = speed2 > (16 * 16)  -- ~16 units/s threshold

    local targetSeq
    if moving and self.GekkoSeq_CrouchWalk ~= -1 then
        targetSeq = self.GekkoSeq_CrouchWalk
    else
        targetSeq = self.GekkoSeq_CrouchIdle
    end

    -- Only ResetSequence when it actually changes
    if self:GetSequence() ~= targetSeq then
        self:ResetSequence(targetSeq)
        self:SetCycle(0)

        if moving then
            local speed   = math.sqrt(speed2)
            local maxSpd  = (self.MoveSpeed and self.MoveSpeed > 0) and self.MoveSpeed or 150
            local rate    = math.Clamp(speed / maxSpd, 0.3, 1.5)
            self:SetPlaybackRate(rate)
        else
            self:SetPlaybackRate(1.0)
        end

        -- Keep debug tracking consistent with the rest of init.lua
        self.Gekko_LastSeqIdx  = targetSeq
        self.Gekko_LastSeqName = moving and "c_walk" or "cidle"
    end

    -- Zero out VJ Base pose parameters so legs don't slide
    self:SetPoseParameter("move_x", 0)
    self:SetPoseParameter("move_y", 0)

    -- Prevent VJ Base from reassigning movement this tick
    self.VJ_IsMoving     = false
    self.VJ_CanMoveThink = false

    return true  -- crouch took control — caller should return early
end