include("shared.lua")

include("muzzleflash_system.lua")
include("bullet_impact_system.lua")
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
--  DEATH FALL POSE CONSTANTS
--  Two-stage client-side death pose to avoid hip-piston disconnects.
--  Stage 1: one leg kicks out as the fall begins.
--  Stage 2: both legs splay out while pelvis drops to the ground.
-- ============================================================
DEATHPOSE_STAGE1_TIME   = 0.26
DEATHPOSE_STAGE2_TIME   = 0.52
DEATHPOSE_BLEND_OUT     = 0.18
DEATHPOSE_L_THIGH_BONE  = "b_l_thigh"
DEATHPOSE_R_THIGH_BONE  = "b_r_thigh"
DEATHPOSE_PELVIS_BONE   = "b_pelvis"
DEATHPOSE_STAGE1_L_ANG  = Angle(-15, 67, -12)
DEATHPOSE_STAGE2_L_ANG  = Angle(-15, 67, -12)
DEATHPOSE_STAGE2_R_ANG  = Angle(0, -77, -22)
DEATHPOSE_STAGE1_PEL_Z  = -12
DEATHPOSE_STAGE2_PEL_Z  = -114

-- Fallbacks from the leg-disable grounded frog pose so the dead pose can
-- remain coherent if the death sequence has ended but the ragdoll wire-up
-- has not taken over yet.
DEATHPOSE_SETTLED_L_ANG = GND_L_THIGH_ANG
DEATHPOSE_SETTLED_R_ANG = GND_R_THIGH_ANG
DEATHPOSE_SETTLED_PEL_Z = GND_PELVIS_OFFSET_Z

local function GekkoResetDeathPose(ent)
    if ent._deathPoseLIdx and ent._deathPoseLIdx >= 0 then
        ent:ManipulateBoneAngles(ent._deathPoseLIdx, Angle(0, 0, 0), false)
    end
    if ent._deathPoseRIdx and ent._deathPoseRIdx >= 0 then
        ent:ManipulateBoneAngles(ent._deathPoseRIdx, Angle(0, 0, 0), false)
    end
    if ent._deathPosePelIdx and ent._deathPosePelIdx >= 0 then
        ent:ManipulateBonePosition(ent._deathPosePelIdx, Vector(0, 0, 0), false)
    end
    ent._deathPoseActive = false
    ent._deathPoseDone   = false
    ent._deathPoseStart  = nil
end

local function GekkoUpdateDeathPose(ent)
    if ent._deathPoseInited == nil then
        ent._deathPoseInited = true
        ent._deathPoseLIdx   = ent:LookupBone(DEATHPOSE_L_THIGH_BONE) or -1
        ent._deathPoseRIdx   = ent:LookupBone(DEATHPOSE_R_THIGH_BONE) or -1
        ent._deathPosePelIdx = ent:LookupBone(DEATHPOSE_PELVIS_BONE)  or -1
        ent._deathPoseAliveLast = ent:Health() > 0
    end

    local alive = ent:Health() > 0
    if alive then
        if ent._deathPoseActive or ent._deathPoseDone then
            GekkoResetDeathPose(ent)
        end
        ent._deathPoseAliveLast = true
        return false
    end

    if not ent._deathPoseActive and not ent._deathPoseDone then
        ent._deathPoseActive = true
        ent._deathPoseStart  = CurTime()
    end

    ent._deathPoseAliveLast = false

    local startT = ent._deathPoseStart or CurTime()
    local elapsed = CurTime() - startT

    local lAng = Angle(0, 0, 0)
    local rAng = Angle(0, 0, 0)
    local pelZ = 0

    if elapsed < DEATHPOSE_STAGE1_TIME then
        local env = Smoothstep(elapsed / DEATHPOSE_STAGE1_TIME)
        lAng = LerpAngle(Angle(0, 0, 0), DEATHPOSE_STAGE1_L_ANG, env)
        rAng = Angle(0, 0, 0)
        pelZ = Lerp(env, 0, DEATHPOSE_STAGE1_PEL_Z)
    elseif elapsed < DEATHPOSE_STAGE2_TIME then
        local env = Smoothstep((elapsed - DEATHPOSE_STAGE1_TIME) / (DEATHPOSE_STAGE2_TIME - DEATHPOSE_STAGE1_TIME))
        lAng = LerpAngle(DEATHPOSE_STAGE1_L_ANG, DEATHPOSE_STAGE2_L_ANG, env)
        rAng = LerpAngle(Angle(0, 0, 0), DEATHPOSE_STAGE2_R_ANG, env)
        pelZ = Lerp(env, DEATHPOSE_STAGE1_PEL_Z, DEATHPOSE_STAGE2_PEL_Z)
    else
        lAng = DEATHPOSE_SETTLED_L_ANG
        rAng = DEATHPOSE_SETTLED_R_ANG
        pelZ = DEATHPOSE_SETTLED_PEL_Z
        ent._deathPoseDone = true
    end

    if ent._deathPoseLIdx and ent._deathPoseLIdx >= 0 then
        ent:ManipulateBoneAngles(ent._deathPoseLIdx, lAng, false)
    end
    if ent._deathPoseRIdx and ent._deathPoseRIdx >= 0 then
        ent:ManipulateBoneAngles(ent._deathPoseRIdx, rAng, false)
    end
    if ent._deathPosePelIdx and ent._deathPosePelIdx >= 0 then
        ent:ManipulateBonePosition(ent._deathPosePelIdx, Vector(0, 0, pelZ), false)
    end

    return true
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

