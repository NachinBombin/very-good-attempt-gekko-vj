include("shared.lua")

-- ============================================================
--  HELPERS
-- ============================================================
local function SetBone(ent, name, ang)
    local id = ent:LookupBone(name)
    if id and id >= 0 then ent:ManipulateBoneAngles(id, ang, false) end
end

-- ============================================================
--  JUMP STATE CONSTANTS  (mirror shared.lua)
-- ============================================================
local JUMP_NONE    = 0
local JUMP_RISING  = 1
local JUMP_FALLING = 2
local JUMP_LAND    = 3

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
--  FOOTSTEP CAMERA SHAKE
-- ============================================================
local SHAKE_NEAR_DIST = 350
local SHAKE_FAR_DIST  = 750
local SHAKE_MIN_SPEED = 8

local function GekkoFootShake(ent)
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local vel = ent:GetNWFloat("GekkoSpeed", 0)
    if vel < SHAKE_MIN_SPEED then return end

    local dist = ply:GetPos():Distance(ent:GetPos())
    if dist >= SHAKE_FAR_DIST then return end

    local cycleHz = (vel > 160) and 1.1 or 0.71
    local cycleT  = CurTime() * cycleHz * 2 * math.pi

    local sinR = math.sin(cycleT)
    local sinL = math.sin(cycleT + math.pi)

    local prevR = ent._shakePhaseR or sinR
    local prevL = ent._shakePhaseL or sinL
    ent._shakePhaseR = sinR
    ent._shakePhaseL = sinL

    local footplant = (prevR > 0 and sinR <= 0) or (prevL > 0 and sinL <= 0)
    if not footplant then return end

    local alpha = 1 - (dist / SHAKE_FAR_DIST)
    local amp   = (dist < SHAKE_NEAR_DIST) and (12 * alpha) or (5 * alpha)
    util.ScreenShake(ent:GetPos(), amp, 14, 0.18, SHAKE_FAR_DIST)
end

-- ============================================================
--  HEAD DRIVER  (b_spine4)  —  YAW + PITCH
-- ============================================================
local HEAD_LIMIT       =  50
local HEAD_PITCH_UP    = -60
local HEAD_PITCH_DOWN  =  60
local HEAD_SPEED       =  30

local function GekkoUpdateHead(ent, dt)
    local bone = ent._spineBone
    if not bone or bone < 0 then return end

    ent._headYaw   = ent._headYaw   or 0
    ent._headPitch = ent._headPitch or 0

    local enemy       = ent:GetNWEntity("GekkoEnemy", NULL)
    local targetYaw   = 0
    local targetPitch = 0

    if IsValid(enemy) then
        local boneMatrix = ent:GetBoneMatrix(bone)
        local pos        = boneMatrix and boneMatrix:GetTranslation() or (ent:GetPos() + Vector(0, 0, 130))
        local toEnemy    = (enemy:GetPos() + Vector(0, 0, 40) - pos):Angle()
        targetYaw   = math.Clamp(math.NormalizeAngle(toEnemy.y - ent:GetAngles().y), -HEAD_LIMIT,     HEAD_LIMIT)
        targetPitch = math.Clamp(toEnemy.p,                                           HEAD_PITCH_UP,   HEAD_PITCH_DOWN)
    end

    local maxStep   = HEAD_SPEED * dt
    local yawDiff   = math.NormalizeAngle(targetYaw - ent._headYaw)
    ent._headYaw    = math.Clamp(ent._headYaw   + math.Clamp(yawDiff,               -maxStep, maxStep), -HEAD_LIMIT,    HEAD_LIMIT)
    local pitchDiff = targetPitch - ent._headPitch
    ent._headPitch  = math.Clamp(ent._headPitch + math.Clamp(pitchDiff,             -maxStep, maxStep),  HEAD_PITCH_UP,  HEAD_PITCH_DOWN)

    ent:ManipulateBoneAngles(bone, Angle(-ent._headYaw, 0, ent._headPitch), false)
end

