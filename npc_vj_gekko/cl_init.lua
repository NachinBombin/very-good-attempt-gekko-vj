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
--  Chaotic thrash during melee window — intentionally broken.
-- ============================================================
local function GekkoStompLegs(ent)
    local t     = CurTime()
    local freq  = 14
    local amp   = 55
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
--  Derived from the walk/run cycle on b_r_thigh / b_l_thigh.
--  We sample the animation's bone positions after SetupBones(),
--  detect each stride peak (when the thigh swings forward most)
--  and emit a sound at that moment.
--
--  Strategy: track the sign-flip of the thigh pitch derived from
--  the current cycle phase.  The walk seq runs at roughly 1.4
--  strides/sec (one full cycle = 2 steps), run at ~2.2.
--  We read the NWFloat("GekkoSpeed") the server already pushes.
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

    -- Derive a phase from time that matches the animation cycle.
    -- walk seq idx=4 cycles at ~0.71 Hz full cycle (two steps).
    -- run  seq idx=6 cycles at ~1.1  Hz full cycle.
    local cycleHz = (vel > 160) and 1.1 or 0.71
    local t       = CurTime()
    local cycleT  = t * cycleHz * 2 * math.pi   -- full sine cycle

    -- Right foot contacts ground when sin(cycleT) crosses +peak → zero falling
    -- Left  foot offset by pi
    local sinR = math.sin(cycleT)
    local sinL = math.sin(cycleT + math.pi)

    -- Detect falling zero-crossing (peak just passed) for each leg
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
--  Both arms (shoulder → upperarm → forearm) rotate to point
--  their gunrack toward the enemy (or forward when idle).
--  Uses the bone world matrix to compute a local aim delta.
-- ============================================================
local ARM_YAW_LIMIT   = 75   -- degrees each side the shoulder can swing
local ARM_PITCH_LIMIT = 50   -- degrees up/down the forearm can tilt
local ARM_TURN_SPEED  = 120  -- degrees per second tracking speed

local function GekkoAimArms(ent, enemyPos, dt)
    -- Build a rough aim direction in entity-local space
    local myPos  = ent:GetPos() + Vector(0, 0, 120)  -- approx torso height
    local aimDir = (enemyPos - myPos):GetNormalized()
    local entAng = ent:GetAngles()

    -- World-space yaw/pitch toward enemy
    local aimAng    = aimDir:Angle()
    local bodyYaw   = entAng.y
    local relYaw    = math.NormalizeAngle(aimAng.y - bodyYaw)
    local relPitch  = -aimAng.p   -- negative because model faces forward

    -- Clamp
    local clampedYaw   = math.Clamp(relYaw,   -ARM_YAW_LIMIT,   ARM_YAW_LIMIT)
    local clampedPitch = math.Clamp(relPitch, -ARM_PITCH_LIMIT, ARM_PITCH_LIMIT)

    -- Smooth arm yaw/pitch state
    ent._armYaw   = ent._armYaw   or 0
    ent._armPitch = ent._armPitch or 0

    local maxStep = ARM_TURN_SPEED * dt
    ent._armYaw   = ent._armYaw   + math.Clamp(clampedYaw   - ent._armYaw,   -maxStep, maxStep)
    ent._armPitch = ent._armPitch + math.Clamp(clampedPitch - ent._armPitch, -maxStep, maxStep)

    local ay = ent._armYaw
    local ap = ent._armPitch

    -- Distribute across the arm chain.
    -- Shoulder handles yaw swing, forearm handles pitch tilt.
    -- Both sides mirror yaw (negative for left).
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
--  Full yaw + pitch tracking.
--  Yaw  clamped ±70°  (old behaviour preserved)
--  Pitch clamped +40° (look down) / -55° (look up)
--  Idle: slow yaw scan, gentle nodding pitch bob.
-- ============================================================
local HEAD_YAW_LIMIT    =  70
local HEAD_PITCH_UP     = -55
local HEAD_PITCH_DOWN   =  40
local HEAD_TURN_SPEED   = 180   -- deg/sec