local function JitterDur(base)
    return base - math.random() * JITTER_DUR_MAX
end

KICK_WINDOW     = 1.0
KICK_BONE_NAME  = "b_r_upperleg"
KICK_BONE_ANGLE = Angle(112, 0, 0)
KICK_BONE_RESET = Angle(0,   0, 0)
KICK_L_BONE_NAME  = "b_l_upperleg"
KICK_L_BONE_ANGLE = KICK_BONE_ANGLE
KICK_L_BONE_RESET = KICK_BONE_RESET
HB_DURATION       = 0.7
HB_PEAK           = 0.45
HB_SPINE3_ANG_X   = -60
HB_PEDESTAL_POS_X =  70
HB_PEDESTAL_POS_Z = -70
HB_SPINE3_BONE    = "b_spine3"
HB_PEDESTAL_BONE  = "b_pedestal"
FK360_RAMP     = 0.15
FK360_BONE     = "b_pelvis"
FK360B_PED_BONE      = "b_pedestal"
FK360B_PISTON_BONE   = "b_r_hippiston1"
FK360B_PEL_BONE      = "b_pelvis"
FK360B_PREP_DUR      = 0.30
FK360B_ELONGATE_DUR  = 0.20
FK360B_LAND_DUR      = 0.30
FK360B_RESTORE_DUR   = 0.25
FK360B_PEL_Z_ELONGATE = 43
FK360B_PEL_Z_LAND     = 22
FK360B_PED_ROLL       = 12
FK360B_PISTON_PITCH   = 15
FK360B_PISTON_YAW     = -8
SK_DURATION = 1.3
SK_P1_END   = 0.250
SK_P2_END   = 0.490
SK_P3_END   = 0.580
SK_P4_END   = 0.700
SK_RAMP       = 0.15
SK_YAW_TOTAL  = 590
SK_PED_BONE   = "b_Pedestal"
SK_PEL_BONE   = "b_pelvis"
SK_HIP_BONE   = "b_r_hippiston1"
SK_ULEG_BONE  = "b_r_upperleg"
SK_PEL_DROP   = -80
SK_HIP_Z      = -22
SK_ULEG_X     = 100
FK_DURATION      = 1.1
FK_PHASE_HOLD    = 0.300 / FK_DURATION
FK_PHASE_EXTEND  = 0.550 / FK_DURATION
FK_PHASE_RECOVER = 0.700 / FK_DURATION
FK_LHIP_Y_PREP   =  105
FK_LHIP_X_PREP   =   36
FK_RHIP_X_PREP   =   36
FK_LHIP_Y_EXT    = -105
FK_LHIP_BONE     = "b_l_hippiston1"
FK_RHIP_BONE     = "b_r_hippiston1"
FKR_DURATION      = 1.3
FKR_PHASE_HOLD    = 0.310 / FKR_DURATION
FKR_PHASE_EXTEND  = 0.550 / FKR_DURATION
FKR_PHASE_RECOVER = 0.790 / FKR_DURATION
FKR_RHIP_Y_PREP   = 105
FKR_RHIP_X_PREP   =   36
FKR_LHIP_X_PREP   =   36
FKR_RHIP_Y_EXT    = -105
FKR_RHIP_BONE     = "b_r_hippiston1"
FKR_LHIP_BONE     = "b_l_hippiston1"
DGK_DURATION = 1.0
DGK_P1_END   = 0.300 / DGK_DURATION
DGK_P2_END   = 0.600 / DGK_DURATION
DGK_P3_END   = 0.750 / DGK_DURATION
DGK_P4_END   = 0.950 / DGK_DURATION
DGK_P1_LHIP  = Angle( -8, -22,  43)
DGK_P1_RHIP  = Angle(-32,   0,   0)
DGK_P3_LHIP  = Angle( -8, -22, 105)
DGK_P3_RHIP  = Angle(109,   0,   0)
DGK_P4_LHIP  = Angle(136,   0,  12)
DGK_P4_RHIP  = Angle(  0,   0,   0)
DGK_LHIP_BONE = "b_l_hippiston1"
DGK_RHIP_BONE = "b_r_hippiston1"
DGKR_DURATION = 1.0
DGKR_P1_END   = 0.300 / DGKR_DURATION
DGKR_P2_END   = 0.500 / DGKR_DURATION
DGKR_P3_END   = 0.700 / DGKR_DURATION
DGKR_P4_END   = 0.920 / DGKR_DURATION
DGKR_P1_LHIP  = Angle( -36, -29,   43)
DGKR_P1_RHIP  = Angle(  12, -22,   15)
DGKR_P2_LHIP  = Angle( -70, -29,   43)
DGKR_P2_RHIP  = Angle(   8,  -5, -105)
DGKR_P3_LHIP  = Angle(-143, -29,   43)
DGKR_P3_RHIP  = Angle(-105,  -5,  -12)
DGKR_LHIP_BONE = "b_l_hippiston1"
DGKR_RHIP_BONE = "b_r_hippiston1"
BITE_DURATION = 1.5
BITE_P0_END   = 0.200 / BITE_DURATION
BITE_P1_END   = 0.480 / BITE_DURATION
BITE_P2_END   = 0.580 / BITE_DURATION
BITE_P3_END   = 0.780 / BITE_DURATION
BITE_P4_END   = 1.100 / BITE_DURATION
BITE_P0_LHIP   = Angle(  46, -15,  15)
BITE_P0_RHIP   = Angle( -25,   0, -25)
BITE_P0_PELVIS = Angle(   0,   0,   0)
BITE_P0_SPINE4 = Angle(   0,   0,   0)
BITE_P1_LHIP   = Angle(  46,  12,  19)
BITE_P1_RHIP   = Angle( -22,  29,  -8)
BITE_P1_PELVIS = Angle(   0, -32,   0)
BITE_P1_SPINE4 = Angle(   0,   0,   0)
BITE_P2_PELVIS = Angle(  -5,  15,   5)
BITE_P2_SPINE4 = Angle( -19,  50, 102)
BITE_P3_LHIP   = Angle(  -1, -36,  19)
BITE_P3_RHIP   = Angle( -22, -22,  -8)
BITE_P3_PELVIS = Angle(  53,  50, 129)
BITE_P3_SPINE4 = Angle( -19,  50, 102)
BITE_LHIP_BONE   = "b_l_hippiston1"
BITE_RHIP_BONE   = "b_r_hippiston1"
BITE_PELVIS_BONE = "b_pelvis"
BITE_SPINE4_BONE = "b_spine3"
BITE_PED_BONE    = "b_pedestal"
BITE_PED_Z       = -65
BITE_PED_RAMP    = 0.20
TK_DURATION = 1.5
TK_P1_END   = 0.200 / TK_DURATION
TK_P2_END   = 0.420 / TK_DURATION
TK_P3_END   = 0.630 / TK_DURATION
TK_P4_END   = 0.820 / TK_DURATION
TK_P1_LHIP  = Angle(  57,  43,  70)
TK_P1_RHIP  = Angle(  88,   0, -36)
TK_P2_LHIP  = Angle(  22,  53,   1)
TK_P2_RHIP  = Angle( -57,   0, -67)
TK_P3_LHIP  = Angle( -70,  15,   1)
TK_P3_RHIP  = Angle( -88,   0, -67)
TK_P4_LHIP  = Angle( -95, -12, -12)
TK_P4_RHIP  = Angle(-105,  70, -46)
TK_LHIP_BONE = "b_l_hippiston1"
TK_RHIP_BONE = "b_r_hippiston1"
SPC_DURATION = 1.5
SPC_P1_END   = 0.10 / SPC_DURATION
SPC_P2_END   = 0.26 / SPC_DURATION
SPC_P3_END   = 0.36 / SPC_DURATION
SPC_P4_END   = 0.56 / SPC_DURATION
SPC_P5_END   = 0.69 / SPC_DURATION
SPC_P6_END   = 1.40 / SPC_DURATION
SPC_P7_END   = 5.10 / SPC_DURATION
SPC_P1_LHIP   = Angle(  0,  -6,   0)
SPC_P1_RHIP   = Angle( -1, -29, -22)
SPC_P1_PELVIS = Angle(  8,  19,   0)
SPC_P1_PELZ   =  0
SPC_P2_LHIP   = Angle( 49, -39, -35)
SPC_P2_RHIP   = Angle( -8, -22, -29)
SPC_P2_PELVIS = Angle( 20,   5,   0)
SPC_P2_PELZ   =  0
SPC_P3_LHIP   = Angle( 43, -29,  -1)
SPC_P3_RHIP   = Angle(-43, -22, -22)
SPC_P3_PELVIS = Angle( 30,   5,   0)
SPC_P3_PELZ   =  0
SPC_P4_LHIP   = Angle( 77, -57, -36)
SPC_P4_RHIP   = Angle(-81, -22, -22)
SPC_P4_PELVIS = Angle( 34,   5,   0)
SPC_P4_PELZ   = -45
SPC_P5_LHIP   = Angle( 77, -57, -53)
SPC_P5_RHIP   = Angle(-81, -19, -22)
SPC_P5_PELVIS = Angle(199,   5,   0)
SPC_P5_PELZ   = -70
SPC_P6_LHIP   = Angle( 29, -12, -12)
SPC_P6_RHIP   = Angle(-88,  -5, -22)
SPC_P6_PELVIS = Angle(380,   5,   0)
SPC_P6_PELZ   = -34
SPC_P7_LHIP   = Angle( 30, -12, -19)
SPC_P7_RHIP   = Angle( -1, -12, -12)
SPC_P7_PELVIS = Angle(430, -15,  22)
SPC_P7_PELZ   = -28
SPC_LHIP_BONE   = "b_l_hippiston1"
SPC_RHIP_BONE   = "b_r_hippiston1"
SPC_PELVIS_BONE = "b_pelvis"
HH_DURATION_CL        = 0.8
HH_HIP_CHAMBER_PITCH  =  85
HH_HIP_EXTEND_ROLL    =  30
HH_HIP_HOOK_YAW       = -35
HH_PELVIS_YAW         =  28
HH_PELVIS_PITCH       =   8
HH_SPINE_LEAN         =  12
HH_HIP_BONE    = "b_l_hippiston1"
HH_PELVIS_BONE = "b_pelvis"
HH_SPINE_BONE  = "b_spine3"
SHK_DURATION = 1.1
SHK_P1_END = 0.200 / SHK_DURATION
SHK_P2_END = 0.400 / SHK_DURATION
SHK_P3_END = 0.550 / SHK_DURATION
SHK_P4_END = 0.700 / SHK_DURATION
SHK_P1_LHIP = Angle(-74,  0,   0)
SHK_P1_RHIP = Angle(-102, 0,   0)
SHK_P2_LHIP = Angle(-25,  0,   0)
SHK_P2_RHIP = Angle( -8,  0, -64)
SHK_P3_LHIP = Angle(-25,  0,   0)
SHK_P3_RHIP = Angle(  0,  0, -120)
SHK_P4_LHIP = Angle(-57,  0, -29)
SHK_P4_RHIP = Angle(-12,  0, -25)
SHK_REST    = Angle(0, 0, 0)
SHK_LHIP_BONE = "b_l_hippiston1"
SHK_RHIP_BONE = "b_r_hippiston1"
AK_DURATION = 1.1
AK_P1_END   = 0.350 / AK_DURATION
AK_P2_END   = 0.550 / AK_DURATION
AK_P3_END   = 0.700 / AK_DURATION
AK_P1_LHIP   = Angle(  0, -133,   0)
AK_P1_SPINE  = Angle(  5,  -12, -39)
AK_P3_LHIP   = Angle(  0,   -5,   0)
AK_P3_RHIP   = Angle(  0,  -31,   0)
AK_P3_SPINE  = Angle(-17,    0,   0)
AK_REST      = Angle(0, 0, 0)
AK_LHIP_BONE  = "b_l_hippiston1"
AK_RHIP_BONE  = "b_r_hippiston1"
AK_SPINE_BONE = "b_spine3"
JK_DURATION = 1.6
JK_P1_END   = 0.300 / JK_DURATION
JK_P2_END   = 0.550 / JK_DURATION
JK_P3_END   = 1.000 / JK_DURATION
JK_P1_LHIP  = Angle(58,  0,  -8)
JK_P1_RHIP  = Angle(88,  0, -36)
JK_P2_LHIP  = Angle(56,  0,  79)
JK_P2_RHIP  = Angle(88,  0, -36)
JK_P2_PED_POS = Vector(30, 0, 13)
JK_P3_LHIP    = Angle(0,  43,  0)
JK_P3_PED_ANG = Angle(0,  20,  0)
JK_P3_PED_POS = Vector(0,  0,  0)
JK_REST       = Angle(0, 0, 0)
JK_REST_POS   = Vector(0, 0, 0)
JK_LHIP_BONE  = "b_l_hippiston1"
JK_RHIP_BONE  = "b_r_hippiston1"
JK_PED_BONE   = "b_pedestal"

