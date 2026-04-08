-- ============================================================
--  npc_vj_gekko / leg_disable_system.lua
--  Gekko VJ NPC — Leg disabling / grounded state
-- ============================================================

local GROUNDED_HEALTH_FRACTION = 0.90
local GROUNDED_CHANCE          = 0.30

local PELVIS_OFFSET_Z = -125
local L_THIGH_ANG     = Angle(0, 0, -50)
local R_THIGH_ANG     = Angle(126, -105, 0)

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
--  Helper: force zero locomotion speeds
-- ============================================================
local function ZeroSpeeds(ent)
    ent.MoveSpeed  = 0
    ent.RunSpeed   = 0
    ent.WalkSpeed  = 0
    ent:SetVelocity(Vector(0, 0, 0))
end

-- ============================================================
--  Helper: snap origin down to floor
-- ============================================================
function ENT:GekkoLegs_GroundToFloor()
    local mins, maxs = self:GetCollisionBounds()
    local halfHeight = (maxs.z - mins.z) * 0.5
    local start      = self:GetPos() + Vector(0, 0, halfHeight)

    local tr = util.TraceHull({
        start  = start,
        endpos  = start - Vector(0, 0, halfHeight + 256),
        mins   = mins,
        maxs   = maxs,
        mask   = MASK_PLAYERSOLID,
        filter = self,
    })

    if tr.Hit then
        self:SetPos(tr.HitPos + Vector(0, 0, 2))
    end
end

-- ============================================================
--  Grounded trigger — one-way transition
-- ============================================================
function ENT:GekkoLegs_TriggerGrounded(dmginfo)
    if self._gekkoLegsDisabled then return end

    self._gekkoLegsDisabled   = true
    self._gekkoLegsTriggeredT = CurTime()

    -- Hard stop
    self:SetMoveType(MOVETYPE_STEP)
    ZeroSpeeds(self)
    self:SetSchedule(SCHED_IDLE_STAND)
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

    -- Force standing hull, no crouch
    self:SetCollisionBounds(Vector(-64, -64, 0), Vector(64, 64, 200))
    self:SetNWBool("GekkoIsCrouching", false)
    self._gekkoCrouching = false

    self:GekkoLegs_GroundToFloor()
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

    print("[GekkoLegs] Entered grounded state (legs disabled, speed zeroed)")
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

    -- Enforce zero speed every tick (VJ Base may try to restore it)
    ZeroSpeeds(self)

    self:GekkoLegs_GroundToFloor()
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
