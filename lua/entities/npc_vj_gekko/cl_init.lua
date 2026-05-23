include("shared.lua")
include("elastic_cl.lua")
include("muzzleflash_system.lua")
include("bullet_impact_system.lua")
include("hit_react_cl.lua")
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
--  FK360B ANIMATION (FL360B 5-step variant)
--  Steps:
--    1) Preparation: pedestal roll, right hip piston wind-up.
--    2) Elongation: pelvis Z up to 43.
--    3) Spin: identical envelope & duration as FK360, damage pulses unchanged.
--    4) Land: pelvis Z settles to 22.
--    5) Smooth restore: pelvis / pedestal / piston return to neutral without a
--       second counter-spin.
-- ============================================================
FK360B_PED_BONE      = "b_pedestal"
FK360B_PISTON_BONE   = "b_r_hippiston1"
FK360B_PEL_BONE      = "b_pelvis"

FK360B_PREP_DUR      = 0.30
FK360B_ELONGATE_DUR  = 0.20
FK360B_LAND_DUR      = 0.30
FK360B_RESTORE_DUR   = 0.25

FK360B_PEL_Z_ELONGATE = 43
FK360B_PEL_Z_LAND     = 22

FK360B_PED_ROLL       = 12   -- pedestal Angle(?, ?, 12)
FK360B_PISTON_PITCH   = 15   -- pistonR Angle(15, -8, ?)
FK360B_PISTON_YAW     = -8

-- ============================================================
--  SPINKICK ANIMATION
-- ============================================================
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

-- ============================================================
--  FOOTBALL KICK ANIMATION  (left leg)
-- ============================================================
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

-- ============================================================
--  FOOTBALL KICK MIRRORED ANIMATION  (right leg)
-- ============================================================
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

-- ============================================================
--  DIAGONAL KICK ANIMATION
-- ============================================================
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

-- ============================================================
--  DIAGONAL KICK R ANIMATION  (right-leg primary variant)
--  Same tempo as DiagonalKick; three distinct strike keyframes
--  before the final return phase.
--
--  Step 1: initial chamber
--    L(-36,-29, 43)  R( 12,-22,  15)
--  Step 2: mid-extension
--    L(-70,-29, 43)  R(  8, -5,-105)
--  Step 3: peak strike
--    L(-143,-29,43)  R(-105, -5, -12)
--  Step 4: return to REST
-- ============================================================
DGKR_DURATION = 1.0
DGKR_P1_END   = 0.300 / DGKR_DURATION   -- ramp in → step 1
DGKR_P2_END   = 0.500 / DGKR_DURATION   -- hold at step 1 → step 2
DGKR_P3_END   = 0.700 / DGKR_DURATION   -- step 2 → step 3 peak
DGKR_P4_END   = 0.920 / DGKR_DURATION   -- step 3 peak → return

-- step 1 — initial chamber
DGKR_P1_LHIP  = Angle( -36, -29,   43)
DGKR_P1_RHIP  = Angle(  12, -22,   15)
-- step 2 — mid-extension
DGKR_P2_LHIP  = Angle( -70, -29,   43)
DGKR_P2_RHIP  = Angle(   8,  -5, -105)
-- step 3 — peak strike
DGKR_P3_LHIP  = Angle(-143, -29,   43)
DGKR_P3_RHIP  = Angle(-105,  -5,  -12)

DGKR_LHIP_BONE = "b_l_hippiston1"
DGKR_RHIP_BONE = "b_r_hippiston1"

-- ============================================================
--  BITE ANIMATION
--  5-phase forward lunge.  Two bones not specified in a given
--  phase hold their previous keyframe value (see driver below).
--
--  Phase 0 — wind-up
--    L( 46,-15, 15)  R(-25,  0,-25)
--    pelvis REST      spine4 REST
--  Phase 1 — head charges backward (preparation)
--    L( 46, 12, 19)  R(-22, 29, -8)
--    pelvis(  0,-32,  0)  spine4 REST
--  Phase 2 — body lean / spine charge
--    L  hold P1       R  hold P1
--    pelvis( -5, 15,  5)  spine4(-19, 50,102)
--  Phase 3 — full bite strike
--    L( -1,-36, 19)  R(-22,-22, -8)
--    pelvis( 53, 50,129)  spine4 holds P2
--  Phase 4 — smooth return to REST
-- ============================================================
BITE_DURATION = 1.5
BITE_P0_END   = 0.200 / BITE_DURATION   -- ramp in         → phase 0 wind-up
BITE_P1_END   = 0.480 / BITE_DURATION   -- phase 0         → phase 1 head-back
BITE_P2_END   = 0.580 / BITE_DURATION   -- phase 1         → phase 2 body lean
BITE_P3_END   = 0.780 / BITE_DURATION   -- phase 2         → phase 3 full strike
BITE_P4_END   = 1.100 / BITE_DURATION   -- phase 3         → return (REST tail follows)

-- phase 0 — wind-up
BITE_P0_LHIP   = Angle(  46, -15,  15)
BITE_P0_RHIP   = Angle( -25,   0, -25)
BITE_P0_PELVIS = Angle(   0,   0,   0)
BITE_P0_SPINE4 = Angle(   0,   0,   0)

-- phase 1 — head charges backward
BITE_P1_LHIP   = Angle(  46,  12,  19)
BITE_P1_RHIP   = Angle( -22,  29,  -8)
BITE_P1_PELVIS = Angle(   0, -32,   0)   -- x and z hold 0 from phase 0
BITE_P1_SPINE4 = Angle(   0,   0,   0)   -- spine4 unchanged

-- phase 2 — body lean  (hips hold phase-1 values; see driver)
BITE_P2_PELVIS = Angle(  -5,  15,   5)
BITE_P2_SPINE4 = Angle( -19,  50, 102)

-- phase 3 — full bite strike  (spine4 holds phase-2 value; see driver)
BITE_P3_LHIP   = Angle(  -1, -36,  19)
BITE_P3_RHIP   = Angle( -22, -22,  -8)
BITE_P3_PELVIS = Angle(  53,  50, 129)
-- BITE_P3_SPINE4 holds BITE_P2_SPINE4 (see driver)

BITE_LHIP_BONE  = "b_l_hippiston1"
BITE_RHIP_BONE  = "b_r_hippiston1"
BITE_PELVIS_BONE = "b_pelvis"
BITE_SPINE4_BONE = "b_spine4"

