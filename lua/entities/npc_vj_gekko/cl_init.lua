include("shared.lua")
include("elastic_cl.lua")
include("muzzleflash_system.lua")
include("bullet_impact_system.lua")
include("hit_react_cl.lua")
include("cl_aps.lua")
include("mg_shell_system.lua")
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
--  GROUNDED POSE CONSTANTS
-- ============================================================
-- FIX: ManipulateBonePosition offsets are in BONE-LOCAL space, not world
-- space.  The server already snapped the entity origin to the floor via
-- SnapToFloor(), so the entity origin IS the floor contact point.
--
-- b_pedestal sits at roughly Z=0 above the entity origin (it is the
-- skeleton root).  b_pelvis sits ~72 u above it.  Applying a huge
-- negative offset (-300) was pushing the root far underground, causing
-- the mesh renderer to place the visible geometry HIGH above the floor
-- (the engine keeps the render origin at entity Z, but the skeleton was
-- displaced downward, producing the "floating" look).
--
-- Correct approach:
--   • Do NOT move b_pedestal — leave the skeleton root at entity origin.
--   • Apply a SMALL downward offset to b_pelvis (-50) to collapse the
--     torso toward the floor and create the broken-leg silhouette.
--   • Drive the hip-piston bones into the broken-leg angles; these are
--     the actual leg bones for this model (b_l/r_hippiston1).
--   • b_l_thigh / b_r_thigh do not exist in this model — using them
--     silently did nothing before.
-- ============================================================
GND_PELVIS_OFFSET_Z = -50          -- small drop to seat torso near floor
GND_LHIP_ANG        = Angle(0,   0,  -70)   -- left  hip piston: splay out
GND_RHIP_ANG        = Angle(110, -90,  0)   -- right hip piston: collapsed

local function GekkoApplyGroundedPose(ent)
    -- Cache bone indices once per entity.
    if not ent._gndBonesInited then
        ent._gndBonesInited = true
        ent._gndPelBone  = ent:LookupBone("b_pelvis")       or -1
        ent._gndLHipBone = ent:LookupBone("b_l_hippiston1") or -1
        ent._gndRHipBone = ent:LookupBone("b_r_hippiston1") or -1
    end

    -- Pull torso down slightly so the body reads as floor-level.
    if ent._gndPelBone >= 0 then
        ent:ManipulateBonePosition(ent._gndPelBone,
            Vector(0, 0, GND_PELVIS_OFFSET_Z), false)
    end

    -- Broken-leg hip angles.
    if ent._gndLHipBone >= 0 then
        ent:ManipulateBoneAngles(ent._gndLHipBone, GND_LHIP_ANG, false)
    end
    if ent._gndRHipBone >= 0 then
        ent:ManipulateBoneAngles(ent._gndRHipBone, GND_RHIP_ANG, false)
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
BITE_P1_PELVIS = Angle(   0, -32,   0)
BITE_P1_SPINE4 = Angle(   0,   0,   0)   -- holds REST

-- phase 2 — body lean / spine charge
BITE_P2_LHIP   = nil   -- hold P1
BITE_P2_RHIP   = nil   -- hold P1
BITE_P2_PELVIS = Angle(  -5,  15,   5)
BITE_P2_SPINE4 = Angle( -19,  50, 102)

-- phase 3 — full bite strike
BITE_P3_LHIP   = Angle(  -1, -36,  19)
BITE_P3_RHIP   = Angle( -22, -22,  -8)
BITE_P3_PELVIS = Angle(  53,  50, 129)
BITE_P3_SPINE4 = nil   -- holds P2

BITE_LHIP_BONE   = "b_l_hippiston1"
BITE_RHIP_BONE   = "b_r_hippiston1"
BITE_PELVIS_BONE = "b_pelvis"
BITE_SPINE4_BONE = "b_spine3"   -- b_spine3: established lean bone, NOT the head-tracker

-- ============================================================
--  TORQUE KICK ANIMATION
--  3-phase strike.  Two bones not specified in a given
--  phase hold their previous keyframe value.
--
--  Phase 0 — wind-up
--    L( 53,-19, 43)  R(-15,   0, -19)
--  Phase 1 — peak strike
--    L(-72,  8, 36)  R( 36, -12,  19)
--  Phase 2 — return to REST
-- ============================================================
TK_DURATION = 1.2
TK_P0_END   = 0.280 / TK_DURATION
TK_P1_END   = 0.620 / TK_DURATION
TK_P2_END   = 0.940 / TK_DURATION

TK_P0_LHIP = Angle(  53, -19,  43)
TK_P0_RHIP = Angle( -15,   0, -19)

TK_P1_LHIP = Angle( -72,   8,  36)
TK_P1_RHIP = Angle(  36, -12,  19)

TK_LHIP_BONE = "b_l_hippiston1"
TK_RHIP_BONE = "b_r_hippiston1"

