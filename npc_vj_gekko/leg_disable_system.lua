-- ============================================================
--  npc_vj_gekko / leg_disable_system.lua
--  Gekko VJ NPC — Leg disabling / grounded state
-- ============================================================

local GROUNDED_HEALTH_FRACTION = 0.90   -- 90% of max/StartHealth
local GROUNDED_CHANCE          = 0.30   -- 30% chance on crossing threshold

local PELVIS_OFFSET_Z = -125
local L_THIGH_ANG     = Angle(0, 0, -50)          -- Z -50
local R_THIGH_ANG     = Angle(126, -105, 0)       -- X 126, Y -105

-- ============================================================
--  Init
-- ============================================================
function ENT:GekkoLegs_Init()
    self._gekkoLegsDisabled   = false
    self._gekkoLegsTriggeredT = 0
    self.GekkoPelvisBone      = self:LookupBone("b_pelvis")   or -1
    self.GekkoLThighBone      = self:LookupBone("b_l_thigh")  or -1
    self.GekkoRThighBone      = self:LookupBone("b_r_thigh")  or -1
end

-- ============================================================
--  Damage hook — test for threshold crossing and roll chance
-- ============================================================
function ENT:GekkoLegs_OnDamage(dmginfo)
    if self._gekkoLegsDisabled then return end

    local curHP   = self:Health()
    local baseMax = self.StartHealth or self:GetMaxHealth() or curHP
    local thresh  = baseMax * GROUNDED_HEALTH_FRACTION

    -- Only trigger when crossing from above → below threshold
    if curHP <= thresh then return end

    local newHP = math.max(curHP - dmginfo:GetDamage(), 0)
    if newHP > thresh then return end

    if math.Rand(0, 1) > GROUNDED_CHANCE then return end

    self:GekkoLegs_TriggerGrounded(dmginfo)
end

-- ============================================================
--  Grounded trigger — one-way transition
-- ============================================================
function ENT:GekkoLegs_TriggerGrounded(dmginfo)
    if self._gekkoLegsDisabled then return end

    self._gekkoLegsDisabled   = true
    self._gekkoLegsTriggeredT = CurTime()

    -- Hard stop movement and special mobility
    self:SetMoveType(MOVETYPE_STEP)
    self:SetVelocity(Vector(0, 0, 0))
    self:SetSchedule(SCHED_IDLE_STAND)
    self.VJ_IsBeingCrouched  = false

    -- Cancel jump state and jet FX if any
    if self.SetGekkoJumpState then
        self:SetGekkoJumpState(self.JUMP_NONE or 0)
        self:SetGekkoJumpTimer(0)
    end
    if self.GekkoJump_StopJetFX then
        self:GekkoJump_StopJetFX()
    end
    self._jumpStateLOCAL   = 0
    self._jumpCooldown     = CurTime() + 9999
    self._jumpLandCooldown = CurTime() + 9999

    -- Force standing hull and clear crouch flag so it cannot crouch again
    self:SetCollisionBounds(Vector(-64, -64, 0), Vector(64, 64, 200))
    self:SetNWBool("GekkoIsCrouching", false)
    self._gekkoCrouching = false

    -- Apply the "collapsed" pose once immediately
    self:GekkoLegs_ApplyPose()

    -- Drive a large gib burst + explosion using the gib system
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
        -- Fallback: at least try to spawn normal gibs
        self:GekkoGib_OnDamage(self.StartHealth or 900, dmginfo)
    end

    print("[GekkoLegs] Entered grounded state (legs disabled)")
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
-- ============================================================
function ENT:GekkoLegs_Think()
    if not self._gekkoLegsDisabled then return end

    -- Keep pose locked every tick so other systems cannot override it
    self:GekkoLegs_ApplyPose()
end