local function GekkoUpdateHead(ent, dt)
    local bone = ent._spineBone
    if not bone or bone < 0 then return end

    local t       = CurTime()
    local bodyYaw = ent:GetAngles().y
    local vel     = ent:GetNWFloat("GekkoSpeed", 0)
    local enemy   = ent:GetNWEntity("GekkoEnemy", NULL)

    -- Init state
    if not ent._cl_headYaw then
        ent._cl_headYaw    = bodyYaw
        ent._cl_headPitch  = 0
        ent._cl_headDir    = 1
        ent._cl_scanNext   = t + 1.5
        ent._cl_scanTarget = bodyYaw
    end

    local targetYaw, targetPitch

    if IsValid(enemy) then
        local eyePos   = ent:GetPos() + Vector(0, 0, 130)
        local toEnemy  = (enemy:GetPos() + Vector(0, 0, 40) - eyePos):Angle()
        targetYaw   = toEnemy.y
        targetPitch = math.Clamp(toEnemy.p, HEAD_PITCH_UP, HEAD_PITCH_DOWN)
    elseif vel < 6 then
        -- idle: yaw scan + gentle pitch bob
        if t > ent._cl_scanNext then
            ent._cl_headDir    = -ent._cl_headDir
            ent._cl_scanNext   = t + math.Rand(2, 5)
            ent._cl_scanTarget = bodyYaw + ent._cl_headDir * math.Rand(35, 70)
        end
        targetYaw   = ent._cl_scanTarget
        targetPitch = math.sin(t * 0.6) * 8   -- gentle nod
    else
        -- walking/running: face forward, slight bob
        targetYaw   = bodyYaw
        targetPitch = math.sin(t * 2.5) * 4
    end

    -- Clamp yaw relative to body
    local relTarget = math.Clamp(math.NormalizeAngle(targetYaw - bodyYaw), -HEAD_YAW_LIMIT, HEAD_YAW_LIMIT)
    targetYaw = bodyYaw + relTarget

    -- Smooth yaw
    ent._cl_headYaw = bodyYaw + math.Clamp(math.NormalizeAngle(ent._cl_headYaw - bodyYaw), -HEAD_YAW_LIMIT, HEAD_YAW_LIMIT)
    local yawDiff   = math.NormalizeAngle(targetYaw - ent._cl_headYaw)
    ent._cl_headYaw = ent._cl_headYaw + math.Clamp(yawDiff, -HEAD_TURN_SPEED * dt, HEAD_TURN_SPEED * dt)

    -- Smooth pitch
    local pitchDiff   = targetPitch - ent._cl_headPitch
    ent._cl_headPitch = ent._cl_headPitch + math.Clamp(pitchDiff, -HEAD_TURN_SPEED * dt, HEAD_TURN_SPEED * dt)
    ent._cl_headPitch = math.Clamp(ent._cl_headPitch, HEAD_PITCH_UP, HEAD_PITCH_DOWN)

    local relYaw = math.Clamp(math.NormalizeAngle(ent._cl_headYaw - bodyYaw), -HEAD_YAW_LIMIT, HEAD_YAW_LIMIT)

    -- Apply: pitch uses p channel, yaw uses r channel on b_spine4
    -- (spine4 is the neck/head root — pitch = forward tilt, yaw via roll given bone orientation)
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

    -- Head: full yaw + pitch
    GekkoUpdateHead(self, dt)

    -- Arms: aim at enemy or return to rest
    if IsValid(enemy) then
        GekkoAimArms(self, enemy:GetPos() + Vector(0, 0, 40), dt)
    else
        GekkoResetArms(self, dt)
    end

    -- Footstep sync (sound emission)
    GekkoSyncFootsteps(self)

    -- Stomp melee leg override
    local stompEnd = self:GetNWFloat("GekkoStompEnd", 0)
    if t < stompEnd then
        GekkoStompLegs(self)
    end

    self:DrawModel()
end