-- ============================================================
--  TAIL-KICK ANIMATION  (TK)
--  Phase 0  wind-up    L( 46,  22, 12) R(-25,  0,-19)
--  Phase 1  coil       L( 22,  38, 19) R( -8, 29,  0)
--  Phase 2  lash       L(-25, -38, 12) R(-22,-22, -8)
--  Phase 3  return     REST
-- ============================================================
TK_DURATION = 1.2
TK_P0_END   = 0.220 / TK_DURATION
TK_P1_END   = 0.450 / TK_DURATION
TK_P2_END   = 0.680 / TK_DURATION
TK_P3_END   = 0.900 / TK_DURATION

TK_P0_LHIP  = Angle( 46,  22,  12)
TK_P0_RHIP  = Angle(-25,   0, -19)
TK_P1_LHIP  = Angle( 22,  38,  19)
TK_P1_RHIP  = Angle( -8,  29,   0)
TK_P2_LHIP  = Angle(-25, -38,  12)
TK_P2_RHIP  = Angle(-22, -22,  -8)

TK_LHIP_BONE = "b_l_hippiston1"
TK_RHIP_BONE = "b_r_hippiston1"

-- ============================================================
--  STOMP ANIMATION  (SPC)
-- ============================================================
SPC_DURATION = 1.1
SPC_P0_END   = 0.180 / SPC_DURATION
SPC_P1_END   = 0.400 / SPC_DURATION
SPC_P2_END   = 0.620 / SPC_DURATION
SPC_P3_END   = 0.850 / SPC_DURATION

SPC_P0_LHIP  = Angle( 19,  12, -8)
SPC_P0_RHIP  = Angle(-12,   0, 22)
SPC_P1_LHIP  = Angle(-22,  -8, 36)
SPC_P1_RHIP  = Angle( 29, -19,  0)
SPC_P2_LHIP  = Angle( 85,  22, 36)
SPC_P2_RHIP  = Angle(-19,  -8,  0)

SPC_LHIP_BONE = "b_l_hippiston1"
SPC_RHIP_BONE = "b_r_hippiston1"

-- ============================================================
-- GEKKO CLIENT-SIDE ENTITY
-- ============================================================
ENT.Type           = "anim"
ENT.PrintName      = "Gekko Client"
ENT.RenderGroup    = RENDERGROUP_BOTH

function ENT:Initialize()
    self._hipDriver          = nil

    -- jump
    self._jumpState          = JUMP_NONE
    self._jumpYOffset        = 0
    self._jumpYaw            = 0
    self._lastLandTime       = -9999

    -- kick
    self._kickActive         = false
    self._kickEndTime        = 0
    self._kickL_Active       = false
    self._kickL_EndTime      = 0

    -- headbutt
    self._hbActive           = false
    self._hbStartTime        = 0
    self._hbDuration         = HB_DURATION

    -- FK360
    self._fk360Active        = false
    self._fk360StartTime     = 0
    self._fk360Duration      = 0
    self._fk360YawOffset     = 0
    self._fk360BaseYaw       = 0

    -- FK360B
    self._fk360BActive       = false
    self._fk360BStartTime    = 0
    self._fk360BTotalDur     = 0
    self._fk360BSpinDur      = 0
    self._fk360BPhase        = "prep"
    self._fk360BYawOffset    = 0
    self._fk360BBaseYaw      = 0

    -- spinkick
    self._skActive           = false
    self._skStartTime        = 0
    self._skDuration         = SK_DURATION
    self._skYawOffset        = 0
    self._skBaseYaw          = 0

    -- football kick L
    self._fkActive           = false
    self._fkStartTime        = 0
    self._fkDuration         = FK_DURATION

    -- football kick R
    self._fkrActive          = false
    self._fkrStartTime       = 0
    self._fkrDuration        = FKR_DURATION

    -- diagonal kick L
    self._dgkActive          = false
    self._dgkStartTime       = 0
    self._dgkDuration        = DGK_DURATION

    -- diagonal kick R
    self._dgkrActive         = false
    self._dgkrStartTime      = 0
    self._dgkrDuration       = DGKR_DURATION

    -- bite
    self._biteActive         = false
    self._biteStartTime      = 0
    self._biteDuration       = BITE_DURATION

    -- tail-kick
    self._tkActive           = false
    self._tkStartTime        = 0
    self._tkDuration         = TK_DURATION

    -- stomp
    self._spcActive          = false
    self._spcStartTime       = 0
    self._spcDuration        = SPC_DURATION
end

-- ============================================================
-- LERP HELPERS
-- ============================================================
local function lerpAng(t, a, b)
    return LerpAngle(math.Clamp(t, 0, 1), a, b)
end

local function easeInOut(t)
    return t * t * (3 - 2 * t)
end

-- ============================================================
-- KICK DRIVER
-- ============================================================
local REST_HIP = Angle(0, 0, 0)

local function GekkoKickDriver(ent)
    -- Right kick
    if ent._kickActive then
        local t = (CurTime() - ent._kickStartTime) / ent._kickWindow
        if t > 1 then
            ent._kickActive = false
            SetBoneAng(ent, KICK_BONE_NAME, KICK_BONE_RESET)
        else
            local ang
            if t < 0.4 then
                ang = lerpAng(t / 0.4, KICK_BONE_RESET, KICK_BONE_ANGLE)
            else
                ang = lerpAng((t - 0.4) / 0.6, KICK_BONE_ANGLE, KICK_BONE_RESET)
            end
            SetBoneAng(ent, KICK_BONE_NAME, ang)
        end
    end
    -- Left kick
    if ent._kickL_Active then
        local t = (CurTime() - ent._kickL_StartTime) / ent._kickWindow
        if t > 1 then
            ent._kickL_Active = false
            SetBoneAng(ent, KICK_L_BONE_NAME, KICK_L_BONE_RESET)
        else
            local ang
            if t < 0.4 then
                ang = lerpAng(t / 0.4, KICK_L_BONE_RESET, KICK_L_BONE_ANGLE)
            else
                ang = lerpAng((t - 0.4) / 0.6, KICK_L_BONE_ANGLE, KICK_L_BONE_RESET)
            end
            SetBoneAng(ent, KICK_L_BONE_NAME, ang)
        end
    end
