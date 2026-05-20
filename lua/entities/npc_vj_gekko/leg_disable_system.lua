-- ============================================================
--  npc_vj_gekko / leg_disable_system.lua
--  Gekko VJ NPC — Leg disabling / grounded state
--  FIXES:
--   * Hard snap to floor once on trigger (no repeated floating adjustment)
--   * Stronger movement kill (including MoveType and sprint flags)
--   * Grounding is no longer re-run every tick, only pose + bleed are
-- ============================================================

local GROUNDED_HEALTH_FRACTION = 0.30
local GROUNDED_CHANCE          = 0.30

local PELVIS_OFFSET_Z = -125
local L_THIGH_ANG     = Angle(0, 0, -50)
local R_THIGH_ANG     = Angle(100, -80, 0)

-- ============================================================
--  Init
-- ============================================================
function ENT:GekkoLegs_Init()
    self._gekkoLegsDisabled    = false
    self._gekkoLegsTriggeredT  = 0
    self._gekkoLegsBleedNextT  = 0
    self.GekkoPelvisBone       = self:LookupBone("b_pelvis")   or -1
    self.GekkoLThighBone       = self:LookupBone("b_l_thigh")  or -1
    self.GekkoRThighBone       = self:LookupBone("b_r_thigh")  or -1
end

-- ============================================================
--  Damage hook — test for threshold crossing and roll chance
-- ============================================================
function ENT:GekkoLegs_OnDamage(dmginfo)
    if self._gekkoLegsDisabled then return end

    local curHP   = self:Health()
    local baseMax = self.StartHealth or self:GetMaxHealth() or curHP
    local thresh  = baseMax * GROUNDED_HEALTH_FRACTION

    if curHP <= thresh then return end

    local newHP = math.max(curHP - dmginfo:GetDamage(), 0)
    if newHP > thresh then return end

    if math.Rand(0, 1) > GROUNDED_CHANCE then return end

    self:GekkoLegs_TriggerGrounded(dmginfo)
end

-- ============================================================
--  Helper: hard-lock all locomotion — called on trigger and tick
-- ============================================================
local function HardLockMovement(ent)
    -- Zero VJ Base speed fields so it cannot feed them to the nav system
    ent.MoveSpeed    = 0
    ent.RunSpeed     = 0
    ent.WalkSpeed    = 0
    ent.MaxWalkSpeed = 0
    ent.MaxRunSpeed  = 0

    -- Kill any residual physics velocity
    local vel = ent:GetVelocity()
    if vel:LengthSqr() > 1 then
        ent:SetVelocity(-vel)   -- impulse to cancel, works on MOVETYPE_STEP
    end

    -- Force the NPC to stand still — override whatever schedule VJ restored
    if ent:GetCurrentSchedule() ~= SCHED_IDLE_STAND then
        ent:SetSchedule(SCHED_IDLE_STAND)
    end

    -- Stop navigation
    ent:TaskComplete()
    if ent.StopMoving then ent:StopMoving() end
end

-- ============================================================
--  Helper: snap origin down to floor (one-shot use on trigger)
-- ============================================================
function ENT:GekkoLegs_GroundToFloorOnce()
    local mins, maxs = self:GetCollisionBounds()
    local halfHeight = (maxs.z - mins.z) * 0.5
    local start      = self:GetPos() + Vector(0, 0, halfHeight)

    local tr = util.TraceHull({
        start  = start,
        endpos = start - Vector(0, 0, halfHeight + 256),
        mins   = mins,
        maxs   = maxs,
        mask   = MASK_PLAYERSOLID,
        filter = self,
    })

    if tr.Hit then
        self:SetPos(tr.HitPos + Vector(0, 0, 2))
    end
end

-- Backwards compat: old name now just forwards once
function ENT:GekkoLegs_GroundToFloor()
    return self:GekkoLegs_GroundToFloorOnce()
end