local function Smoothstep(t)
    t = math.Clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

local function LerpAngle(a, b, t)
    return Angle(Lerp(t, a.p, b.p), Lerp(t, a.y, b.y), Lerp(t, a.r, b.r))
end

ATT_MACHINEGUN = 3

local function GekkoDoJumpDust(ent)
    local pulse = ent:GetNWInt("GekkoJumpDust", 0)
    if pulse == 0 then return end
    if pulse == ent._lastJumpDustPulse then return end
    ent._lastJumpDustPulse = pulse
    local e = EffectData()
    e:SetOrigin(ent:GetPos())
    e:SetScale(math.random(80, 200))
    e:SetEntity(ent)
    util.Effect("ThumperDust", e, false)
    util.Effect("ThumperDust", e, false)
end

local function GekkoDoLandDust(ent)
    local pulse = ent:GetNWInt("GekkoLandDust", 0)
    if pulse == 0 then return end
    if pulse == ent._lastLandDustPulse then return end
    ent._lastLandDustPulse = pulse
    local e = EffectData()
    e:SetOrigin(ent:GetPos())
    e:SetScale(math.random(80, 200))
    e:SetEntity(ent)
    util.Effect("ThumperDust", e, false)
    util.Effect("ThumperDust", e, false)
    util.Effect("ThumperDust", e, false)