end

-- ============================================================
-- HEADBUTT DRIVER
-- ============================================================
local function GekkoHeadbuttDriver(ent)
    if not ent._hbActive then return end

    local elapsed = CurTime() - ent._hbStartTime
    local active  = elapsed >= 0 and elapsed < ent._hbDuration
    if not active then
        ent._hbActive = false
        if ClaimHips(ent, "headbutt") then
            SetBoneAng(ent, HB_SPINE3_BONE,  Angle(0, 0, 0))
            SetBonePos(ent, HB_PEDESTAL_BONE, Vector(0, 0, 0))
            ReleaseHips(ent, "headbutt")
        end
        return
    end

    if not ClaimHips(ent, "headbutt") then return end

    local t   = elapsed / ent._hbDuration
    local fwd
    if t < HB_PEAK then
        fwd = easeInOut(t / HB_PEAK)
    else
        fwd = 1 - easeInOut((t - HB_PEAK) / (1 - HB_PEAK))
    end

    SetBoneAng(ent, HB_SPINE3_BONE, Angle(HB_SPINE3_ANG_X * fwd, 0, 0))
    SetBonePos(ent, HB_PEDESTAL_BONE,
        Vector(HB_PEDESTAL_POS_X * fwd, 0, HB_PEDESTAL_POS_Z * fwd))
end

-- ============================================================
-- FK360 DRIVER
-- ============================================================
local function GekkoFK360Driver(ent)
    if not ent._fk360Active then return end

    local elapsed = CurTime() - ent._fk360StartTime
    local active  = elapsed >= 0 and elapsed < ent._fk360Duration
    if not active then
        ent._fk360Active = false
        if ClaimHips(ent, "fk360") then
            SetBoneAng(ent, FK360_BONE, Angle(0, 0, 0))
            ReleaseHips(ent, "fk360")
        end
        return
    end

    if not ClaimHips(ent, "fk360") then return end

    local t = elapsed / ent._fk360Duration
    local yawFrac
    if t < FK360_RAMP then
        yawFrac = easeInOut(t / FK360_RAMP)
    elseif t > (1 - FK360_RAMP) then
        yawFrac = 1 - easeInOut((t - (1 - FK360_RAMP)) / FK360_RAMP)
    else
        yawFrac = 1
    end

    local fullYaw = 360 * (elapsed / ent._fk360Duration)
    ent._fk360YawOffset = fullYaw * yawFrac
    SetBoneAng(ent, FK360_BONE, Angle(0, ent._fk360YawOffset, 0))
end

-- ============================================================
-- FK360B DRIVER
-- ============================================================
local function GekkoFK360BDriver(ent)
    if not ent._fk360BActive then return end

    local elapsed = CurTime() - ent._fk360BStartTime
    local active  = elapsed >= 0 and elapsed < ent._fk360BTotalDur
    if not active then
        ent._fk360BActive = false
        if ClaimHips(ent, "fk360b") then
            SetBoneAng(ent, FK360B_PED_BONE,    Angle(0, 0, 0))
            SetBoneAng(ent, FK360B_PISTON_BONE, Angle(0, 0, 0))
            SetBoneAng(ent, FK360B_PEL_BONE,    Angle(0, 0, 0))
            ReleaseHips(ent, "fk360b")
        end
        return
    end

    if not ClaimHips(ent, "fk360b") then return end

    local t   = elapsed / ent._fk360BTotalDur
    local spinDur = ent._fk360BSpinDur
    local prepEnd = FK360B_PREP_DUR / ent._fk360BTotalDur
    local elongEnd = prepEnd + FK360B_ELONGATE_DUR / ent._fk360BTotalDur
    local spinEnd = elongEnd + spinDur / ent._fk360BTotalDur
    local landEnd = spinEnd + FK360B_LAND_DUR / ent._fk360BTotalDur

    if t <= prepEnd then
        local pt = t / prepEnd
        local ef = easeInOut(pt)
        SetBoneAng(ent, FK360B_PED_BONE,    Angle(0, 0, FK360B_PED_ROLL * ef))
        SetBoneAng(ent, FK360B_PISTON_BONE, Angle(FK360B_PISTON_PITCH * ef, FK360B_PISTON_YAW * ef, 0))
        SetBoneAng(ent, FK360B_PEL_BONE,    Angle(0, 0, 0))
    elseif t <= elongEnd then
        local et = (t - prepEnd) / (elongEnd - prepEnd)
        local ef = easeInOut(et)
        SetBoneAng(ent, FK360B_PEL_BONE,    Angle(0, 0, 0))
        SetBonePos(ent, FK360B_PEL_BONE,    Vector(0, 0, FK360B_PEL_Z_ELONGATE * ef))
    elseif t <= spinEnd then
        local st = (t - elongEnd) / (spinEnd - elongEnd)
        local yawFrac
        if st < FK360_RAMP then
            yawFrac = easeInOut(st / FK360_RAMP)
        elseif st > (1 - FK360_RAMP) then
            yawFrac = 1 - easeInOut((st - (1 - FK360_RAMP)) / FK360_RAMP)
        else
            yawFrac = 1
        end
        local fullYaw = 360 * st
        ent._fk360BYawOffset = fullYaw * yawFrac
        SetBoneAng(ent, FK360B_PEL_BONE, Angle(0, ent._fk360BYawOffset, 0))
        SetBonePos(ent, FK360B_PEL_BONE, Vector(0, 0, FK360B_PEL_Z_ELONGATE))
    elseif t <= landEnd then
        local lt = (t - spinEnd) / (landEnd - spinEnd)
        local lf = easeInOut(lt)
        local pelZ = FK360B_PEL_Z_ELONGATE + (FK360B_PEL_Z_LAND - FK360B_PEL_Z_ELONGATE) * lf
        SetBoneAng(ent, FK360B_PEL_BONE, Angle(0, 0, 0))
        SetBonePos(ent, FK360B_PEL_BONE, Vector(0, 0, pelZ))
    else
        local rt = (t - landEnd) / (1 - landEnd)
        local rf = easeInOut(rt)
        local pelZ = FK360B_PEL_Z_LAND * (1 - rf)
        SetBoneAng(ent, FK360B_PED_BONE,    lerpAng(rf, Angle(0, 0, FK360B_PED_ROLL), Angle(0, 0, 0)))
        SetBoneAng(ent, FK360B_PISTON_BONE, lerpAng(rf, Angle(FK360B_PISTON_PITCH, FK360B_PISTON_YAW, 0), Angle(0, 0, 0)))
        SetBoneAng(ent, FK360B_PEL_BONE,    Angle(0, 0, 0))
        SetBonePos(ent, FK360B_PEL_BONE,    Vector(0, 0, pelZ))
    end