-- ============================================================
--  Grounded trigger — one-way transition
-- ============================================================
function ENT:GekkoLegs_TriggerGrounded(dmginfo)
    if self._gekkoLegsDisabled then return end

    self._gekkoLegsDisabled   = true
    self._gekkoLegsTriggeredT = CurTime()

    -- Hard stop locomotion and AI navigation
    -- Freeze movement type so Gekko cannot be pushed into walking again
    self:SetMoveType(MOVETYPE_NONE)
    HardLockMovement(self)
    self.VJ_IsBeingCrouched = false

    -- Cancel jump
    if self.SetGekkoJumpState then
        self:SetGekkoJumpState(self.JUMP_NONE or 0)
        self:SetGekkoJumpTimer(0)
    end
    if self.GekkoJump_StopJetFX then self:GekkoJump_StopJetFX() end
    self._jumpStateLOCAL   = 0
    self._jumpCooldown     = CurTime() + 9999
    self._jumpLandCooldown = CurTime() + 9999

    -- Turn off run / sprint flags so animation update does not try to run
    self._gekkoRunning = false
    if self._gekkoSprinting then
        if GekkoSprint_End then
            GekkoSprint_End(self)
        else
            self._gekkoSprinting = false
        end
    end

    -- Force standing hull, no crouch
    self:SetCollisionBounds(Vector(-64, -64, 0), Vector(64, 64, 200))
    self:SetNWBool("GekkoIsCrouching", false)
    self._gekkoCrouching = false

    -- One-shot hard snap to the floor directly below current position
    self:GekkoLegs_GroundToFloorOnce()

    -- Apply static disabled pose
    self:GekkoLegs_ApplyPose()

    -- Gib burst
    local hitPos = dmginfo:GetDamagePosition()
    if (not hitPos) or hitPos == vector_origin then
        hitPos = self:GetPos() + Vector(0, 0, 80)
    end
    local attacker  = dmginfo:GetAttacker()
    local hitNormal = Vector(0, 0, 1)
    if IsValid(attacker) then
        hitNormal = (self:GetPos() - attacker:GetPos()):GetNormalized()
        hitNormal.z = math.Clamp(hitNormal.z, -0.3, 0.3)
        hitNormal:Normalize()
    end
    if self.GekkoGib_BigBurst then
        self:GekkoGib_BigBurst(hitPos, hitNormal)
    else
        self:GekkoGib_OnDamage(self.StartHealth or 900, dmginfo)
    end

    print("[GekkoLegs] Entered grounded state (legs disabled, movement hard-locked)")
end

-- ============================================================
--  Pose application
-- ============================================================
function ENT:GekkoLegs_ApplyPose()
    if not self._gekkoLegsDisabled then return end
    if self.GekkoPelvisBone and self.GekkoPelvisBone >= 0 then
        self:ManipulateBonePosition(self.GekkoPelvisBone, Vector(0, 0, PELVIS_OFFSET_Z))
    end
    if self.GekkoLThighBone and self.GekkoLThighBone >= 0 then
        self:ManipulateBoneAngles(self.GekkoLThighBone, L_THIGH_ANG)
    end
    if self.GekkoRThighBone and self.GekkoRThighBone >= 0 then
        self:ManipulateBoneAngles(self.GekkoRThighBone, R_THIGH_ANG)
    end
end

-- ============================================================
--  Per-tick update while grounded
--  NOTE: We no longer re-ground every tick; that was causing
--        the floating / slow settle behaviour. Ground snap is
--        done once on trigger; here we just re-assert speeds
--        and keep the visual pose + bleeding.
-- ============================================================
function ENT:GekkoLegs_Think()
    if not self._gekkoLegsDisabled then return end

    -- Re-enforce movement lock every tick (VJ Base tries to restore speeds)
    HardLockMovement(self)

    -- Keep disabled pose (visual only; no SetPos here)
    self:GekkoLegs_ApplyPose()

    -- Passive bleeding
    local now = CurTime()
    if now >= (self._gekkoLegsBleedNextT or 0) then
        self._gekkoLegsBleedNextT = now + math.Rand(0.4, 0.9)
        self._bloodSplatPulse = (self._bloodSplatPulse or 0) + 1
        local variant = math.random(1, 5)
        self:SetNWInt("GekkoBloodSplat", self._bloodSplatPulse * 8 + (variant - 1))
    end
end
