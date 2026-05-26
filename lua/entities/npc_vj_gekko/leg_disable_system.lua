-- ============================================================
--  npc_vj_gekko / leg_disable_system.lua
-- ============================================================

local GROUNDED_HEALTH_FRACTION = 0.30
local GROUNDED_CHANCE          = 0.30

-- Bone manipulation is a CLIENT-SIDE rendering operation in GMod.
-- Server-side ManipulateBonePosition / ManipulateBoneAngles calls
-- have no visual effect. The grounded pose is handled entirely in
-- cl_init.lua:GekkoApplyGroundedPose, which fires when it reads
-- the GekkoLegsDisabled NW bool == true.
-- This file's job: set that bool and lock movement.

local L_THIGH_ANG = Angle(0, 0, -50)
local R_THIGH_ANG = Angle(100, -80, 0)

-- Hull used while grounded: low flat box so origin stays on the floor surface.
local GROUNDED_HULL_MIN = Vector(-64, -64, 0)
local GROUNDED_HULL_MAX = Vector(64, 64, 72)

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
--  FIX: Use MASK_SOLID as primary (catches displacements + props)
--  before falling back to brush-only masks.
-- ============================================================
local function SnapToFloor(ent)
    local pos = ent:GetPos()

    local tr = util.TraceLine({
        start  = Vector(pos.x, pos.y, pos.z + 500),
        endpos = Vector(pos.x, pos.y, pos.z - 2048),
        filter = ent,
        mask   = MASK_SOLID,
    })

    if not tr.Hit or tr.StartSolid then
        tr = util.TraceLine({
            start  = Vector(pos.x, pos.y, pos.z + 500),
            endpos = Vector(pos.x, pos.y, pos.z - 2048),
            filter = ent,
            mask   = MASK_SOLID_BRUSHONLY,
        })
    end

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

    -- 4. Collapse hull to grounded size and clear crouch state
    self:SetCollisionBounds(GROUNDED_HULL_MIN, GROUNDED_HULL_MAX)
    self:SetNWBool("GekkoIsCrouching", false)
    self._gekkoCrouching    = false
    self.VJ_IsBeingCrouched = false

    -- 5. Zero velocity
    self:SetAbsVelocity(Vector(0, 0, 0))

    -- 6. Hard freeze FIRST — SetPos works on MOVETYPE_NONE
    self:SetMoveType(MOVETYPE_NONE)
    HardLockMovement(self)

    -- 7. Snap to floor
    SnapToFloor(self)

    -- 7b. Deferred re-snap one frame later
    local selfRef = self
    timer.Simple(0, function()
        if IsValid(selfRef) and selfRef._gekkoLegsDisabled then
            SnapToFloor(selfRef)
        end
    end)

    -- 8. Signal the CLIENT to apply the grounded bone pose.
    --    cl_init.lua:Think checks this NW bool and calls
    --    GekkoApplyGroundedPose every frame while it is true.
    --    This is the fix: without this SetNWBool the client
    --    never knew to apply the grounded pose at all.
    self:SetNWBool("GekkoLegsDisabled", true)

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

    print("[GekkoLegs] Grounded state entered — GekkoLegsDisabled NW bool set")
end

-- ============================================================
--  GekkoLegs_ApplyPose (server stub)
--  Bone pose is applied CLIENT-SIDE by GekkoApplyGroundedPose
--  in cl_init.lua. This stub exists only so any legacy call
--  sites don't error.
-- ============================================================
function ENT:GekkoLegs_ApplyPose()
    -- no-op: visual pose is owned by cl_init.lua
end

-- ============================================================
function ENT:GekkoLegs_Think()
    if not self._gekkoLegsDisabled then return end

    self:SetMoveType(MOVETYPE_NONE)
    self:SetAbsVelocity(Vector(0, 0, 0))
    HardLockMovement(self)

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
