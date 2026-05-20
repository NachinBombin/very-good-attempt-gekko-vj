-- ============================================================
--  npc_vj_gekko / leg_disable_system.lua
--  Gekko VJ NPC — Leg disabling / grounded state
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
--  Helper: hard-lock all locomotion
--  Called both on trigger and every tick while grounded.
-- ============================================================
local function HardLockMovement(ent)
    ent.MoveSpeed    = 0
    ent.RunSpeed     = 0
    ent.WalkSpeed    = 0
    ent.MaxWalkSpeed = 0
    ent.MaxRunSpeed  = 0

    -- Cancel any residual velocity
    local vel = ent:GetVelocity()
    if vel:LengthSqr() > 1 then
        ent:SetAbsVelocity(Vector(0, 0, 0))
    end

    -- Force idle schedule so VJ Base stops issuing move tasks
    if ent:GetCurrentSchedule() ~= SCHED_IDLE_STAND then
        ent:SetSchedule(SCHED_IDLE_STAND)
    end
    ent:TaskComplete()
    if ent.StopMoving then ent:StopMoving() end
end

-- ============================================================
--  Helper: snap NPC feet to the floor directly below
--  Uses a simple downward traceline from the foot origin.
--  Must be called BEFORE SetMoveType(MOVETYPE_NONE).
-- ============================================================
local function SnapToFloor(ent)
    -- Start just a couple units above the foot so we never start solid
    local footOrigin = ent:GetPos() + Vector(0, 0, 2)

    -- Trace straight down up to 2048 units, only world/brush geometry
    local tr = util.TraceLine({
        start  = footOrigin,
        endpos  = footOrigin - Vector(0, 0, 2048),
        filter = ent,
        mask   = MASK_SOLID_BRUSHONLY,
    })

    if tr.Hit and not tr.StartSolid then
        -- Place feet exactly on the surface
        ent:SetPos(tr.HitPos)
        print(string.format("[GekkoLegs] Snapped to floor at Z=%.1f (dropped %.1f units)",
            tr.HitPos.z, footOrigin.z - tr.HitPos.z))
    else
        -- Fallback: try again with a broader mask in case the first missed a prop floor
        local tr2 = util.TraceLine({
            start  = footOrigin,
            endpos  = footOrigin - Vector(0, 0, 2048),
            filter = ent,
            mask   = MASK_PLAYERSOLID_BRUSHONLY,
        })
        if tr2.Hit and not tr2.StartSolid then
            ent:SetPos(tr2.HitPos)
            print(string.format("[GekkoLegs] Snapped to floor (fallback mask) at Z=%.1f",
                tr2.HitPos.z))
        else
            print("[GekkoLegs] WARNING: floor snap trace missed, NPC may float")
        end
    end
end

-- ============================================================
--  Grounded trigger — one-way transition
-- ============================================================
function ENT:GekkoLegs_TriggerGrounded(dmginfo)
    if self._gekkoLegsDisabled then return end

    self._gekkoLegsDisabled   = true
    self._gekkoLegsTriggeredT = CurTime()

    -- 1. Cancel jump immediately
    if self.SetGekkoJumpState then
        self:SetGekkoJumpState(self.JUMP_NONE or 0)
        self:SetGekkoJumpTimer(0)
    end
    if self.GekkoJump_StopJetFX then self:GekkoJump_StopJetFX() end
    self._jumpStateLOCAL   = 0
    self._jumpCooldown     = CurTime() + 9999
    self._jumpLandCooldown = CurTime() + 9999

    -- 2. Kill sprint / run flags
    self._gekkoRunning = false
    if self._gekkoSprinting then
        -- GekkoSprint_End is a module-local in init.lua;
        -- set the flag directly as a safe fallback
        self._gekkoSprinting    = false
        self._gekkoSprintEndT   = 0
        if self._preSprint_MoveSpeed then
            self.MoveSpeed = self._preSprint_MoveSpeed
            self.RunSpeed  = self._preSprint_RunSpeed
            self.WalkSpeed = self._preSprint_WalkSpeed
            self._preSprint_MoveSpeed = nil
            self._preSprint_RunSpeed  = nil
            self._preSprint_WalkSpeed = nil
        end
    end

    -- 3. Force standing hull, clear crouch
    self:SetCollisionBounds(Vector(-64, -64, 0), Vector(64, 64, 200))
    self:SetNWBool("GekkoIsCrouching", false)
    self._gekkoCrouching    = false
    self.VJ_IsBeingCrouched = false

    -- 4. Snap feet to floor BEFORE freezing move type
    --    (move type must still be MOVETYPE_STEP so SetPos works normally)
    SnapToFloor(self)

    -- 5. NOW freeze locomotion completely
    self:SetMoveType(MOVETYPE_NONE)
    self:SetAbsVelocity(Vector(0, 0, 0))
    HardLockMovement(self)

    -- 6. Apply the disabled leg pose
    self:GekkoLegs_ApplyPose()

    -- 7. Gib burst
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

    print("[GekkoLegs] Entered grounded state")
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

    -- Re-enforce every tick: VJ Base tries to restore speed values
    HardLockMovement(self)

    -- Keep the visual pose
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

-- Backwards compat alias (safe to call but does nothing while grounded)
function ENT:GekkoLegs_GroundToFloor() end
function ENT:GekkoLegs_GroundToFloorOnce() end