end

-- ============================================================
-- SPINKICK DRIVER
-- ============================================================
local function GekkoSpinkickDriver(ent)
    if not ent._skActive then return end

    local elapsed = CurTime() - ent._skStartTime
    local active  = elapsed >= 0 and elapsed < ent._skDuration
    if not active then
        ent._skActive = false
        if ClaimHips(ent, "spinkick") then
            SetBoneAng(ent, SK_PED_BONE,  Angle(0, 0, 0))
            SetBoneAng(ent, SK_PEL_BONE,  Angle(0, 0, 0))
            SetBoneAng(ent, SK_HIP_BONE,  Angle(0, 0, 0))
            SetBoneAng(ent, SK_ULEG_BONE, Angle(0, 0, 0))
            ReleaseHips(ent, "spinkick")
        end
        return
    end

    if not ClaimHips(ent, "spinkick") then return end

    local t = elapsed / ent._skDuration

    -- Phase 1: drop pelvis and chamber right leg
    if t <= SK_P1_END then
        local pt = t / SK_P1_END
        local ef = easeInOut(pt)
        SetBoneAng(ent, SK_PEL_BONE,  Angle(0, 0, SK_PEL_DROP * ef))
        SetBoneAng(ent, SK_HIP_BONE,  Angle(0, 0, SK_HIP_Z * ef))
        SetBoneAng(ent, SK_ULEG_BONE, Angle(SK_ULEG_X * ef, 0, 0))
    -- Phase 2: spin + kick
    elseif t <= SK_P2_END then
        local st = (t - SK_P1_END) / (SK_P2_END - SK_P1_END)
        local yawFrac
        if st < SK_RAMP then
            yawFrac = easeInOut(st / SK_RAMP)
        elseif st > (1 - SK_RAMP) then
            yawFrac = 1 - easeInOut((st - (1 - SK_RAMP)) / SK_RAMP)
        else
            yawFrac = 1
        end
        ent._skYawOffset = SK_YAW_TOTAL * st * yawFrac
        SetBoneAng(ent, SK_PED_BONE,  Angle(0, ent._skYawOffset, 0))
        SetBoneAng(ent, SK_ULEG_BONE, Angle(SK_ULEG_X, 0, 0))
    -- Phase 3: extend kick
    elseif t <= SK_P3_END then
        local et = (t - SK_P2_END) / (SK_P3_END - SK_P2_END)
        SetBoneAng(ent, SK_ULEG_BONE, lerpAng(easeInOut(et), Angle(SK_ULEG_X, 0, 0), Angle(0, 0, 0)))
    -- Phase 4: return
    elseif t <= SK_P4_END then
        local rt = (t - SK_P3_END) / (SK_P4_END - SK_P3_END)
        local rf = easeInOut(rt)
        SetBoneAng(ent, SK_PED_BONE,  lerpAng(rf, Angle(0, ent._skYawOffset or 0, 0), Angle(0, 0, 0)))
        SetBoneAng(ent, SK_PEL_BONE,  lerpAng(rf, Angle(0, 0, SK_PEL_DROP), Angle(0, 0, 0)))
        SetBoneAng(ent, SK_HIP_BONE,  lerpAng(rf, Angle(0, 0, SK_HIP_Z), Angle(0, 0, 0)))
    else
        local ft = (t - SK_P4_END) / (1 - SK_P4_END)
        local ff = easeInOut(ft)
        SetBoneAng(ent, SK_PED_BONE,  lerpAng(ff, Angle(0, 0, 0), Angle(0, 0, 0)))
    end
end

-- ============================================================
-- FOOTBALL KICK DRIVER (left)
-- ============================================================
local function GekkoFootballKickDriver(ent)
    if not ent._fkActive then return end

    local elapsed = CurTime() - ent._fkStartTime
    local active  = elapsed >= 0 and elapsed < ent._fkDuration
    if not active then
        ent._fkActive = false
        if ClaimHips(ent, "fk") then
            SetBoneAng(ent, FK_LHIP_BONE, Angle(0, 0, 0))
            SetBoneAng(ent, FK_RHIP_BONE, Angle(0, 0, 0))
            ReleaseHips(ent, "fk")
        end
        return
    end

    if not ClaimHips(ent, "fk") then return end

    local t = elapsed / ent._fkDuration

    if t < FK_PHASE_HOLD then
        local pt = t / FK_PHASE_HOLD
        local ef = easeInOut(pt)
        SetBoneAng(ent, FK_LHIP_BONE, Angle(FK_LHIP_X_PREP * ef, FK_LHIP_Y_PREP * ef, 0))
        SetBoneAng(ent, FK_RHIP_BONE, Angle(FK_RHIP_X_PREP * ef, 0, 0))
    elseif t < FK_PHASE_EXTEND then
        local et = (t - FK_PHASE_HOLD) / (FK_PHASE_EXTEND - FK_PHASE_HOLD)
        local ef = easeInOut(et)
        local lhipY = FK_LHIP_Y_PREP + (FK_LHIP_Y_EXT - FK_LHIP_Y_PREP) * ef
        SetBoneAng(ent, FK_LHIP_BONE, Angle(FK_LHIP_X_PREP, lhipY, 0))
        SetBoneAng(ent, FK_RHIP_BONE, Angle(FK_RHIP_X_PREP, 0, 0))
    elseif t < FK_PHASE_RECOVER then
        local rt = (t - FK_PHASE_EXTEND) / (FK_PHASE_RECOVER - FK_PHASE_EXTEND)
        local rf = easeInOut(rt)
        SetBoneAng(ent, FK_LHIP_BONE, lerpAng(rf, Angle(FK_LHIP_X_PREP, FK_LHIP_Y_EXT, 0), Angle(0, 0, 0)))
        SetBoneAng(ent, FK_RHIP_BONE, lerpAng(rf, Angle(FK_RHIP_X_PREP, 0, 0), Angle(0, 0, 0)))
    else
        local ft = (t - FK_PHASE_RECOVER) / (1 - FK_PHASE_RECOVER)
        local ff = easeInOut(ft)
        SetBoneAng(ent, FK_LHIP_BONE, lerpAng(ff, Angle(0, 0, 0), Angle(0, 0, 0)))
        SetBoneAng(ent, FK_RHIP_BONE, lerpAng(ff, Angle(0, 0, 0), Angle(0, 0, 0)))
    end