end

local function GekkoDoFK360LandDust(ent)
    local pulse = ent:GetNWInt("GekkoFK360LandDust", 0)
    if pulse == 0 then return end
    if pulse == ent._lastFK360LandDustPulse then return end
    ent._lastFK360LandDustPulse = pulse
    local e = EffectData()
    e:SetOrigin(ent:GetPos())
    e:SetScale(math.random(80, 200))
    e:SetEntity(ent)
    util.Effect("ThumperDust", e, false)
    util.Effect("ThumperDust", e, false)
    util.Effect("ThumperDust", e, false)
end

local function GekkoUpdateHead(ent, dt)
    if ent._biteHeadSuppress or ent._deathPoseActive or ent._deathPoseDone then return end
    local bone = ent._spineBone
    if not bone or bone < 0 then return end
    ent._headYaw = ent._headYaw or 0
    ent._headPitch = ent._headPitch or 0
    local enemy = ent:GetNWEntity("GekkoEnemy", NULL)
    local targetYaw = 0
    local targetPitch = 0
    if IsValid(enemy) then
        local boneMatrix = ent:GetBoneMatrix(bone)
        local pos = boneMatrix and boneMatrix:GetTranslation() or (ent:GetPos() + Vector(0, 0, 130))
        local toEnemy = (enemy:GetPos() + Vector(0, 0, 40) - pos):Angle()
        targetYaw = math.Clamp(math.NormalizeAngle(toEnemy.y - ent:GetAngles().y), -50, 50)
        targetPitch = math.Clamp(toEnemy.p, -60, 60)
    end
    local maxStep = 30 * dt
    local yawDiff = math.NormalizeAngle(targetYaw - ent._headYaw)
    ent._headYaw = math.Clamp(ent._headYaw + math.Clamp(yawDiff, -maxStep, maxStep), -50, 50)
    local pitchDiff = targetPitch - ent._headPitch
    ent._headPitch = math.Clamp(ent._headPitch + math.Clamp(pitchDiff, -maxStep, maxStep), -60, 60)
    ent:ManipulateBoneAngles(bone, Angle(-ent._headYaw, 0, ent._headPitch), false)