-- ============================================================
--  THUMPER DUST HELPER
--  Wiki fields: Origin, Scale, Entity  (exactly these three)
--  util.Effect args: name, data  (no extra args from clientside)
-- ============================================================
local function SpawnThumperDust(pos, ent, scale)
    local e = EffectData()
    e:SetOrigin(pos)
    e:SetScale(scale or 1)
    e:SetEntity(ent)
    util.Effect("ThumperDust", e)
end

-- ============================================================
--  JUMP DUST
-- ============================================================
local ATT_MACHINEGUN = 3

local function GekkoDoJumpDust(ent)
    local pulse = ent:GetNWInt("GekkoJumpDust", 0)
    if pulse == 0 then return end
    if pulse == ent._lastJumpDustPulse then return end
    ent._lastJumpDustPulse = pulse

    local pos = ent:GetPos()
    SpawnThumperDust(pos,                    ent, 1.2)
    SpawnThumperDust(pos + Vector(0, 0, 20), ent, 0.8)
end

-- ============================================================
--  LAND DUST
-- ============================================================
local function GekkoDoLandDust(ent)
    local pulse = ent:GetNWInt("GekkoLandDust", 0)
    if pulse == 0 then return end
    if pulse == ent._lastLandDustPulse then return end
    ent._lastLandDustPulse = pulse

    local pos   = ent:GetPos()
    local fwd   = ent:GetForward()
    local right = ent:GetRight()

    SpawnThumperDust(pos,               ent, 1.5)
    SpawnThumperDust(pos + fwd   * 48,  ent, 1.0)
    SpawnThumperDust(pos - right * 48,  ent, 1.0)
    SpawnThumperDust(pos + right * 48,  ent, 1.0)
end

-- ============================================================
--  MG FIRING FX
--  RifleShellEject fields: Entity, Origin, Angles
--  ManhackSparks fields:   Origin, Normal, Angles
-- ============================================================
local SHELL_INTERVAL = 0.09

local function GekkoDoMGFX(ent)
    if not ent:GetNWBool("GekkoMGFiring", false) then
        ent._nextSparkT = nil
        ent._nextShellT = nil
        return
    end

    local attData = ent:GetAttachment(ATT_MACHINEGUN)
    if not attData then return end

    local pos = attData.Pos
    local ang = attData.Ang
    local fwd = ang:Forward()
    local now = CurTime()

    -- Shell eject: rate-limited to ~11/sec
    if not ent._nextShellT or now >= ent._nextShellT then
        ent._nextShellT = now + SHELL_INTERVAL

        local shellEff = EffectData()
        shellEff:SetEntity(ent)
        shellEff:SetOrigin(pos)
        shellEff:SetAngles(ang)
        util.Effect("RifleShellEject", shellEff)
    end

    -- Manhack sparks intermittently
    if not ent._nextSparkT or now >= ent._nextSparkT then
        ent._nextSparkT = now + math.Rand(0.4, 0.9)

        local sparkEff = EffectData()
        sparkEff:SetOrigin(pos + fwd * 8)
        sparkEff:SetNormal(fwd)
        sparkEff:SetAngles(ang)
        sparkEff:SetEntity(ent)
        sparkEff:SetMagnitude(3)
        sparkEff:SetScale(1)
        sparkEff:SetRadius(12)
        util.Effect("ManhackSparks", sparkEff)
    end
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

    local jumpState = self:GetGekkoJumpState()
    local landing   = (jumpState == JUMP_LAND)

    if not landing then
        GekkoUpdateHead(self, dt)
    end

    if not landing then
        GekkoSyncFootsteps(self)
        GekkoFootShake(self)
    end

    local grounded = (jumpState == JUMP_NONE)
    local stompEnd = self:GetNWFloat("GekkoStompEnd", 0)
    if t < stompEnd and grounded then
        GekkoStompLegs(self)
    end

    GekkoDoJumpDust(self)
    GekkoDoLandDust(self)
    GekkoDoMGFX(self)

    self:DrawModel()
end
