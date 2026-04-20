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

function ENT:Think()
    self:GekkoDeath_Think()
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
JITTER_DEG      = 9.9   -- ± degrees applied per axis
JITTER_DUR_MAX  = 0.4   -- maximum seconds shaved off a duration

local function JitterAng(base)
    local function j() return (math.random() - 0.5) * 2 * JITTER_DEG end
    return Angle(base.p + j(), base.y + j(), base.r + j())
end

-- Call once per attack trigger to get a shortened duration.
-- Returns a value in [ base - JITTER_DUR_MAX , base ].
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

-- mirrored basic kick (left upper leg)
KICK_L_BONE_NAME  = "b_l_upperleg"
KICK_L_BONE_ANGLE = KICK_BONE_ANGLE
KICK_L_BONE_RESET = KICK_BONE_RESET
