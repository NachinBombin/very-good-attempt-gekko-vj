include("shared.lua")

-- ============================================================
--  HELPERS
-- ============================================================
local function SetBone(ent, name, ang)
    local id = ent:LookupBone(name)
    if id and id >= 0 then ent:ManipulateBoneAngles(id, ang, false) end
end

-- ============================================================
--  STOMP LEG DRIVER
-- ============================================================
local function GekkoStompLegs(ent)
    local t      = CurTime()
    local freq   = 14
    local amp    = 55
    local phaseR = t * freq
    local phaseL = t * freq + math.pi

    SetBone(ent, "b_r_thigh",      Angle(math.sin(phaseR)         * amp,        0, 0))
    SetBone(ent, "b_r_upperleg",   Angle(math.sin(phaseR + 0.4)   * amp * 0.7,  0, 0))
    SetBone(ent, "b_r_calf",       Angle(math.sin(phaseR + 0.9)   * amp * 0.5,  0, 0))
    SetBone(ent, "b_r_foot",       Angle(math.sin(phaseR + 1.2)   * -amp * 0.4, 0, 0))
    SetBone(ent, "b_r_toe",        Angle(math.sin(phaseR + 1.5)   * -amp * 0.3, 0, 0))

    SetBone(ent, "b_l_thigh",      Angle(math.sin(phaseL)         * amp,        0, 0))
    SetBone(ent, "b_l_upperleg",   Angle(math.sin(phaseL + 0.4)   * amp * 0.7,  0, 0))
    SetBone(ent, "b_l_calf",       Angle(math.sin(phaseL + 0.9)   * amp * 0.5,  0, 0))
    SetBone(ent, "b_l_foot",       Angle(math.sin(phaseL + 1.2)   * -amp * 0.4, 0, 0))
    SetBone(ent, "b_l_toe",        Angle(math.sin(phaseL + 1.5)   * -amp * 0.3, 0, 0))

    local slam = math.abs(math.sin(t * freq * 0.5)) * 12
    SetBone(ent, "b_pelvis",       Angle(slam, 0, 0))
    SetBone(ent, "b_r_hippiston1", Angle(math.sin(phaseR) * amp * 0.4, 0, 0))
    SetBone(ent, "b_l_hippiston1", Angle(math.sin(phaseL) * amp * 0.4, 0, 0))
end

-- ============================================================
--  FOOTSTEP SYNC
-- ============================================================
local STEP_SOUNDS = {
    "physics/metal/metal_box_impact_hard1.wav",
    "physics/metal/metal_box_impact_hard2.wav",
    "physics/metal/metal_box_impact_hard3.wav",
}