end

-- ============================================================
-- FOOTBALL KICK MIRRORED DRIVER (right)
-- ============================================================
local function GekkoFootballKickRDriver(ent)
    if not ent._fkrActive then return end

    local elapsed = CurTime() - ent._fkrStartTime
    local active  = elapsed >= 0 and elapsed < ent._fkrDuration
    if not active then
        ent._fkrActive = false
        if ClaimHips(ent, "fkr") then
            SetBoneAng(ent, FKR_RHIP_BONE, Angle(0, 0, 0))
            SetBoneAng(ent, FKR_LHIP_BONE, Angle(0, 0, 0))
            ReleaseHips(ent, "fkr")
        end
        return
    end

    if not ClaimHips(ent, "fkr") then return end

    local t = elapsed / ent._fkrDuration

    if t < FKR_PHASE_HOLD then
        local pt = t / FKR_PHASE_HOLD
        local ef = easeInOut(pt)
        SetBoneAng(ent, FKR_RHIP_BONE, Angle(FKR_RHIP_X_PREP * ef, FKR_RHIP_Y_PREP * ef, 0))
        SetBoneAng(ent, FKR_LHIP_BONE, Angle(FKR_LHIP_X_PREP * ef, 0, 0))
    elseif t < FKR_PHASE_EXTEND then
        local et = (t - FKR_PHASE_HOLD) / (FKR_PHASE_EXTEND - FKR_PHASE_HOLD)
        local ef = easeInOut(et)
        local rhipY = FKR_RHIP_Y_PREP + (FKR_RHIP_Y_EXT - FKR_RHIP_Y_PREP) * ef
        SetBoneAng(ent, FKR_RHIP_BONE, Angle(FKR_RHIP_X_PREP, rhipY, 0))
        SetBoneAng(ent, FKR_LHIP_BONE, Angle(FKR_LHIP_X_PREP, 0, 0))
    elseif t < FKR_PHASE_RECOVER then
        local rt = (t - FKR_PHASE_EXTEND) / (FKR_PHASE_RECOVER - FKR_PHASE_EXTEND)
        local rf = easeInOut(rt)
        SetBoneAng(ent, FKR_RHIP_BONE, lerpAng(rf, Angle(FKR_RHIP_X_PREP, FKR_RHIP_Y_EXT, 0), Angle(0, 0, 0)))
        SetBoneAng(ent, FKR_LHIP_BONE, lerpAng(rf, Angle(FKR_LHIP_X_PREP, 0, 0), Angle(0, 0, 0)))
    else
        local ft = (t - FKR_PHASE_RECOVER) / (1 - FKR_PHASE_RECOVER)
        local ff = easeInOut(ft)
        SetBoneAng(ent, FKR_RHIP_BONE, lerpAng(ff, Angle(0, 0, 0), Angle(0, 0, 0)))
        SetBoneAng(ent, FKR_LHIP_BONE, lerpAng(ff, Angle(0, 0, 0), Angle(0, 0, 0)))
    end
end

-- ============================================================
-- DIAGONAL KICK DRIVER
-- ============================================================
local function GekkoDiagonalKickDriver(ent)
    if not ent._dgkActive then return end

    local elapsed = CurTime() - ent._dgkStartTime
    local active  = elapsed >= 0 and elapsed < ent._dgkDuration
    if not active then
        ent._dgkActive = false
        if ClaimHips(ent, "dgk") then
            SetBoneAng(ent, DGK_LHIP_BONE, Angle(0, 0, 0))
            SetBoneAng(ent, DGK_RHIP_BONE, Angle(0, 0, 0))
            ReleaseHips(ent, "dgk")
        end
        return
    end

    if not ClaimHips(ent, "dgk") then return end

    local t = elapsed / ent._dgkDuration

    if t <= DGK_P1_END then
        local pt = t / DGK_P1_END
        local ef = easeInOut(pt)
        SetBoneAng(ent, DGK_LHIP_BONE, lerpAng(ef, Angle(0,0,0), DGK_P1_LHIP))
        SetBoneAng(ent, DGK_RHIP_BONE, lerpAng(ef, Angle(0,0,0), DGK_P1_RHIP))
    elseif t <= DGK_P2_END then
        local st = (t - DGK_P1_END) / (DGK_P2_END - DGK_P1_END)
        -- hold P1 values
        SetBoneAng(ent, DGK_LHIP_BONE, DGK_P1_LHIP)
        SetBoneAng(ent, DGK_RHIP_BONE, DGK_P1_RHIP)
    elseif t <= DGK_P3_END then
        local et = (t - DGK_P2_END) / (DGK_P3_END - DGK_P2_END)
        local ef = easeInOut(et)
        SetBoneAng(ent, DGK_LHIP_BONE, lerpAng(ef, DGK_P1_LHIP, DGK_P3_LHIP))
        SetBoneAng(ent, DGK_RHIP_BONE, lerpAng(ef, DGK_P1_RHIP, DGK_P3_RHIP))
    elseif t <= DGK_P4_END then
        local rt = (t - DGK_P3_END) / (DGK_P4_END - DGK_P3_END)
        local rf = easeInOut(rt)
        SetBoneAng(ent, DGK_LHIP_BONE, lerpAng(rf, DGK_P3_LHIP, DGK_P4_LHIP))
        SetBoneAng(ent, DGK_RHIP_BONE, lerpAng(rf, DGK_P3_RHIP, DGK_P4_RHIP))
    else
        local ft = (t - DGK_P4_END) / (1 - DGK_P4_END)
        local ff = easeInOut(ft)
        SetBoneAng(ent, DGK_LHIP_BONE, lerpAng(ff, DGK_P4_LHIP, Angle(0,0,0)))
        SetBoneAng(ent, DGK_RHIP_BONE, lerpAng(ff, DGK_P4_RHIP, Angle(0,0,0)))
    end