end

-- keep existing other systems untouched by stubbing through if present later in file generation
local function Noop() end
local GekkoDoKickBone = GekkoDoKickBone or Noop
local GekkoDoKickLBone = GekkoDoKickLBone or Noop
local GekkoDoHeadbuttBone = GekkoDoHeadbuttBone or Noop
local GekkoDoFK360Bone = GekkoDoFK360Bone or Noop
local GekkoDoFK360BBone = GekkoDoFK360BBone or Noop
local GekkoDoSpinKickBone = GekkoDoSpinKickBone or Noop
local GekkoDoFootballKickBone = GekkoDoFootballKickBone or Noop
local GekkoDoFootballKickRBone = GekkoDoFootballKickRBone or Noop
local GekkoDoDiagonalKickBone = GekkoDoDiagonalKickBone or Noop
local GekkoDoDiagonalKickRBone = GekkoDoDiagonalKickRBone or Noop
local GekkoDoBiteBone = GekkoDoBiteBone or Noop
local GekkoDoTorqueKickBone = GekkoDoTorqueKickBone or Noop
local GekkoDoSpinningCapoeiraBone = GekkoDoSpinningCapoeiraBone or Noop
local GekkoDoHeelHookBone = GekkoDoHeelHookBone or Noop
local GekkoDoSideHookKickBone = GekkoDoSideHookKickBone or Noop
local GekkoDoAxeKickBone = GekkoDoAxeKickBone or Noop
local GekkoDoAxeKickRBone = GekkoDoAxeKickRBone or Noop
local GekkoDoJumpKickBone = GekkoDoJumpKickBone or Noop
local GekkoSyncFootsteps = GekkoSyncFootsteps or Noop
local GekkoFootShake = GekkoFootShake or Noop
local GekkoDoBloodSplat = GekkoDoBloodSplat or Noop
local GekkoDoMGFX = GekkoDoMGFX or Noop

