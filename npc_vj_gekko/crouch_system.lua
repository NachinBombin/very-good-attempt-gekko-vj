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

-- Hitbox heights
local HITBOX_STAND_H  = 200   -- must match Init() SetCollisionBounds
local HITBOX_CROUCH_H = 130
local HITBOX_HALF_W   = 64

-- ───────────────────────────────────────────────────────────
--  Ceiling trace
-- ───────────────────────────────────────────────────────────
local function CeilingCheck(ent)
    local pos = ent:GetPos()
    local tr  = util.TraceLine({
        start  = pos + Vector(0, 0, 4),
        endpos = pos + Vector(0, 0, CROUCH_CEIL_HEIGHT),
        filter = ent,
        mask   = MASK_SOLID_BRUSHONLY,
    })
    ent._gekkoCeilingHit = tr.Hit  -- expose to debug line in init.lua
    return tr.Hit
end

-- ───────────────────────────────────────────────────────────
--  GeckoCrouch_Init
-- ───────────────────────────────────────────────────────────
function ENT:GeckoCrouch_Init()
    self._gekkoCrouching      = false
    self._gekkoCrouchExitTime = 0
    self._gekkoCeilingHit     = false
    self.GekkoSeq_CrouchIdle  = -1
    self.GekkoSeq_CrouchWalk  = -1
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
        print("[GeckoCrouch] WARNING: 'cidle' sequence NOT FOUND — crouch anim will not play")
    end
    if self.GekkoSeq_CrouchWalk == -1 then
        print("[GeckoCrouch] WARNING: 'c_walk' sequence NOT FOUND — crouch walk anim will not play")
    end
end

-- ───────────────────────────────────────────────────────────
--  GeckoCrouch_Update
--  Returns true  → crouch active, caller must return early
--  Returns false → crouch inactive, caller runs normally
-- ───────────────────────────────────────────────────────────
function ENT:GeckoCrouch_Update()

    -- ── Jump system takes absolute priority ──────────────────
    local jumpState = self:GetGekkoJumpState()
    if jumpState == self.JUMP_RISING  or
       jumpState == self.JUMP_FALLING or
       jumpState == self.JUMP_LAND    or
       (self._gekkoJustJumped and CurTime() < self._gekkoJustJumped) then
        if self._gekkoCrouching then
            self._gekkoCrouching      = false
            self._gekkoCrouchExitTime = 0
            self.VJ_CanMoveThink      = true
            -- Restore standing hitbox when jump interrupts crouch
            self:SetCollisionBounds(
                Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0),
                Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_STAND_H)
            )
            print("[GeckoCrouch] Jump interrupted crouch — forced stand hitbox")
        end
        return false
    end

    -- ── Suppress active (landing grace etc.) ─────────────────
    if self._gekkoSuppressActivity and CurTime() < self._gekkoSuppressActivity then
        return false
    end

    -- ── Evaluate triggers ────────────────────────────────────
    local vjCrouch  = (self.VJ_IsBeingCrouched == true)
    local ceilHit   = CeilingCheck(self)
    local wantCrouch = vjCrouch or ceilHit

    -- Throttled diagnostic so we aren't spammed every tick
    if not self._crouchDiagT or CurTime() > self._crouchDiagT then
        print(string.format(
            "[GeckoCrouch] Update | crouching=%s  wantCrouch=%s  VJ_IsBeingCrouched=%s  ceilHit=%s  cidle=%d  c_walk=%d",
            tostring(self._gekkoCrouching),
            tostring(wantCrouch),
            tostring(vjCrouch),
            tostring(ceilHit),
            self.GekkoSeq_CrouchIdle or -1,
            self.GekkoSeq_CrouchWalk or -1
        ))
        self._crouchDiagT = CurTime() + 2
    end

    -- ── Handle exit with lockout ──────────────────────────────
    if not wantCrouch then
        if self._gekkoCrouching then
            if self._gekkoCrouchExitTime == 0 then
                self._gekkoCrouchExitTime = CurTime() + CROUCH_EXIT_LOCKOUT
                print("[GeckoCrouch] Trigger dropped — starting exit lockout")
            end
            if CurTime() < self._gekkoCrouchExitTime then
                wantCrouch = true  -- still inside lockout
            else
                -- Stand up
                self._gekkoCrouching      = false
                self._gekkoCrouchExitTime = 0
                self.VJ_CanMoveThink      = true
                self:SetCollisionBounds(
                    Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0),
                    Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_STAND_H)
                )
                print("[GeckoCrouch] → Standing | hitbox restored to h=" .. HITBOX_STAND_H)
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
        print("[GeckoCrouch] → Crouching | hitbox set to h=" .. HITBOX_CROUCH_H)
    end

    -- ── Sequences not yet cached ──────────────────────────────
    if self.GekkoSeq_CrouchIdle == -1 then
        print("[GeckoCrouch] Update: sequences not yet cached — skipping anim")
        return false
    end

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

    if self:GetSequence() ~= targetSeq then
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
            "[GeckoCrouch] Sequence changed → %s (seq %d)  moving=%s",
            self.Gekko_LastSeqName, targetSeq, tostring(moving)
        ))
    end

    self:SetPoseParameter("move_x", 0)
    self:SetPoseParameter("move_y", 0)
    self.VJ_IsMoving     = false
    self.VJ_CanMoveThink = false

    return true
end