-- ============================================================
--  SPINNING CAPOEIRA ANIMATION
--  4-phase full-rotation kick.  Each phase holds until time
--  fraction crosses the phase boundary.
--
--  Phase 0 — wind-up
--    ped(0,0,22)  L(-22,-19,-12)  R(0,-19,-22)
--    pel(0,0,0)   spine4 REST
--  Phase 1 — spin build
--    ped holds P0   L(-36,-19, 22)  R(-8,-8,15)
--    pel(0,0,36)    spine4(-8,-19,15)
--  Phase 2 — peak/strike  (yaw spins here)
--    ped holds P1   L(-83, 15,-12)  R(-19,-19, 8)
--    pel holds P1   spine4 holds P1
--  Phase 3 — return to REST
-- ============================================================
SPC_DURATION = 1.5
SPC_P0_END   = 0.200 / SPC_DURATION
SPC_P1_END   = 0.400 / SPC_DURATION
SPC_P2_END   = 0.750 / SPC_DURATION
SPC_P3_END   = 0.980 / SPC_DURATION

SPC_YAW_TOTAL = 680
SPC_RAMP      = 0.15

-- phase 0
SPC_P0_PED    = Angle(0,  0, 22)
SPC_P0_LHIP   = Angle(-22, -19, -12)
SPC_P0_RHIP   = Angle(  0, -19, -22)
SPC_P0_PELVIS = Angle(0, 0, 0)
SPC_P0_SPINE4 = Angle(0, 0, 0)

-- phase 1
SPC_P1_LHIP   = Angle(-36, -19,  22)
SPC_P1_RHIP   = Angle( -8,  -8,  15)
SPC_P1_PELVIS = Angle(  0,   0,  36)
SPC_P1_SPINE4 = Angle( -8, -19,  15)

-- phase 2
SPC_P2_LHIP   = Angle(-83,  15, -12)
SPC_P2_RHIP   = Angle(-19, -19,   8)

SPC_PELVIS_BONE = "b_pelvis"
SPC_PED_BONE    = "b_pedestal"
SPC_LHIP_BONE   = "b_l_hippiston1"
SPC_RHIP_BONE   = "b_r_hippiston1"
SPC_SPINE4_BONE = "b_spine3"

-- ============================================================
--  HEEL HOOK ANIMATION
--  5-phase sweep/lock.  Phase boundaries as time fractions.
--
--  Phase 0 — wind-up
--    L(29,-43, 43)   R(-25, 0,-22)
--    pel REST        spine4 REST
--  Phase 1 — sweep in
--    L(83,-29, 22)   R(-12, 0,-19)
--    pel(0,0, 22)    spine4(-8, 15, 15)
--  Phase 2 — hook lock (hold until return)
--    L(53,-36,-12)   R(22, -8, -8)
--    pel( 36,36,-19) spine4(-8, 36, 36)
--  Phase 3 — return to REST
-- ============================================================
HH_DURATION = 1.4
HH_P0_END   = 0.200 / HH_DURATION
HH_P1_END   = 0.460 / HH_DURATION
HH_P2_END   = 0.750 / HH_DURATION
HH_P3_END   = 0.960 / HH_DURATION

-- phase 0
HH_P0_LHIP   = Angle( 29, -43,  43)
HH_P0_RHIP   = Angle(-25,   0, -22)
HH_P0_PELVIS = Angle(  0,   0,   0)
HH_P0_SPINE4 = Angle(  0,   0,   0)

-- phase 1
HH_P1_LHIP   = Angle( 83, -29,  22)
HH_P1_RHIP   = Angle(-12,   0, -19)
HH_P1_PELVIS = Angle(  0,   0,  22)
HH_P1_SPINE4 = Angle( -8,  15,  15)

-- phase 2 — hook lock
HH_P2_LHIP   = Angle( 53, -36, -12)
HH_P2_RHIP   = Angle( 22,  -8,  -8)
HH_P2_PELVIS = Angle( 36,  36, -19)
HH_P2_SPINE4 = Angle( -8,  36,  36)

HH_PELVIS_BONE = "b_pelvis"
HH_PED_BONE    = "b_pedestal"
HH_LHIP_BONE   = "b_l_hippiston1"
HH_RHIP_BONE   = "b_r_hippiston1"
HH_SPINE4_BONE = "b_spine4"

-- ============================================================
--  SIDE HOOK KICK ANIMATION
--  3-phase lateral hook kick.
--
--  Phase 0 — wind-up
--    L(36, 0, 22)   R(-19, -8, -36)
--  Phase 1 — hook extension
--    L(12, 0,-83)   R(-36, -19, 22)
--  Phase 2 — return
-- ============================================================
SHK_DURATION = 1.1
SHK_P0_END   = 0.260 / SHK_DURATION
SHK_P1_END   = 0.620 / SHK_DURATION
SHK_P2_END   = 0.930 / SHK_DURATION

SHK_P0_LHIP  = Angle( 36,   0,  22)
SHK_P0_RHIP  = Angle(-19,  -8, -36)