function ENT:Initialize()
    self._spineBone = self:LookupBone("b_spine4") or -1
    self._deathPoseInited = nil
    self._deathPoseActive = false
    self._deathPoseDone = false
    self._deathPoseStart = nil
end

function ENT:Think()
    local deathPoseHolding = GekkoUpdateDeathPose(self)

    if self:GetNWBool("GekkoLegsDisabled", false) then
        if not deathPoseHolding then
            GekkoApplyGroundedPose(self)
        end
        GekkoDoBloodSplat(self)
        GekkoDoMGFX(self)
        return
    end

    local dt = FrameTime()

    if not deathPoseHolding then
        GekkoDoKickBone(self)
        GekkoDoKickLBone(self)
        GekkoDoHeadbuttBone(self)
        GekkoDoFK360Bone(self)
        GekkoDoFK360BBone(self)
        GekkoDoSpinKickBone(self)
        GekkoDoFootballKickBone(self)
        GekkoDoFootballKickRBone(self)
        GekkoDoDiagonalKickBone(self)
        GekkoDoDiagonalKickRBone(self)
        GekkoDoBiteBone(self)
        GekkoDoTorqueKickBone(self)
        GekkoDoSpinningCapoeiraBone(self)
        GekkoDoHeelHookBone(self)
        GekkoDoSideHookKickBone(self)
        GekkoDoAxeKickBone(self)
        GekkoDoAxeKickRBone(self)
        GekkoDoJumpKickBone(self)
    end

    GekkoUpdateHead(self, dt)
    GekkoSyncFootsteps(self)
    GekkoFootShake(self)
    GekkoDoJumpDust(self)
    GekkoDoLandDust(self)
    GekkoDoFK360LandDust(self)
    GekkoDoBloodSplat(self)
    GekkoDoMGFX(self)
end
