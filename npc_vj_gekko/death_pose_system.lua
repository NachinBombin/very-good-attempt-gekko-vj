-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--
--  Fake death: keep the NPC alive but disable all AI/movement,
--  then animate a 2-step fall via ManipulateBone* exactly like
--  leg_disable_system does.
--
--  Step 1 (immediate): one leg kicks out, pelvis starts dropping
--    L_Thigh: Angle(-15, 67, -12)   Pelvis Z: -12
--
--  Step 2 (gravity-timed, ~0.35s later): full frog-fall,
--  pelvis hits ground
--    R_Thigh: Angle(X, -77, -22)    Pelvis Z: -114
--
--  The entity never actually dies — HasDeathCorpse = false,
--  VJ will not spawn a ragdoll.
-- ============================================================

-- Step 1 pose
local STEP1_PELVIS_Z  = -12
local STEP1_L_THIGH   = Angle(-15, 67, -12)

-- Step 2 pose
local STEP2_PELVIS_Z  = -114
local STEP2_R_THIGH   = Angle(0, -77, -22)

-- Time between step 1 and step 2 (seconds)
-- ~0.35s feels like gravity-speed fall from standing
local STEP2_DELAY     = 0.35

local ZERO_VEC = Vector(0, 0, 0)
local ZERO_ANG = Angle(0, 0, 0)

-- ============================================================
--  AI kill — mirrors HardLockMovement from leg_disable_system
-- ============================================================
local function KillAI(ent)
    ent.MoveSpeed    = 0
    ent.RunSpeed     = 0
    ent.WalkSpeed    = 0
    ent.MaxWalkSpeed = 0
    ent.MaxRunSpeed  = 0

    local vel = ent:GetVelocity()
    if vel:LengthSqr() > 1 then ent:SetVelocity(-vel) end

    ent:SetSchedule(SCHED_IDLE_STAND)
    ent:TaskComplete()
    if ent.StopMoving then ent:StopMoving() end

    -- Disable target acquisition
    ent:SetNWBool("GekkoIsDead", true)
end

-- ============================================================
--  Pose helpers
-- ============================================================
local function ApplyStep1(ent)
    -- L thigh kicks out
    if ent._deathLThighBone >= 0 then
        ent:ManipulateBoneAngles(ent._deathLThighBone, STEP1_L_THIGH)
    end
    -- Pelvis starts to drop
    if ent._deathPelvisBone >= 0 then
        ent:ManipulateBonePosition(ent._deathPelvisBone, Vector(0, 0, STEP1_PELVIS_Z))
    end
end

local function ApplyStep2(ent)
    if not IsValid(ent) then return end
    -- R thigh swings out (frog fall)
    if ent._deathRThighBone >= 0 then
        ent:ManipulateBoneAngles(ent._deathRThighBone, STEP2_R_THIGH)
    end
    -- Pelvis fully drops to ground
    if ent._deathPelvisBone >= 0 then
        ent:ManipulateBonePosition(ent._deathPelvisBone, Vector(0, 0, STEP2_PELVIS_Z))
    end
    ent._deathStep = 2
end

-- ============================================================
--  Public API
-- ============================================================

function ENT:GekkoDeath_Init()
    self._deathPoseActive = false
    self._deathStep       = 0

    -- Cache bone indices once
    self._deathPelvisBone = self:LookupBone("b_pelvis")   or -1
    self._deathLThighBone = self:LookupBone("b_l_thigh")  or -1
    self._deathRThighBone = self:LookupBone("b_r_thigh")  or -1

    -- Tell VJ NOT to spawn a ragdoll corpse
    self.HasDeathCorpse = false
end

function ENT:GekkoDeath_Trigger()
    if self._deathPoseActive then return end
    self._deathPoseActive = true
    self._deathStep       = 1

    -- Hard-kill all AI and movement
    KillAI(self)

    -- Cancel jump system
    if self.SetGekkoJumpState then
        self:SetGekkoJumpState(self.JUMP_NONE or 0)
        self:SetGekkoJumpTimer(0)
    end
    if self.GekkoJump_StopJetFX then self:GekkoJump_StopJetFX() end
    self._jumpCooldown     = CurTime() + 9999
    self._jumpLandCooldown = CurTime() + 9999

    -- Step 1 immediately
    ApplyStep1(self)

    -- Step 2 after gravity-coherent delay
    local selfRef = self
    timer.Simple(STEP2_DELAY, function()
        if IsValid(selfRef) then ApplyStep2(selfRef) end
    end)

    print("[GekkoDeath] Fake death triggered — step 1 applied")
end

function ENT:GekkoDeath_Think()
    if not self._deathPoseActive then return end

    -- Re-enforce AI kill every tick (VJ tries to restore speeds)
    KillAI(self)

    -- Re-apply current step's pose every tick so VJ cannot undo it
    if self._deathStep == 1 then
        ApplyStep1(self)
    elseif self._deathStep == 2 then
        ApplyStep2(self)
    end
end