SHK_P1_LHIP  = Angle( 12,   0, -83)
SHK_P1_RHIP  = Angle(-36, -19,  22)

SHK_LHIP_BONE = "b_l_hippiston1"
SHK_RHIP_BONE = "b_r_hippiston1"

-- ============================================================
--  AXE KICK ANIMATION  (left leg overhead)
--  3-phase downward axe strike.
--
--  Phase 0 — raise
--    L(-105, 22, 36)   R(15, -12, -22)
--  Phase 1 — strike
--    L(  83, 22, 22)   R(22,   0, -19)
--  Phase 2 — return
-- ============================================================
AK_DURATION = 1.0
AK_P0_END   = 0.280 / AK_DURATION
AK_P1_END   = 0.600 / AK_DURATION
AK_P2_END   = 0.920 / AK_DURATION

AK_P0_LHIP  = Angle(-105,  22,  36)
AK_P0_RHIP  = Angle(  15, -12, -22)

AK_P1_LHIP  = Angle(  83,  22,  22)
AK_P1_RHIP  = Angle(  22,   0, -19)

AK_LHIP_BONE = "b_l_hippiston1"
AK_RHIP_BONE = "b_r_hippiston1"

-- ============================================================
--  AXE KICK R ANIMATION  (right leg overhead)
--  Mirror of AK but right leg leads.
--
--  Phase 0 — raise
--    R(-105, -22, -36)   L(15, 12, 22)
--  Phase 1 — strike
--    R(  83, -22, -22)   L(22,  0, 19)
--  Phase 2 — return
-- ============================================================
AKR_DURATION = 1.0
AKR_P0_END   = 0.280 / AKR_DURATION
AKR_P1_END   = 0.600 / AKR_DURATION
AKR_P2_END   = 0.920 / AKR_DURATION

AKR_P0_RHIP  = Angle(-105, -22, -36)
AKR_P0_LHIP  = Angle(  15,  12,  22)

AKR_P1_RHIP  = Angle(  83, -22, -22)
AKR_P1_LHIP  = Angle(  22,   0,  19)

AKR_RHIP_BONE = "b_r_hippiston1"
AKR_LHIP_BONE = "b_l_hippiston1"

-- ============================================================
--  JUMP KICK ANIMATION
--  4-phase aerial kick.
--
--  Phase 0 — wind-up
--    ped(-19,0,0)  L( 43, 0, 36)   R(-22, 0, -22)
--    pel(-19,0,0)
--  Phase 1 — kick peak
--    ped(-36,0,0)  L(-83, 0,-22)   R( 22, 0, -19)
--    pel(-36,0,0)
--  Phase 2 — land tuck
--    ped(-12,0,0)  L( 22, 0, 12)   R(-12, 0, -12)
--    pel(-12,0,0)
--  Phase 3 — return
-- ============================================================
JK_DURATION = 1.2
JK_P0_END   = 0.220 / JK_DURATION
JK_P1_END   = 0.520 / JK_DURATION
JK_P2_END   = 0.760 / JK_DURATION
JK_P3_END   = 0.970 / JK_DURATION

-- phase 0 — wind-up
JK_P0_PED   = Angle(-19, 0,  0)
JK_P0_LHIP  = Angle( 43, 0, 36)
JK_P0_RHIP  = Angle(-22, 0,-22)
JK_P0_PEL   = Angle(-19, 0,  0)

-- phase 1 — kick peak
JK_P1_PED   = Angle(-36, 0,  0)
JK_P1_LHIP  = Angle(-83, 0,-22)
JK_P1_RHIP  = Angle( 22, 0,-19)
JK_P1_PEL   = Angle(-36, 0,  0)

-- phase 2 — land tuck
JK_P2_PED   = Angle(-12, 0,  0)
JK_P2_LHIP  = Angle( 22, 0, 12)
JK_P2_RHIP  = Angle(-12, 0,-12)
JK_P2_PEL   = Angle(-12, 0,  0)

JK_PED_BONE  = "b_pedestal"
JK_LHIP_BONE = "b_l_hippiston1"
JK_RHIP_BONE = "b_r_hippiston1"
JK_PEL_BONE  = "b_pelvis"

-- ============================================================
--  ENT:Initialize
-- ============================================================
function ENT:Initialize()
    self._spineBone = self:LookupBone("b_spine4") or -1
end

-- ============================================================
--  ENT:Think  (client)
-- ============================================================
function ENT:Think()
    if self:GetNWBool("GekkoLegsDisabled", false) then
        GekkoApplyGroundedPose(self)
        GekkoDoBloodSplat(self)
        GekkoDoMGFX(self)
        return
    end

    local dt = FrameTime()

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

    GekkoUpdateHead(self, dt)
    GekkoSyncFootsteps(self)
    GekkoFootShake(self)
    GekkoDoJumpDust(self)
    GekkoDoLandDust(self)
    GekkoDoFK360LandDust(self)
    GekkoDoBloodSplat(self)
    GekkoDoMGFX(self)
end