end

-- ============================================================
-- DIAGONAL KICK R DRIVER
-- ============================================================
local function GekkoDiagonalKickRDriver(ent)
    if not ent._dgkrActive then return end

    local elapsed = CurTime() - ent._dgkrStartTime
    local active  = elapsed >= 0 and elapsed < ent._dgkrDuration
    if not active then
        ent._dgkrActive = false
        if ClaimHips(ent, "dgkr") then
            SetBoneAng(ent, DGKR_LHIP_BONE, Angle(0, 0, 0))
            SetBoneAng(ent, DGKR_RHIP_BONE, Angle(0, 0, 0))
            ReleaseHips(ent, "dgkr")
        end
        return
    end

    if not ClaimHips(ent, "dgkr") then return end

    local t = elapsed / ent._dgkrDuration

    if t <= DGKR_P1_END then
        local pt = t / DGKR_P1_END
        local ef = easeInOut(pt)
        SetBoneAng(ent, DGKR_LHIP_BONE, lerpAng(ef, Angle(0,0,0), DGKR_P1_LHIP))
        SetBoneAng(ent, DGKR_RHIP_BONE, lerpAng(ef, Angle(0,0,0), DGKR_P1_RHIP))
    elseif t <= DGKR_P2_END then
        local et = (t - DGKR_P1_END) / (DGKR_P2_END - DGKR_P1_END)
        local ef = easeInOut(et)
        SetBoneAng(ent, DGKR_LHIP_BONE, lerpAng(ef, DGKR_P1_LHIP, DGKR_P2_LHIP))
        SetBoneAng(ent, DGKR_RHIP_BONE, lerpAng(ef, DGKR_P1_RHIP, DGKR_P2_RHIP))
    elseif t <= DGKR_P3_END then
        local et = (t - DGKR_P2_END) / (DGKR_P3_END - DGKR_P2_END)
        local ef = easeInOut(et)
        SetBoneAng(ent, DGKR_LHIP_BONE, lerpAng(ef, DGKR_P2_LHIP, DGKR_P3_LHIP))
        SetBoneAng(ent, DGKR_RHIP_BONE, lerpAng(ef, DGKR_P2_RHIP, DGKR_P3_RHIP))
    elseif t <= DGKR_P4_END then
        local rt = (t - DGKR_P3_END) / (DGKR_P4_END - DGKR_P3_END)
        local rf = easeInOut(rt)
        SetBoneAng(ent, DGKR_LHIP_BONE, lerpAng(rf, DGKR_P3_LHIP, Angle(0,0,0)))
        SetBoneAng(ent, DGKR_RHIP_BONE, lerpAng(rf, DGKR_P3_RHIP, Angle(0,0,0)))
    else
        SetBoneAng(ent, DGKR_LHIP_BONE, Angle(0,0,0))
        SetBoneAng(ent, DGKR_RHIP_BONE, Angle(0,0,0))
    end
end

-- ============================================================
-- BITE DRIVER
-- ============================================================
local function GekkoBiteDriver(ent)
    if not ent._biteActive then return end

    local elapsed = CurTime() - ent._biteStartTime
    local active  = elapsed >= 0 and elapsed < ent._biteDuration
    if not active then
        ent._biteActive = false
        if ClaimHips(ent, "bite") then
            SetBoneAng(ent, BITE_LHIP_BONE,  Angle(0,0,0))
            SetBoneAng(ent, BITE_RHIP_BONE,  Angle(0,0,0))
            SetBoneAng(ent, BITE_PELVIS_BONE, Angle(0,0,0))
            SetBoneAng(ent, BITE_SPINE4_BONE, Angle(0,0,0))
            ReleaseHips(ent, "bite")
        end
        return
    end

    if not ClaimHips(ent, "bite") then return end

    local t = elapsed / ent._biteDuration

    if t <= BITE_P0_END then
        local pt = t / BITE_P0_END
        local ef = easeInOut(pt)
        SetBoneAng(ent, BITE_LHIP_BONE,   lerpAng(ef, Angle(0,0,0), BITE_P0_LHIP))
        SetBoneAng(ent, BITE_RHIP_BONE,   lerpAng(ef, Angle(0,0,0), BITE_P0_RHIP))
        SetBoneAng(ent, BITE_PELVIS_BONE, BITE_P0_PELVIS)
        SetBoneAng(ent, BITE_SPINE4_BONE, BITE_P0_SPINE4)
    elseif t <= BITE_P1_END then
        local et = (t - BITE_P0_END) / (BITE_P1_END - BITE_P0_END)
        local ef = easeInOut(et)
        SetBoneAng(ent, BITE_LHIP_BONE,   lerpAng(ef, BITE_P0_LHIP, BITE_P1_LHIP))
        SetBoneAng(ent, BITE_RHIP_BONE,   lerpAng(ef, BITE_P0_RHIP, BITE_P1_RHIP))
        SetBoneAng(ent, BITE_PELVIS_BONE, lerpAng(ef, BITE_P0_PELVIS, BITE_P1_PELVIS))
        SetBoneAng(ent, BITE_SPINE4_BONE, BITE_P1_SPINE4)
    elseif t <= BITE_P2_END then
        local et = (t - BITE_P1_END) / (BITE_P2_END - BITE_P1_END)
        local ef = easeInOut(et)
        -- hips hold P1
        SetBoneAng(ent, BITE_LHIP_BONE,   BITE_P1_LHIP)
        SetBoneAng(ent, BITE_RHIP_BONE,   BITE_P1_RHIP)
        SetBoneAng(ent, BITE_PELVIS_BONE, lerpAng(ef, BITE_P1_PELVIS, BITE_P2_PELVIS))
        SetBoneAng(ent, BITE_SPINE4_BONE, lerpAng(ef, BITE_P1_SPINE4, BITE_P2_SPINE4))
    elseif t <= BITE_P3_END then
        local et = (t - BITE_P2_END) / (BITE_P3_END - BITE_P2_END)
        local ef = easeInOut(et)
        SetBoneAng(ent, BITE_LHIP_BONE,   lerpAng(ef, BITE_P1_LHIP, BITE_P3_LHIP))
        SetBoneAng(ent, BITE_RHIP_BONE,   lerpAng(ef, BITE_P1_RHIP, BITE_P3_RHIP))
        SetBoneAng(ent, BITE_PELVIS_BONE, lerpAng(ef, BITE_P2_PELVIS, BITE_P3_PELVIS))
        -- spine4 holds P2
        SetBoneAng(ent, BITE_SPINE4_BONE, BITE_P2_SPINE4)
    elseif t <= BITE_P4_END then
        local rt = (t - BITE_P3_END) / (BITE_P4_END - BITE_P3_END)
        local rf = easeInOut(rt)
        SetBoneAng(ent, BITE_LHIP_BONE,   lerpAng(rf, BITE_P3_LHIP, Angle(0,0,0)))
        SetBoneAng(ent, BITE_RHIP_BONE,   lerpAng(rf, BITE_P3_RHIP, Angle(0,0,0)))
        SetBoneAng(ent, BITE_PELVIS_BONE, lerpAng(rf, BITE_P3_PELVIS, Angle(0,0,0)))
        SetBoneAng(ent, BITE_SPINE4_BONE, lerpAng(rf, BITE_P2_SPINE4, Angle(0,0,0)))
    else
        SetBoneAng(ent, BITE_LHIP_BONE,   Angle(0,0,0))
        SetBoneAng(ent, BITE_RHIP_BONE,   Angle(0,0,0))
        SetBoneAng(ent, BITE_PELVIS_BONE, Angle(0,0,0))
        SetBoneAng(ent, BITE_SPINE4_BONE, Angle(0,0,0))
    end
