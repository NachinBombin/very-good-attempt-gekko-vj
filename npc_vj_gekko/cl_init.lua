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

    local relYaw   = math.NormalizeAngle(aimDir:Angle().y - bodyYaw)
    local delta    = enemyPos - myPos
    local len      = delta:Length()
    local relPitch = len > 1 and -math.deg(math.asin(math.Clamp(delta.z / len, -1, 1))) or 0

    local clampedYaw   = math.Clamp(relYaw,   -ARM_YAW_LIMIT,   ARM_YAW_LIMIT)
    local clampedPitch = math.Clamp(relPitch, -ARM_PITCH_LIMIT, ARM_PITCH_LIMIT)

    ent._armYaw   = ent._armYaw   or 0
    ent._armPitch = ent._armPitch or 0

    local maxStep = ARM_TURN_SPEED * dt
    ent._armYaw   = ent._armYaw   + math.Clamp(clampedYaw   - ent._armYaw,   -maxStep, maxStep)
    ent._armPitch = ent._armPitch + math.Clamp(clampedPitch - ent._armPitch, -maxStep, maxStep)

    local ay = ent._armYaw
    local ap = ent._armPitch

    SetBone(ent, "b_r_shoulder",  Angle(0,  ay * 0.5, 0))
    SetBone(ent, "b_r_upperarm",  Angle(ap * 0.6, ay * 0.3, 0))
    SetBone(ent, "b_r_forearm",   Angle(ap * 0.4, 0, 0))

    SetBone(ent, "b_l_shoulder",  Angle(0,  -ay * 0.5, 0))
    SetBone(ent, "b_l_upperarm",  Angle(ap * 0.6, -ay * 0.3, 0))
    SetBone(ent, "b_l_forearm",   Angle(ap * 0.4, 0, 0))
end

local function GekkoResetArms(ent, dt)
    ent._armYaw   = ent._armYaw   or 0
    ent._armPitch = ent._armPitch or 0
    local maxStep = ARM_TURN_SPEED * dt
    ent._armYaw   = ent._armYaw   + math.Clamp(0 - ent._armYaw,   -maxStep, maxStep)
    ent._armPitch = ent._armPitch + math.Clamp(0 - ent._armPitch, -maxStep, maxStep)

    SetBone(ent, "b_r_shoulder",  Angle(0,  ent._armYaw * 0.5, 0))
    SetBone(ent, "b_r_upperarm",  Angle(ent._armPitch * 0.6, ent._armYaw * 0.3, 0))
    SetBone(ent, "b_r_forearm",   Angle(ent._armPitch * 0.4, 0, 0))

    SetBone(ent, "b_l_shoulder",  Angle(0,  -ent._armYaw * 0.5, 0))
    SetBone(ent, "b_l_upperarm",  Angle(ent._armPitch * 0.6, -ent._armYaw * 0.3, 0))
    SetBone(ent, "b_l_forearm",   Angle(ent._armPitch * 0.4, 0, 0))
end

-- ============================================================
--  HEAD AIM DRIVER  (b_spine4)
--
--  Bone channel confirmed working from idle:
--    ManipulateBoneAngles(bone, Angle(pitch, 0, -yaw), false)
--
--  Pitch is transmitted from server as NWFloat "GekkoHeadPitch".
--  Server computes it every think from the real enemy position.
--  Client only smooths and applies it.
--  This sidesteps ALL client-side position/entity resolution issues.
-- ============================================================
local HEAD_YAW_LIMIT  =  70
local HEAD_PITCH_UP   = -70
local HEAD_PITCH_DOWN =  50
local HEAD_TURN_SPEED = 200

local function GekkoUpdateHead(ent, dt)
    local bone = ent._spineBone
    if not bone or bone < 0 then return end

    local t       = CurTime()
    local bodyYaw = ent:GetAngles().y
    local vel     = ent:GetNWFloat("GekkoSpeed", 0)
    local enemy   = ent:GetNWEntity("GekkoEnemy", NULL)

    if not ent._cl_headYaw then
        ent._cl_headYaw    = bodyYaw
        ent._cl_headPitch  = 0
        ent._cl_headDir    = 1
        ent._cl_scanNext   = t + 1.5
        ent._cl_scanTarget = bodyYaw
    end

    local targetYaw, targetPitch

    if IsValid(enemy) then
        local enemyEye = enemy:GetPos() + Vector(0, 0, 40)
        targetYaw = (enemyEye - ent:GetPos()):Angle().y

        -- Read pitch from server NWFloat — server has authoritative enemy pos
        -- and computed it with the same SignedPitch formula.
        -- This avoids any client-side GetPos() weirdness during Draw().
        targetPitch = math.Clamp(
            ent:GetNWFloat("GekkoHeadPitch", 0),
            HEAD_PITCH_UP, HEAD_PITCH_DOWN
        )
    elseif vel < 6 then
        -- Idle scan: yaw sweep + gentle pitch nod
        if t > ent._cl_scanNext then
            ent._cl_headDir    = -ent._cl_headDir
            ent._cl_scanNext   = t + math.Rand(2, 5)
            ent._cl_scanTarget = bodyYaw + ent._cl_headDir * math.Rand(35, 70)
        end
        targetYaw   = ent._cl_scanTarget
        targetPitch = math.sin(t * 0.6) * 12
    else
        -- Walking/running: face forward, light bob
        targetYaw   = bodyYaw
        targetPitch = math.sin(t * 2.5) * 5
    end

    -- Smooth yaw
    local relTarget = math.Clamp(math.NormalizeAngle(targetYaw - bodyYaw), -HEAD_YAW_LIMIT, HEAD_YAW_LIMIT)
    targetYaw = bodyYaw + relTarget
    ent._cl_headYaw = bodyYaw + math.Clamp(math.NormalizeAngle(ent._cl_headYaw - bodyYaw), -HEAD_YAW_LIMIT, HEAD_YAW_LIMIT)
    local yawDiff = math.NormalizeAngle(targetYaw - ent._cl_headYaw)
    ent._cl_headYaw = ent._cl_headYaw + math.Clamp(yawDiff, -HEAD_TURN_SPEED * dt, HEAD_TURN_SPEED * dt)

    -- Smooth pitch — identical smoothing path as idle
    local pitchDiff   = targetPitch - ent._cl_headPitch
    ent._cl_headPitch = ent._cl_headPitch + math.Clamp(pitchDiff, -HEAD_TURN_SPEED * dt, HEAD_TURN_SPEED * dt)
    ent._cl_headPitch = math.Clamp(ent._cl_headPitch, HEAD_PITCH_UP, HEAD_PITCH_DOWN)

    local relYaw = math.Clamp(math.NormalizeAngle(ent._cl_headYaw - bodyYaw), -HEAD_YAW_LIMIT, HEAD_YAW_LIMIT)

    -- Same channel mapping confirmed working in idle
    ent:ManipulateBoneAngles(bone, Angle(ent._cl_headPitch, 0, -relYaw), false)
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
