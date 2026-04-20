include("shared.lua")

include("muzzleflash_system.lua")
include("bullet_impact_system.lua")
include("death_pose_system.lua")
-- ============================================================
--  HELPERS
-- ============================================================
local function SetBoneAng(ent, name, ang)
    local id = ent:LookupBone(name)
    if id and id >= 0 then ent:ManipulateBoneAngles(id, ang, false) end
end

local function SetBonePos(ent, name, pos)
    local id = ent:LookupBone(name)
    if id and id >= 0 then ent:ManipulateBonePosition(id, pos, false) end
end

-- preserve existing Think behavior and also drive death pose
local _OLD_THINK = ENT.Think
function ENT:Think()
    if _OLD_THINK then _OLD_THINK(self) end
    if self.GekkoDeath_Think then self:GekkoDeath_Think() end
end

-- ============================================================
--  JUMP STATE CONSTANTS  (mirror shared.lua)
-- ============================================================
JUMP_NONE    = 0
JUMP_RISING  = 1
JUMP_FALLING = 2
JUMP_LAND    = 3

-- ============================================================
--  GROUNDED POSE CONSTANTS  (must match leg_disable_system.lua)
-- ============================================================
GND_PELVIS_OFFSET_Z = -125
GND_L_THIGH_ANG     = Angle(0,   0,   -50)
GND_R_THIGH_ANG     = Angle(126, -105,  0)

local function GekkoApplyGroundedPose(ent)
    local pelBone = ent:LookupBone("b_pelvis")
    if pelBone and pelBone >= 0 then
        ent:ManipulateBonePosition(pelBone, Vector(0, 0, GND_PELVIS_OFFSET_Z), false)
    end

    local lBone = ent:LookupBone("b_l_thigh")
    if lBone and lBone >= 0 then
        ent:ManipulateBoneAngles(lBone, GND_L_THIGH_ANG, false)
    end

    local rBone = ent:LookupBone("b_r_thigh")
    if rBone and rBone >= 0 then
        ent:ManipulateBoneAngles(rBone, GND_R_THIGH_ANG, false)
    end
end

-- ============================================================
--  HIP BONE MUTEX
-- ============================================================
local function ClaimHips(ent, key)
    if ent._hipDriver == nil or ent._hipDriver == key then
        ent._hipDriver = key
        return true
    end
    return false
end

local function ReleaseHips(ent, key)
    if ent._hipDriver == key then
        ent._hipDriver = nil
    end
end

-- ============================================================
--  JITTER HELPERS
--  JitterAng  : adds ±JITTER_DEG to each axis of a base Angle
--  JitterDur  : shortens a duration by a random amount (never lengthens)
-- ============================================================
JITTER_DEG      = 9.9
JITTER_DUR_MAX  = 0.4

local function JitterAng(base)
    local function j() return (math.random() - 0.5) * 2 * JITTER_DEG end
    return Angle(base.p + j(), base.y + j(), base.r + j())
end

local function JitterDur(base)
    return base - math.random() * JITTER_DUR_MAX
end

-- ============================================================
--  KICK ANIMATION  (b_r_upperleg)
-- ============================================================
KICK_WINDOW     = 1.0
KICK_BONE_NAME  = "b_r_upperleg"
KICK_BONE_ANGLE = Angle(112, 0, 0)
KICK_BONE_RESET = Angle(0,   0, 0)

KICK_L_BONE_NAME  = "b_l_upperleg"
KICK_L_BONE_ANGLE = KICK_BONE_ANGLE
KICK_L_BONE_RESET = KICK_BONE_RESET

-- ============================================================
--  HEADBUTT ANIMATION
-- ============================================================
HB_DURATION       = 0.7
HB_PEAK           = 0.45
HB_SPINE3_ANG_X   = -60
HB_PEDESTAL_POS_X =  70
HB_PEDESTAL_POS_Z = -70
HB_SPINE3_BONE    = "b_spine3"
HB_PEDESTAL_BONE  = "b_pedestal"

-- ============================================================
--  FK360 ANIMATION
-- ============================================================
FK360_RAMP     = 0.15
FK360_BONE     = "b_pelvis"

-- ============================================================
--  SMOOTHSTEP
-- ============================================================
local function Smoothstep(t)
    t = math.Clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

local function LerpAngle(a, b, t)
    return Angle(
        Lerp(t, a.p, b.p),
        Lerp(t, a.y, b.y),
        Lerp(t, a.r, b.r)
    )
end

-- ============================================================
--  BASIC KICK DRIVERS
-- ============================================================
local function GekkoDoKickBone(ent)
    if ent._kickBoneIdx == nil then
        ent._kickBoneIdx   = ent:LookupBone(KICK_BONE_NAME) or -1
        ent._kickEndTime   = 0
        ent._kickPulseLast = ent:GetNWInt("GekkoKickPulse", 0)
        ent._kickWasActive = false
        ent._kickJitAng    = KICK_BONE_ANGLE
    end

    local pulse = ent:GetNWInt("GekkoKickPulse", 0)
    if pulse ~= ent._kickPulseLast then
        ent._kickPulseLast = pulse
        local dur = JitterDur(KICK_WINDOW)
        ent._kickEndTime  = math.max(ent._kickEndTime, CurTime() + dur)
        ent._kickJitAng   = JitterAng(KICK_BONE_ANGLE)
    end

    local boneIdx = ent._kickBoneIdx
    if not boneIdx or boneIdx < 0 then return end

    local active = CurTime() < ent._kickEndTime
    if active then
        ent._kickWasActive = true
        ent:ManipulateBoneAngles(boneIdx, ent._kickJitAng, false)
    elseif ent._kickWasActive then
        ent._kickWasActive = false
        ent:ManipulateBoneAngles(boneIdx, KICK_BONE_RESET, false)
    end
end

local function GekkoDoKickLBone(ent)
    if ent._kickLBoneIdx == nil then
        ent._kickLBoneIdx   = ent:LookupBone(KICK_L_BONE_NAME) or -1
        ent._kickLEndTime   = 0
        ent._kickLPulseLast = ent:GetNWInt("GekkoLKickPulse", 0)
        ent._kickLWasActive = false
        ent._kickLJitAng    = KICK_L_BONE_ANGLE
    end

    local pulse = ent:GetNWInt("GekkoLKickPulse", 0)
    if pulse ~= ent._kickLPulseLast then
        ent._kickLPulseLast = pulse
        local dur = JitterDur(KICK_WINDOW)
        ent._kickLEndTime  = math.max(ent._kickLEndTime, CurTime() + dur)
        ent._kickLJitAng   = JitterAng(KICK_L_BONE_ANGLE)
    end

    local boneIdx = ent._kickLBoneIdx
    if not boneIdx or boneIdx < 0 then return end

    local active = CurTime() < ent._kickLEndTime
    if active then
        ent._kickLWasActive = true
        ent:ManipulateBoneAngles(boneIdx, ent._kickLJitAng, false)
    elseif ent._kickLWasActive then
        ent._kickLWasActive = false
        ent:ManipulateBoneAngles(boneIdx, KICK_L_BONE_RESET, false)
    end
end

-- ============================================================
--  INIT / DRAW
-- ============================================================
function ENT:Initialize()
    self._spineBone = self:LookupBone("b_spine3") or -1
    if self.GekkoDeath_Init then self:GekkoDeath_Init() end
end

function ENT:Draw()
    self:DrawModel()

    GekkoDoKickBone(self)
    GekkoDoKickLBone(self)
end

language.Add("npc_vj_gekko", "Gekko")