end

-- ============================================================
-- TAIL-KICK DRIVER
-- ============================================================
local function GekkoTailKickDriver(ent)
    if not ent._tkActive then return end

    local elapsed = CurTime() - ent._tkStartTime
    local active  = elapsed >= 0 and elapsed < ent._tkDuration
    if not active then
        ent._tkActive = false
        if ClaimHips(ent, "tk") then
            SetBoneAng(ent, TK_LHIP_BONE, Angle(0,0,0))
            SetBoneAng(ent, TK_RHIP_BONE, Angle(0,0,0))
            ReleaseHips(ent, "tk")
        end
        return
    end

    if not ClaimHips(ent, "tk") then return end

    local t = elapsed / ent._tkDuration

    if t <= TK_P0_END then
        local pt = t / TK_P0_END
        local ef = easeInOut(pt)
        SetBoneAng(ent, TK_LHIP_BONE, lerpAng(ef, Angle(0,0,0), TK_P0_LHIP))
        SetBoneAng(ent, TK_RHIP_BONE, lerpAng(ef, Angle(0,0,0), TK_P0_RHIP))
    elseif t <= TK_P1_END then
        local et = (t - TK_P0_END) / (TK_P1_END - TK_P0_END)
        local ef = easeInOut(et)
        SetBoneAng(ent, TK_LHIP_BONE, lerpAng(ef, TK_P0_LHIP, TK_P1_LHIP))
        SetBoneAng(ent, TK_RHIP_BONE, lerpAng(ef, TK_P0_RHIP, TK_P1_RHIP))
    elseif t <= TK_P2_END then
        local et = (t - TK_P1_END) / (TK_P2_END - TK_P1_END)
        local ef = easeInOut(et)
        SetBoneAng(ent, TK_LHIP_BONE, lerpAng(ef, TK_P1_LHIP, TK_P2_LHIP))
        SetBoneAng(ent, TK_RHIP_BONE, lerpAng(ef, TK_P1_RHIP, TK_P2_RHIP))
    elseif t <= TK_P3_END then
        local rt = (t - TK_P2_END) / (TK_P3_END - TK_P2_END)
        local rf = easeInOut(rt)
        SetBoneAng(ent, TK_LHIP_BONE, lerpAng(rf, TK_P2_LHIP, Angle(0,0,0)))
        SetBoneAng(ent, TK_RHIP_BONE, lerpAng(rf, TK_P2_RHIP, Angle(0,0,0)))
    else
        SetBoneAng(ent, TK_LHIP_BONE, Angle(0,0,0))
        SetBoneAng(ent, TK_RHIP_BONE, Angle(0,0,0))
    end
end

-- ============================================================
-- STOMP DRIVER
-- ============================================================
local function GekkoStompDriver(ent)
    if not ent._spcActive then return end

    local elapsed = CurTime() - ent._spcStartTime
    local active  = elapsed >= 0 and elapsed < ent._spcDuration
    if not active then
        ent._spcActive = false
        if ClaimHips(ent, "spc") then
            SetBoneAng(ent, SPC_LHIP_BONE, Angle(0,0,0))
            SetBoneAng(ent, SPC_RHIP_BONE, Angle(0,0,0))
            ReleaseHips(ent, "spc")
        end
        return
    end

    if not ClaimHips(ent, "spc") then return end

    local t = elapsed / ent._spcDuration

    if t <= SPC_P0_END then
        local pt = t / SPC_P0_END
        local ef = easeInOut(pt)
        SetBoneAng(ent, SPC_LHIP_BONE, lerpAng(ef, Angle(0,0,0), SPC_P0_LHIP))
        SetBoneAng(ent, SPC_RHIP_BONE, lerpAng(ef, Angle(0,0,0), SPC_P0_RHIP))
    elseif t <= SPC_P1_END then
        local et = (t - SPC_P0_END) / (SPC_P1_END - SPC_P0_END)
        local ef = easeInOut(et)
        SetBoneAng(ent, SPC_LHIP_BONE, lerpAng(ef, SPC_P0_LHIP, SPC_P1_LHIP))
        SetBoneAng(ent, SPC_RHIP_BONE, lerpAng(ef, SPC_P0_RHIP, SPC_P1_RHIP))
    elseif t <= SPC_P2_END then
        local et = (t - SPC_P1_END) / (SPC_P2_END - SPC_P1_END)
        local ef = easeInOut(et)
        SetBoneAng(ent, SPC_LHIP_BONE, lerpAng(ef, SPC_P1_LHIP, SPC_P2_LHIP))
        SetBoneAng(ent, SPC_RHIP_BONE, lerpAng(ef, SPC_P1_RHIP, SPC_P2_RHIP))
    elseif t <= SPC_P3_END then
        local rt = (t - SPC_P2_END) / (SPC_P3_END - SPC_P2_END)
        local rf = easeInOut(rt)
        SetBoneAng(ent, SPC_LHIP_BONE, lerpAng(rf, SPC_P2_LHIP, Angle(0,0,0)))
        SetBoneAng(ent, SPC_RHIP_BONE, lerpAng(rf, SPC_P2_RHIP, Angle(0,0,0)))
    else
        SetBoneAng(ent, SPC_LHIP_BONE, Angle(0,0,0))
        SetBoneAng(ent, SPC_RHIP_BONE, Angle(0,0,0))
    end