local function GekkoSyncFootsteps(ent)
    local vel = ent:GetNWFloat("GekkoSpeed", 0)
    if vel < 8 then
        ent._stepPhaseR = nil
        ent._stepPhaseL = nil
        return
    end

    local cycleHz = (vel > 160) and 1.1 or 0.71
    local t       = CurTime()
    local cycleT  = t * cycleHz * 2 * math.pi

    local sinR = math.sin(cycleT)
    local sinL = math.sin(cycleT + math.pi)

    local prevR = ent._stepPhaseR or sinR
    local prevL = ent._stepPhaseL or sinL
    ent._stepPhaseR = sinR
    ent._stepPhaseL = sinL

    local pitch = (vel > 160) and math.random(58, 68) or math.random(70, 80)
    local vol   = (vel > 160) and 88 or 80

    if prevR > 0 and sinR <= 0 then
        ent:EmitSound(STEP_SOUNDS[math.random(#STEP_SOUNDS)], vol, pitch)
    end
    if prevL > 0 and sinL <= 0 then
        ent:EmitSound(STEP_SOUNDS[math.random(#STEP_SOUNDS)], vol, pitch)
    end
end

-- ============================================================
--  ARM AIM DRIVER
-- ============================================================
local ARM_YAW_LIMIT   = 75
local ARM_PITCH_LIMIT = 50
local ARM_TURN_SPEED  = 120

local function GekkoAimArms(ent, enemyPos, dt)
    local myPos   = ent:GetPos() + Vector(0, 0, 120)
    local aimDir  = (enemyPos - myPos):GetNormalized()
    local bodyYaw = ent:GetAngles().y
    local aimAng  = aimDir:Angle()

    local clampedYaw   = math.Clamp(math.NormalizeAngle(aimAng.y - bodyYaw), -ARM_YAW_LIMIT,   ARM_YAW_LIMIT)
    local clampedPitch = math.Clamp(-aimAng.p,                                -ARM_PITCH_LIMIT, ARM_PITCH_LIMIT)

    ent._armYaw   = ent._armYaw   or 0
    ent._armPitch = ent._armPitch or 0

    local maxStep = ARM_TURN_SPEED * dt
    ent._armYaw   = ent._armYaw   + math.Clamp(clampedYaw   - ent._armYaw,   -maxStep, maxStep)
    ent._armPitch = ent._armPitch + math.Clamp(clampedPitch - ent._armPitch, -maxStep, maxStep)

    local ay = ent._armYaw
    local ap = ent._armPitch

    SetBone(ent, "b_r_shoulder", Angle(0,        ay * 0.5,  0))
    SetBone(ent, "b_r_upperarm", Angle(ap * 0.6, ay * 0.3,  0))
    SetBone(ent, "b_r_forearm",  Angle(ap * 0.4, 0,         0))
    SetBone(ent, "b_l_shoulder", Angle(0,        -ay * 0.5, 0))
    SetBone(ent, "b_l_upperarm", Angle(ap * 0.6, -ay * 0.3, 0))
    SetBone(ent, "b_l_forearm",  Angle(ap * 0.4, 0,         0))
end

local function GekkoResetArms(ent, dt)
    ent._armYaw   = ent._armYaw   or 0
    ent._armPitch = ent._armPitch or 0
    local maxStep = ARM_TURN_SPEED * dt
    ent._armYaw   = ent._armYaw   + math.Clamp(-ent._armYaw,   -maxStep, maxStep)
    ent._armPitch = ent._armPitch + math.Clamp(-ent._armPitch, -maxStep, maxStep)

    SetBone(ent, "b_r_shoulder", Angle(0,                   ent._armYaw * 0.5,  0))
    SetBone(ent, "b_r_upperarm", Angle(ent._armPitch * 0.6, ent._armYaw * 0.3,  0))
    SetBone(ent, "b_r_forearm",  Angle(ent._armPitch * 0.4, 0,                  0))
    SetBone(ent, "b_l_shoulder", Angle(0,                   -ent._armYaw * 0.5, 0))
    SetBone(ent, "b_l_upperarm", Angle(ent._armPitch * 0.6, -ent._armYaw * 0.3, 0))
    SetBone(ent, "b_l_forearm",  Angle(ent._armPitch * 0.4, 0,                  0))
end

-- ============================================================
--  HEAD DRIVER  (b_spine4)  —  YAW + PITCH
--
--  Confirmed axis mapping from original mech UpdateAimAngle:
--    Angle( -ang.y + bodyYaw,  0,  ang.p )
--    => Angle.p = yaw delta  ( -relYaw )
--    => Angle.r = world pitch ( toEnemy.p )
--
--  Both channels smoothed at HEAD_SPEED deg/sec.
--  Yaw limit: +-50 deg.  Pitch limit: -30 (up) / +20 (down).
-- ============================================================
local HEAD_LIMIT       =  50
local HEAD_PITCH_UP    = -30
local HEAD_PITCH_DOWN  =  20
local HEAD_SPEED       =  80   -- deg/sec, same for both axes

local function GekkoUpdateHead(ent, dt)
    local bone = ent._spineBone
    if not bone or bone < 0 then return end

    ent._headYaw   = ent._headYaw   or 0
    ent._headPitch = ent._headPitch or 0

    local enemy     = ent:GetNWEntity("GekkoEnemy", NULL)
    local targetYaw = 0
    local targetPitch = 0

    if IsValid(enemy) then
        local boneMatrix = ent:GetBoneMatrix(bone)
        local pos        = boneMatrix and boneMatrix:GetTranslation() or (ent:GetPos() + Vector(0, 0, 130))
        local toEnemy    = (enemy:GetPos() + Vector(0, 0, 40) - pos):Angle()
        targetYaw   = math.Clamp(math.NormalizeAngle(toEnemy.y - ent:GetAngles().y), -HEAD_LIMIT,      HEAD_LIMIT)
        targetPitch = math.Clamp(toEnemy.p,                                           HEAD_PITCH_UP,    HEAD_PITCH_DOWN)
    end

    local maxStep    = HEAD_SPEED * dt

    local yawDiff    = math.NormalizeAngle(targetYaw - ent._headYaw)
    ent._headYaw     = math.Clamp(ent._headYaw   + math.Clamp(yawDiff,                  -maxStep, maxStep), -HEAD_LIMIT,     HEAD_LIMIT)

    local pitchDiff  = targetPitch - ent._headPitch
    ent._headPitch   = math.Clamp(ent._headPitch + math.Clamp(pitchDiff,                -maxStep, maxStep),  HEAD_PITCH_UP,   HEAD_PITCH_DOWN)

    -- Angle.p = -yaw,  Angle.r = pitch  (original mech convention)
    ent:ManipulateBoneAngles(bone, Angle(-ent._headYaw, 0, ent._headPitch), false)
end

-- ============================================================
--  DRAW
-- ============================================================
function ENT:Draw()
    self:SetupBones()

    if not self._spineBone then
        self._spineBone = self:LookupBone("b_spine4")
    end

    local t  = CurTime()
    local dt = math.Clamp(t - (self._cl_lastT or t), 0, 0.05)
    self._cl_lastT = t

    local enemy = self:GetNWEntity("GekkoEnemy", NULL)

    GekkoUpdateHead(self, dt)

    if IsValid(enemy) then
        GekkoAimArms(self, enemy:GetPos() + Vector(0, 0, 40), dt)
    else
        GekkoResetArms(self, dt)
    end

    GekkoSyncFootsteps(self)

    local stompEnd = self:GetNWFloat("GekkoStompEnd", 0)
    if t < stompEnd then
        GekkoStompLegs(self)
    end

    self:DrawModel()
end
