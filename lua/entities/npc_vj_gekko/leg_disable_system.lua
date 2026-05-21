-- ============================================================
--  npc_vj_gekko / leg_disable_system.lua
-- ============================================================

local GROUNDED_HEALTH_FRACTION = 0.30
local GROUNDED_CHANCE          = 0.30

local PELVIS_OFFSET_Z = -125
local L_THIGH_ANG     = Angle(0, 0, -50)
local R_THIGH_ANG     = Angle(100, -80, 0)

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
local function HardLockMovement(ent)
    ent.MoveSpeed    = 0
    ent.RunSpeed     = 0
    ent.WalkSpeed    = 0
    ent.MaxWalkSpeed = 0
    ent.MaxRunSpeed  = 0
    ent:SetAbsVelocity(Vector(0, 0, 0))
    if ent:GetCurrentSchedule() ~= SCHED_IDLE_STAND then
        ent:SetSchedule(SCHED_IDLE_STAND)
    end
    ent:TaskComplete()
    if ent.StopMoving then ent:StopMoving() end
end

-- ============================================================
--  SnapToFloor
--  Must be called AFTER SetMoveType(MOVETYPE_NONE).
--  On MOVETYPE_NONE entities SetPos is respected by the engine
--  and moves the origin directly. Traces from 500u above to
--  find the floor, then places the origin on the hit point.
-- ============================================================
local function SnapToFloor(ent)
    local pos = ent:GetPos()

    local tr = util.TraceLine({
        start  = Vector(pos.x, pos.y, pos.z + 500),
        endpos = Vector(pos.x, pos.y, pos.z - 2048),
        filter = ent,
        mask   = MASK_SOLID_BRUSHONLY,
    })

    if not tr.Hit or tr.StartSolid then
        tr = util.TraceLine({
            start  = Vector(pos.x, pos.y, pos.z + 500),
            endpos = Vector(pos.x, pos.y, pos.z - 2048),
            filter = ent,
            mask   = MASK_PLAYERSOLID_BRUSHONLY,
        })
    end

    if tr.Hit and not tr.StartSolid then
        local newPos = Vector(pos.x, pos.y, tr.HitPos.z)
        ent:SetPos(newPos)
        print(string.format(
            "[GekkoLegs] SnapToFloor | was Z=%.1f  snapped to Z=%.1f",
            pos.z, tr.HitPos.z
        ))
    else
        print("[GekkoLegs] WARNING: SnapToFloor trace missed")
    end
end

-- ============================================================
function ENT:GekkoLegs_TriggerGrounded(dmginfo)
    if self._gekkoLegsDisabled then return end
    self._gekkoLegsDisabled   = true
    self._gekkoLegsTriggeredT = CurTime()

    -- 1. Kill jump_system state
    self._jumpStateLOCAL  = 0
    if self.SetGekkoJumpState then self:SetGekkoJumpState(0) end
    if self.SetGekkoJumpTimer  then self:SetGekkoJumpTimer(0) end
    if self.GekkoJump_StopJetFX then self:GekkoJump_StopJetFX() end
    self._jumpCooldown        = CurTime() + 999999
    self._jumpLandCooldown    = CurTime() + 999999
    self._jumpRisingStartTime = 0
    self._jumpDidLiftoff      = false

    -- 2. Kill targeted_jump_system state
    self._tjStateLOCAL   = 0
    self._tjCooldown     = CurTime() + 999999
    self._tjLandCooldown = CurTime() + 999999
    self._tjDidLiftoff   = false

    -- 3. Kill sprint / run
    self._gekkoRunning    = false
    self._gekkoSprinting  = false
    self._gekkoSprintEndT = 0
    if self._preSprint_MoveSpeed then
        self.MoveSpeed = self._preSprint_MoveSpeed
        self.RunSpeed  = self._preSprint_RunSpeed
        self.WalkSpeed = self._preSprint_WalkSpeed
        self._preSprint_MoveSpeed = nil
        self._preSprint_RunSpeed  = nil
        self._preSprint_WalkSpeed = nil
    end

    -- 4. Reset hull / crouch
    self:SetCollisionBounds(Vector(-64, -64, 0), Vector(64, 64, 200))
    self:SetNWBool("GekkoIsCrouching", false)
    self._gekkoCrouching    = false
    self.VJ_IsBeingCrouched = false

    -- 5. Zero velocity
    self:SetAbsVelocity(Vector(0, 0, 0))

    -- 6. Hard freeze FIRST — SetPos works on MOVETYPE_NONE
    self:SetMoveType(MOVETYPE_NONE)
    HardLockMovement(self)

    -- 7. Snap to floor (SetPos respected now that type is NONE)
    SnapToFloor(self)

    -- 8. Apply bone pose
    self:GekkoLegs_ApplyPose()

    -- 9. Gibs
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

    print("[GekkoLegs] Grounded state entered")
end

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
function ENT:GekkoLegs_Think()
    if not self._gekkoLegsDisabled then return end

    self:SetMoveType(MOVETYPE_NONE)
    self:SetAbsVelocity(Vector(0, 0, 0))
    HardLockMovement(self)
    self:GekkoLegs_ApplyPose()

    local now = CurTime()
    if now >= (self._gekkoLegsBleedNextT or 0) then
        self._gekkoLegsBleedNextT = now + math.Rand(0.4, 0.9)
        self._bloodSplatPulse = (self._bloodSplatPulse or 0) + 1
        local variant = math.random(1, 5)
        self:SetNWInt("GekkoBloodSplat", self._bloodSplatPulse * 8 + (variant - 1))
    end
end

function ENT:GekkoLegs_GroundToFloor() end
function ENT:GekkoLegs_GroundToFloorOnce() end