end

-- ============================================================
-- THINK — call all animation drivers
-- ============================================================
function ENT:Think()
    GekkoKickDriver(self)
    GekkoHeadbuttDriver(self)
    GekkoFK360Driver(self)
    GekkoFK360BDriver(self)
    GekkoSpinkickDriver(self)
    GekkoFootballKickDriver(self)
    GekkoFootballKickRDriver(self)
    GekkoDiagonalKickDriver(self)
    GekkoDiagonalKickRDriver(self)
    GekkoBiteDriver(self)
    GekkoTailKickDriver(self)
    GekkoStompDriver(self)
end

-- ============================================================
-- NET RECEIVERS — attack triggers
-- ============================================================

net.Receive("GekkoCrushHit", function()
    local ent = net.ReadEntity()
    if not IsValid(ent) then return end
    local hitPos    = net.ReadVector()
    local hitNormal = net.ReadVector()
    local hitType   = net.ReadUInt(3)

    local ed = EffectData()
    ed:SetOrigin(hitPos)
    ed:SetNormal(hitNormal)
    ed:SetEntity(ent)
    ed:SetScale(1.2)
    ed:SetMagnitude(1.5)
    util.Effect("BloodImpact", ed)

    util.Decal("Blood", hitPos - hitNormal * 4, hitPos + hitNormal * 8, ent)
end)

net.Receive("GekkoSonarLock", function()
    -- sonar lock handled by sonar system in cl_init
end)

-- ============================================================
-- APS INTERCEPT CLIENT — GekkoAPSIntercept
-- Server fires this for each burst pulse.
-- src       = world-space muzzle origin
-- dir       = normalized direction toward intercept
-- targetPos = world-space explosion position
-- firstShot = true only on the very first pulse (laser flash)
-- ============================================================

local APS_FLASH_PRESETS = {
    [1] = {
        fov = 165, nearz = 2, farz = 520,
        brightness = 3.8, lifetime = 0.055,
        color = { r = 255, g = 175, b = 70 },
        scaleMin = 1.10, scaleMax = 1.35,
        texture = "effects/muzzleflash_light",
    },
}

local APS_ActiveFlashes = {}

local function APS_SpawnFlash(pos, normal)
    local p     = APS_FLASH_PRESETS[1]
    local scale = p.scaleMin + math.random() * (p.scaleMax - p.scaleMin)
    local proj  = ProjectedTexture()
    if not proj then return end
    local ang = normal:Angle()
    ang.p = -ang.p
    proj:SetTexture(p.texture)
    proj:SetFOV(p.fov * scale)
    proj:SetNearZ(p.nearz)
    proj:SetFarZ(p.farz * scale)
    proj:SetBrightness(p.brightness * scale)
    proj:SetColor(Color(p.color.r, p.color.g, p.color.b))
    if proj.SetEnableShadows then proj:SetEnableShadows(false) end
    proj:SetPos(pos)
    proj:SetAngles(ang)
    proj:Update()
    table.insert(APS_ActiveFlashes, {
        proj    = proj,
        dieTime = CurTime() + p.lifetime,
    })
end

hook.Add("Think", "GekkoAPS_FlashCleanup", function()
    local now = CurTime()
    for i = #APS_ActiveFlashes, 1, -1 do
        local d = APS_ActiveFlashes[i]
        if not IsValid(d.proj) or now > d.dieTime then
            if IsValid(d.proj) then d.proj:Remove() end
            table.remove(APS_ActiveFlashes, i)
        end
    end
end)

_GekkoAPS_LaserFlash = nil

net.Receive("GekkoAPSIntercept", function()
    local src       = net.ReadVector()
    local dir       = net.ReadVector()
    local targetPos = net.ReadVector()
    local firstShot = net.ReadBool()

    -- Projected light burst at muzzle origin
    APS_SpawnFlash(src, dir)

    -- Particle muzzle puff
    local muzzleEd = EffectData()
    muzzleEd:SetOrigin(src)
    muzzleEd:SetNormal(dir)
    muzzleEd:SetAngles(dir:Angle())
    util.Effect("MuzzleEffect", muzzleEd)

    -- Tracer line from muzzle to intercept point
    local tracerEd = EffectData()
    tracerEd:SetStart(src)
    tracerEd:SetOrigin(targetPos)
    tracerEd:SetScale(5000)
    util.Effect("Tracer", tracerEd)

    -- Smoke puff at the intercept position
    local smokeEd = EffectData()
    smokeEd:SetOrigin(targetPos)
    smokeEd:SetNormal(Vector(0, 0, 1))
    smokeEd:SetScale(0.6)
    smokeEd:SetMagnitude(1)
    util.Effect("SmokeEffect", smokeEd)

    -- First pulse only: brief red laser dot toward intercept point (80 ms)
    if firstShot then
        _GekkoAPS_LaserFlash = {
            src     = src,
            endpos  = targetPos,
            dieTime = CurTime() + 0.08,
            color   = Color(255, 50, 50, 200),
        }
    end
end)

-- Laser flash renderer — draws beam for exactly 80ms then self-clears
hook.Add("PostDrawTranslucentRenderables", "GekkoAPS_LaserFlash", function()
    if not _GekkoAPS_LaserFlash then return end
    if CurTime() > _GekkoAPS_LaserFlash.dieTime then
        _GekkoAPS_LaserFlash = nil
        return
    end
    local d     = _GekkoAPS_LaserFlash
    local frac  = math.max(0, (d.dieTime - CurTime()) / 0.08)
    local alpha = frac * 200
    render.SetMaterial(Material("effects/laser1"))
    render.DrawBeam(d.src, d.endpos, 2, 0, 1, ColorAlpha(d.color, alpha))
end)
