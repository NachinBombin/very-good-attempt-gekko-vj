include("shared.lua")
include("elastic_cl.lua")
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
BITE_P3_SPINE4 = Angle( -19,  50, 102)   -- holds P2

BITE_LHIP_BONE   = "b_l_hippiston1"
BITE_RHIP_BONE   = "b_r_hippiston1"
BITE_PELVIS_BONE = "b_pelvis"
BITE_SPINE4_BONE = "b_spine3"   -- b_spine3: established lean bone, NOT the head-tracker
BITE_PED_BONE    = "b_pedestal"
BITE_PED_Z       = -65          -- crouch depth in local units
BITE_PED_RAMP    = 0.20         -- fraction of duration used to ramp in / out

-- ============================================================
--  TORQUE KICK ANIMATION  (spin-kick variation, forward attack)
--  5 phases:
--    P0 → P1  ramp in REST → preparation
--    P1 → P2  preparation → posture
--    P2 → P3  posture → kick (strike peak)
--    P3 → P4  kick → recoil
--    P4 → end smooth return to REST
--
--  Rhip Y is unspecified in phases 1-3 (held at 0), explicitly
--  driven to 70 only during the recoil phase.
-- ============================================================
TK_DURATION = 1.5
TK_P1_END   = 0.200 / TK_DURATION   -- ramp in     → preparation
TK_P2_END   = 0.420 / TK_DURATION   -- preparation → posture
TK_P3_END   = 0.630 / TK_DURATION   -- posture     → kick peak
TK_P4_END   = 0.820 / TK_DURATION   -- kick        → recoil
-- P4_END → 1.0 : smooth return to REST

-- preparation
TK_P1_LHIP  = Angle(  57,  43,  70)
TK_P1_RHIP  = Angle(  88,   0, -36)

-- posture
TK_P2_LHIP  = Angle(  22,  53,   1)
TK_P2_RHIP  = Angle( -57,   0, -67)

-- kick peak
TK_P3_LHIP  = Angle( -70,  15,   1)
TK_P3_RHIP  = Angle( -88,   0, -67)

-- recoil  (Rhip Y finally keyed to 70)
TK_P4_LHIP  = Angle( -95, -12, -12)
TK_P4_RHIP  = Angle(-105,  70, -46)

TK_LHIP_BONE = "b_l_hippiston1"
TK_RHIP_BONE = "b_r_hippiston1"

-- ============================================================
--  SPINNING CAPOEIRA ANIMATION  (360-damage spin-kick variant)
--  1.8 s sequence, 7 keyframes + smooth return to REST.
--
--  Pelvis drives BOTH angles AND position Z from steps 4–7.
--  Unspecified X/Z axes in step 1 and pelvis Z angle in steps
--  1–6 are held at 0.
--
--  Phase timeline (raw seconds / SPC_DURATION):
--    P1  0.18  legs get together
--    P2  0.36  legs continue
--    P3  0.56  end of preparatory spin
--    P4  0.76  leg extension
--    P5  0.96  FULL ATTACK
--    P6  1.15  attack ends
--    P7  1.40  recoil and decelerate
--    ret 1.40→1.80  smooth return to REST
-- ============================================================
SPC_DURATION = 1.5

SPC_P1_END   = 0.10 / SPC_DURATION
SPC_P2_END   = 0.26 / SPC_DURATION
SPC_P3_END   = 0.36 / SPC_DURATION
SPC_P4_END   = 0.56 / SPC_DURATION
SPC_P5_END   = 0.69 / SPC_DURATION   -- FULL ATTACK
SPC_P6_END   = 1.40 / SPC_DURATION
SPC_P7_END   = 5.10 / SPC_DURATION

-- step 1 — legs get together
SPC_P1_LHIP   = Angle(  0,  -6,   0)
SPC_P1_RHIP   = Angle( -1, -29, -22)
SPC_P1_PELVIS = Angle(  8,  19,   0)
SPC_P1_PELZ   =  0

-- step 2 — legs continue
SPC_P2_LHIP   = Angle( 49, -39, -35)
SPC_P2_RHIP   = Angle( -8, -22, -29)
SPC_P2_PELVIS = Angle( 20,   5,   0)
SPC_P2_PELZ   =  0

-- step 3 — end of preparatory spin
SPC_P3_LHIP   = Angle( 43, -29,  -1)
SPC_P3_RHIP   = Angle(-43, -22, -22)
SPC_P3_PELVIS = Angle( 30,   5,   0)
SPC_P3_PELZ   =  0

-- step 4 — leg extension
SPC_P4_LHIP   = Angle( 77, -57, -36)
SPC_P4_RHIP   = Angle(-81, -22, -22)
SPC_P4_PELVIS = Angle( 34,   5,   0)
SPC_P4_PELZ   = -45

-- step 5 — FULL ATTACK
SPC_P5_LHIP   = Angle( 77, -57, -53)
SPC_P5_RHIP   = Angle(-81, -19, -22)
SPC_P5_PELVIS = Angle(199,   5,   0)
SPC_P5_PELZ   = -70

-- step 6 — attack ends
SPC_P6_LHIP   = Angle( 29, -12, -12)
SPC_P6_RHIP   = Angle(-88,  -5, -22)
SPC_P6_PELVIS = Angle(380,   5,   0)
SPC_P6_PELZ   = -34

-- step 7 — recoil and decelerate
SPC_P7_LHIP   = Angle( 30, -12, -19)
SPC_P7_RHIP   = Angle( -1, -12, -12)
SPC_P7_PELVIS = Angle(430, -15,  22)
SPC_P7_PELZ   = -28

SPC_LHIP_BONE   = "b_l_hippiston1"
SPC_RHIP_BONE   = "b_r_hippiston1"
SPC_PELVIS_BONE = "b_pelvis"

-- ============================================================
--  HEEL HOOK ANIMATION
-- ============================================================
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

-- ============================================================
--  SIDE HOOK KICK ANIMATION
-- ============================================================
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

-- ============================================================
--  AXE KICK ANIMATION
-- ============================================================
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

-- mirrored AXE KICK (right leg primary, reuse same angles)

-- ============================================================
--  JUMP KICK ANIMATION
-- ============================================================
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
--  CRUSH HIT
-- ============================================================
CRUSH_IMPACT_SOUNDS = {
    "physics/body/body_medium_impact_hard1.wav",
    "physics/body/body_medium_impact_hard2.wav",
    "physics/body/body_medium_impact_hard3.wav",
    "physics/body/body_medium_impact_hard4.wav",
    "physics/body/body_medium_impact_hard5.wav",
    "physics/body/body_medium_impact_hard6.wav",
}

CRUSH_SHAKE_RADIUS = 900

net.Receive("GekkoCrushHit", function()
    local hitPos   = net.ReadVector()
    local gekkoPos = net.ReadVector()

    sound.Play(
        CRUSH_IMPACT_SOUNDS[math.random(#CRUSH_IMPACT_SOUNDS)],
        hitPos, 110, 80
    )

    local e = EffectData()
    e:SetOrigin(hitPos + Vector(0, 0, 20))
    e:SetNormal(Vector(0, 0, 1))
    e:SetMagnitude(12)
    e:SetScale(3)
    e:SetRadius(40)
    util.Effect("ManhackSparks", e, false)

    local ply = LocalPlayer()
    if IsValid(ply) then
        local dist  = ply:GetPos():Distance(gekkoPos)
        local alpha = 1 - math.Clamp(dist / CRUSH_SHAKE_RADIUS, 0, 1)
        if alpha > 0 then
            util.ScreenShake(gekkoPos, 45 * alpha, 28, 0.20, CRUSH_SHAKE_RADIUS)
            util.ScreenShake(gekkoPos, 20 * alpha,  8, 0.45, CRUSH_SHAKE_RADIUS)
        end
    end
end)

-- ============================================================
--  SONAR LOCK
-- ============================================================
SONAR_SOUND          = "mac_bo2_m32/Sonar intercept.wav"
SONAR_DURATION       = 3.0
SONAR_PULSE_COUNT    = 3
SONAR_PULSE_INTERVAL = 0.6
SONAR_RING_THICKNESS = 3
SONAR_PEAK_ALPHA     = 100
SONAR_TINT_ALPHA     = 40

SONAR_R = 200
SONAR_G = 0
SONAR_B = 0

local sonar_startTime = nil
local sonar_active    = false

net.Receive("GekkoSonarLock", function()
    local ply = LocalPlayer()
    if IsValid(ply) then
        sound.Play(SONAR_SOUND, ply:GetPos(), 75, 100)
    end

    sonar_startTime = CurTime()
    sonar_active    = true

    print("[GekkoSonar] TRIGGERED  t=" .. tostring(sonar_startTime))
end)

local function DrawRingOutline(cx, cy, radius, thick, r, g, b, a)
    if radius <= 0 or a <= 0 then return end

    local steps  = math.max(48, math.floor(radius * 0.4))
    local prev_x = cx + radius
    local prev_y = cy

    for i = 1, steps do
        local ang = (i / steps) * math.pi * 2
        local nx  = cx + math.cos(ang) * radius
        local ny  = cy + math.sin(ang) * radius

        local mx  = (prev_x + nx) * 0.5
        local my  = (prev_y + ny) * 0.5

        local dx  = nx - prev_x
        local dy  = ny - prev_y
        local len = math.sqrt(dx*dx + dy*dy)

        if len > 0 then
            surface.SetDrawColor(r, g, b, a)
            surface.DrawRect(
                math.floor(mx - len * 0.5),
                math.floor(my - thick * 0.5),
                math.ceil(len + 1),
                thick
            )
        end

        prev_x = nx
        prev_y = ny
    end
end

hook.Add("HUDPaint", "GekkoSonarEffect", function()
    if not sonar_active then return end

    local now     = CurTime()
    local elapsed = now - sonar_startTime
    if elapsed >= SONAR_DURATION then
        sonar_active = false
        return
    end

    local sw, sh = ScrW(), ScrH()
    local cx, cy = sw * 0.5, sh * 0.5

    local globalFade = 1 - math.Clamp(elapsed / SONAR_DURATION, 0, 1)

    local tintFade = math.max(0, 1 - elapsed / (SONAR_DURATION * 0.4))
    local tintA    = math.floor(SONAR_TINT_ALPHA * tintFade * globalFade)
    if tintA > 0 then
        surface.SetDrawColor(SONAR_R, SONAR_G, SONAR_B, tintA)
        surface.DrawRect(0, 0, sw, sh)
    end

    local maxRadius = math.sqrt(cx*cx + cy*cy) * 1.1

    for i = 0, SONAR_PULSE_COUNT - 1 do
        local pulseStart    = i * SONAR_PULSE_INTERVAL
        local pulseAge      = elapsed - pulseStart
        if pulseAge < 0 then continue end

        local pulseDuration = SONAR_PULSE_INTERVAL + 0.5
        local t = math.Clamp(pulseAge / pulseDuration, 0, 1)
        if t >= 1 then continue end

        local riseEnd = 0.12
        local pAlpha
        if t < riseEnd then
            pAlpha = t / riseEnd
        else
            pAlpha = 1 - ((t - riseEnd) / (1 - riseEnd))
        end
        pAlpha = pAlpha * pAlpha

        local finalAlpha = math.floor(SONAR_PEAK_ALPHA * pAlpha * globalFade)
        if finalAlpha <= 0 then continue end

        local radius = maxRadius * (0.05 + t * 0.95)
        DrawRingOutline(cx, cy, radius, SONAR_RING_THICKNESS,
            SONAR_R, SONAR_G, SONAR_B, finalAlpha)
    end
end)

-- ============================================================
--  FOOTSTEP SYNC
-- ============================================================
STEP_SOUNDS = {
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
SHAKE_NEAR_DIST = 350
SHAKE_FAR_DIST  = 750
SHAKE_MIN_SPEED = 8

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

    local footplant =
        (prevR > 0 and sinR <= 0) or
        (prevL > 0 and sinL <= 0)

    if not footplant then return end

    local alpha = 1 - (dist / SHAKE_FAR_DIST)
    local amp   = (dist < SHAKE_NEAR_DIST) and (12 * alpha) or (5 * alpha)

    util.ScreenShake(ent:GetPos(), amp, 14, 0.18, SHAKE_FAR_DIST)
end

-- ============================================================
--  HEAD DRIVER
-- ============================================================
HEAD_LIMIT       =  50
HEAD_PITCH_UP    = -60
HEAD_PITCH_DOWN  =  60
HEAD_SPEED       =  30

local function GekkoUpdateHead(ent, dt)
    -- BITE suppresses head tracking for the full attack duration so
    -- the lunge pose on b_spine3 is not fought by the head driver.
    if ent._biteHeadSuppress then return end

    local bone = ent._spineBone
    if not bone or bone < 0 then return end

    ent._headYaw   = ent._headYaw   or 0
    ent._headPitch = ent._headPitch or 0

    local enemy       = ent:GetNWEntity("GekkoEnemy", NULL)
    local targetYaw   = 0
    local targetPitch = 0

    if IsValid(enemy) then
        local boneMatrix = ent:GetBoneMatrix(bone)
        local pos        = boneMatrix and boneMatrix:GetTranslation()
                            or (ent:GetPos() + Vector(0, 0, 130))

        local toEnemy    = (enemy:GetPos() + Vector(0, 0, 40) - pos):Angle()
        targetYaw   = math.Clamp(
            math.NormalizeAngle(toEnemy.y - ent:GetAngles().y),
            -HEAD_LIMIT, HEAD_LIMIT
        )
        targetPitch = math.Clamp(
            toEnemy.p,
            HEAD_PITCH_UP, HEAD_PITCH_DOWN
        )
    end

    local maxStep   = HEAD_SPEED * dt

    local yawDiff   = math.NormalizeAngle(targetYaw - ent._headYaw)
    ent._headYaw    = math.Clamp(ent._headYaw +
        math.Clamp(yawDiff, -maxStep, maxStep),
        -HEAD_LIMIT, HEAD_LIMIT)

    local pitchDiff = targetPitch - ent._headPitch
    ent._headPitch  = math.Clamp(ent._headPitch +
        math.Clamp(pitchDiff, -maxStep, maxStep),
        HEAD_PITCH_UP, HEAD_PITCH_DOWN)

    ent:ManipulateBoneAngles(bone, Angle(-ent._headYaw, 0, ent._headPitch), false)
end

-- ============================================================
--  JUMP DUST
-- ============================================================
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

-- ============================================================
--  LAND DUST
-- ============================================================
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

-- ============================================================
--  FK360 LAND DUST
-- ============================================================
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

-- ============================================================
--  MG FIRING FX
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

    local now = CurTime()

    if not ent._nextShellT or now >= ent._nextShellT then
        ent._nextShellT = now + SHELL_INTERVAL

        local e = EffectData()
        e:SetEntity(ent)
        e:SetOrigin(pos)
        e:SetAngles(ang)
        util.Effect("RifleShellEject", e, false)
    end

    if not ent._nextSparkT or now >= ent._nextSparkT then
        ent._nextSparkT = now + math.Rand(1.5, 3.5)

        local fwd = ang:Forward()
        local e = EffectData()
        e:SetOrigin(pos + fwd * 8)
        e:SetNormal(fwd)
        e:SetAngles(ang)
        e:SetEntity(ent)
        e:SetMagnitude(math.Rand(2, 6))
        e:SetScale(math.Rand(0.5, 2.0))
        e:SetRadius(math.random(8, 20))
        util.Effect("ManhackSparks", e, false)
    end
end

-- ============================================================
--  BLOOD SPLATTER
-- ============================================================
local BLOOD_SIZE   = 0.4
local BLOOD_DECAL  = "Blood"
local BLOOD_DECAL2 = "Blood"

local function RandBiasedDir(dir, bias)
    local r = Vector(
        (math.random() - 0.5) * 2,
        (math.random() - 0.5) * 2,
        (math.random() - 0.5) * 2
    )
    r:Normalize()
    return (r + dir * bias):GetNormalized()
end

local function SpawnBloodBlob(pos, dir, speed, scale)
    local s  = BLOOD_SIZE
    local sp = speed * s

    local e = EffectData()
    e:SetOrigin(pos)
    e:SetNormal(dir)
    e:SetScale(scale * s)
    e:SetMagnitude(sp * 0.05)
    e:SetRadius(math.random(12, 36) * s)
    util.Effect("BloodImpact", e, false)

    local e2 = EffectData()
    e2:SetOrigin(pos)
    e2:SetNormal(dir)
    e2:SetScale(scale * math.Rand(0.6, 1.4) * s)
    e2:SetMagnitude(math.Rand(8, 22) * s)
    util.Effect("BloodSpray", e2, false)

    local tr = util.TraceLine({
        start  = pos,
        endpos = pos + dir * sp,
        mask   = MASK_SOLID_BRUSHONLY,
    })

    if tr.Hit then
        local decalName = (math.random(1, 6) == 1) and BLOOD_DECAL2 or BLOOD_DECAL
        util.Decal(decalName, tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal)
    end
end

local function BloodVariant_Geyser(origin)
    local s     = BLOOD_SIZE
    local count = math.random(18, 32)

    for _ = 1, count do
        local spread = math.Rand(0.0, 0.35)
        local dir    = Vector(
            (math.random() - 0.5) * 2 * spread,
            (math.random() - 0.5) * 2 * spread,
            math.Rand(0.7, 1.0)
        )
        dir:Normalize()

        SpawnBloodBlob(
            origin + Vector(0, 0, math.Rand(20, 120) * s),
            dir,
            math.Rand(800, 2200),
            math.Rand(8, 22)
        )
    end

    for _ = 1, math.random(4, 8) do
        local e = EffectData()
        e:SetOrigin(origin + Vector((math.random()-0.5)*80*s, (math.random()-0.5)*80*s, 4))
        e:SetNormal(Vector(0, 0, 1))
        e:SetScale(math.Rand(12, 28) * s)
        
        e:SetMagnitude(math.Rand(10, 30) * s)
        util.Effect("BloodImpact", e, false)
    end
end

local function BloodVariant_RadialRing(origin)
    local s      = BLOOD_SIZE
    local spokes = math.random(20, 36)
    local ringH  = math.Rand(40, 100) * s

    for i = 1, spokes do
        local angle = (i / spokes) * math.pi * 2
        local dir   = Vector(math.cos(angle), math.sin(angle), math.Rand(-0.15, 0.35))
        dir:Normalize()

        SpawnBloodBlob(
            origin + Vector(0, 0, ringH),
            dir,
            math.Rand(700, 2400),
            math.Rand(10, 28)
        )
    end

    for _ = 1, math.random(6, 12) do
        local e = EffectData()
        e:SetOrigin(origin + Vector(0, 0, ringH))
        e:SetNormal(RandBiasedDir(Vector(0, 0, 1), 0.3))
        e:SetScale(math.Rand(15, 35) * s)
        e:SetMagnitude(math.Rand(15, 40) * s)
        util.Effect("BloodImpact", e, false)
    end
end

local function BloodVariant_BurstCloud(origin)
    local s = BLOOD_SIZE

    for _ = 1, math.random(28, 50) do
        SpawnBloodBlob(
            origin + Vector(0, 0, math.Rand(30, 160) * s),
            RandBiasedDir(Vector(0, 0, 0.4), 0),
            math.Rand(600, 2800),
            math.Rand(10, 30)
        )
    end

    for _ = 1, math.random(8, 16) do
        local e = EffectData()
        e:SetOrigin(origin + Vector(
            (math.random()-0.5) * 120 * s,
            (math.random()-0.5) * 120 * s,
            math.Rand(10, 180) * s
        ))
        e:SetNormal(RandBiasedDir(Vector(0, 0, 1), 0.2))
        e:SetScale(math.Rand(18, 40) * s)
        e:SetMagnitude(math.Rand(20, 50) * s)
        util.Effect("BloodImpact", e, false)
    end
end

local function BloodVariant_ArcShower(origin, forwardDir)
    local s = BLOOD_SIZE

    for _ = 1, math.random(22, 40) do
        SpawnBloodBlob(
            origin + Vector(0, 0, math.Rand(60, 180) * s),
            RandBiasedDir(forwardDir + Vector(0, 0, 0.5), 0.55),
            math.Rand(1000, 3000),
            math.Rand(8, 24)
        )
    end

    for _ = 1, math.random(4, 10) do
        local e = EffectData()
        e:SetOrigin(origin + Vector(0, 0, math.Rand(30, 100) * s))
        e:SetNormal(RandBiasedDir(Vector((math.random()-0.5)*2, (math.random()-0.5)*2, 0.1), 0.1))
        e:SetScale(math.Rand(12, 32) * s)
        e:SetMagnitude(math.Rand(12, 35) * s)
        util.Effect("BloodImpact", e, false)
    end
end

local function BloodVariant_GroundPool(origin)
    local s = BLOOD_SIZE

    for _ = 1, math.random(20, 38) do
        local angle = math.Rand(0, math.pi * 2)
        local dir   = Vector(math.cos(angle), math.sin(angle), math.Rand(-0.05, 0.25))
        dir:Normalize()

        SpawnBloodBlob(
            origin + Vector(0, 0, math.Rand(5, 40) * s),
            dir,
            math.Rand(600, 2000),
            math.Rand(14, 36)
        )
    end

    for _ = 1, math.random(5, 10) do
        local e = EffectData()
        e:SetOrigin(origin + Vector(
            (math.random()-0.5) * 100 * s,
            (math.random()-0.5) * 100 * s,
            2
        ))
        e:SetNormal(Vector(0, 0, 1))
        e:SetScale(math.Rand(20, 50) * s)
        e:SetMagnitude(math.Rand(20, 55) * s)
        util.Effect("BloodImpact", e, false)
    end
end
-- ============================================================
--  BLOOD VARIANT 6 — HEMO STREAM  (Hemo-fluid-stream port)
--  Fires the gekko_bloodstream effect with randomized
--  size_mult (SetScale) and force_mult (SetMagnitude).
-- ============================================================
local function BloodVariant_HemoStream(ent)
    local size_mult  = math.Rand(0.6, 1.8)
    local force_mult = math.Rand(0.7, 2.0)

    -- flags: 0 = stream (long), 1 = burst (short)
    -- We randomly pick between stream and burst for variety
    local flags = (math.random(1, 3) == 1) and 1 or 0

    local effectdata = EffectData()
    effectdata:SetEntity(ent)
    effectdata:SetFlags(flags)
    effectdata:SetScale(size_mult)
    effectdata:SetMagnitude(force_mult)
    util.Effect("gekko_bloodstream", effectdata, false)
end



local function GekkoDoBloodSplat(ent)
    local packed = ent:GetNWInt("GekkoBloodSplat", 0)
    if packed == 0 then return end

    local pulse = math.floor(packed / 8)
    if pulse == (ent._lastBloodPulse or 0) then return end
    ent._lastBloodPulse = pulse

       local variant = (packed % 8) + 1
    local fwd     = ent:GetForward()

    -- Pick a random bone to bleed from so wounds appear all over the model
    local BLOOD_BONES = {
        "b_spine3",       -- torso / upper body
        "b_spine4",       -- neck / head area
        "b_pelvis",       -- midsection
        "b_l_upperleg",   -- left thigh
        "b_r_upperleg",   -- right thigh
        "b_l_hippiston1", -- left hip
        "b_r_hippiston1", -- right hip
        "b_pedestal",     -- lower base
    }
    local origin
    local boneName = BLOOD_BONES[math.random(#BLOOD_BONES)]
    local boneIdx  = ent:LookupBone(boneName)
    if boneIdx and boneIdx >= 0 then
        local mat = ent:GetBoneMatrix(boneIdx)
        origin = mat and mat:GetTranslation() or (ent:GetPos() + Vector(0, 0, 80))
    else
        origin = ent:GetPos() + Vector(0, 0, 80)
    end

    if     variant == 1 then BloodVariant_Geyser(origin)
    elseif variant == 2 then BloodVariant_RadialRing(origin)
    elseif variant == 3 then BloodVariant_BurstCloud(origin)
    elseif variant == 4 then BloodVariant_ArcShower(origin, fwd)
    elseif variant == 5 then BloodVariant_GroundPool(ent:GetPos())
    elseif variant == 6 then BloodVariant_HemoStream(ent)
    end
end

-- ============================================================
--  KICK BONE DRIVER (right leg)
--  Jitter: randomised kick angle and window duration on each trigger.
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

-- ============================================================
--  KICK BONE DRIVER (left leg mirror)
--  Jitter: same pattern as right leg driver.
-- ============================================================
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
--  HEADBUTT BONE DRIVER
--  Jitter: randomised duration and jittered peak angles.
-- ============================================================
local function GekkoDoHeadbuttBone(ent)
    if ent._hbInited == nil then
        ent._hbInited      = true
        ent._hbSpineIdx    = ent:LookupBone(HB_SPINE3_BONE)   or -1
        ent._hbPedestalIdx = ent:LookupBone(HB_PEDESTAL_BONE) or -1
        ent._hbStartTime   = -9999
        ent._hbDuration    = HB_DURATION
        ent._hbPulseLast   = ent:GetNWInt("GekkoHeadbuttPulse", 0)
        ent._hbWasActive   = false
        ent._hbJitSpineX   = HB_SPINE3_ANG_X
        ent._hbJitPedX     = HB_PEDESTAL_POS_X
        ent._hbJitPedZ     = HB_PEDESTAL_POS_Z
    end

    local pulse = ent:GetNWInt("GekkoHeadbuttPulse", 0)
    if pulse ~= ent._hbPulseLast then
        ent._hbPulseLast = pulse
        ent._hbStartTime = CurTime()
        ent._hbDuration  = JitterDur(HB_DURATION)
        -- jitter the scalar peak values by ±JITTER_DEG
        local function jf() return (math.random() - 0.5) * 2 * JITTER_DEG end
        ent._hbJitSpineX = HB_SPINE3_ANG_X   + jf()
        ent._hbJitPedX   = HB_PEDESTAL_POS_X + jf()
        ent._hbJitPedZ   = HB_PEDESTAL_POS_Z + jf()

        print(string.format("[GekkoHeadbutt] pulse=%d  dur=%.2f", pulse, ent._hbDuration))
    end

    local elapsed = CurTime() - ent._hbStartTime
    local active  = elapsed >= 0 and elapsed < ent._hbDuration
    if not active then
        if ent._hbWasActive then
            ent._hbWasActive = false
            if ent._hbSpineIdx    >= 0 then
                ent:ManipulateBoneAngles(ent._hbSpineIdx, Angle(0, 0, 0), false)
            end
            if ent._hbPedestalIdx >= 0 then
                ent:ManipulateBonePosition(ent._hbPedestalIdx, Vector(0, 0, 0), false)
            end
        end
        return
    end

    ent._hbWasActive = true

    local t   = elapsed / ent._hbDuration
    local peak = ent._hbDuration > 0 and (HB_PEAK / HB_DURATION) or HB_PEAK
    local env
    if t < peak then
        env = Smoothstep(t / peak)
    else
        env = Smoothstep(1 - (t - peak) / (1 - peak))
    end

    if ent._hbSpineIdx >= 0 then
        ent:ManipulateBoneAngles(ent._hbSpineIdx,
            Angle(ent._hbJitSpineX * env, 0, 0), false)
    end

    if ent._hbPedestalIdx >= 0 then
        ent:ManipulateBonePosition(ent._hbPedestalIdx,
            Vector(ent._hbJitPedX * env, 0, ent._hbJitPedZ * env), false)
    end
end

-- ============================================================
--  FK360 BONE DRIVER
--  Jitter: randomised duration (stored per-trigger on ent).
--  Angle jitter is not applied here because the animation is a
--  continuous yaw accumulation — the speed envelope handles it.
-- ============================================================
local function GekkoDoFK360Bone(ent)
    local fk360Duration = ent.FK360_DURATION or 0.9

    if ent._fk360Inited == nil then
        ent._fk360Inited    = true
        ent._fk360BoneIdx   = ent:LookupBone(FK360_BONE) or -1
        ent._fk360StartTime = -9999
        ent._fk360Duration  = fk360Duration
        ent._fk360PulseLast = ent:GetNWInt("GekkoFrontKick360Pulse", 0)
        ent._fk360Yaw       = 0
        ent._fk360WasActive = false
    end

    local pulse = ent:GetNWInt("GekkoFrontKick360Pulse", 0)
    if pulse ~= ent._fk360PulseLast then
        ent._fk360PulseLast = pulse
        ent._fk360StartTime = CurTime()
        ent._fk360Yaw       = 0
        ent._fk360Duration  = JitterDur(fk360Duration)

        print(string.format("[GekkoFK360] pulse=%d  duration=%.2f",
            pulse, ent._fk360Duration))
    end

    local boneIdx = ent._fk360BoneIdx
    if not boneIdx or boneIdx < 0 then return end

    local elapsed = CurTime() - ent._fk360StartTime
    local active  = elapsed >= 0 and elapsed < ent._fk360Duration
    if not active then
        if ent._fk360WasActive then
            ent._fk360WasActive = false
            ent._fk360Yaw = 0
            ent:ManipulateBoneAngles(boneIdx, Angle(0, 0, 0), false)
        end
        return
    end

    ent._fk360WasActive = true

    local peakSpeed = 360.0 / ((1.0 - FK360_RAMP) * ent._fk360Duration)
    local t = elapsed / ent._fk360Duration

    local env
    if t < FK360_RAMP then
        env = Smoothstep(t / FK360_RAMP)
    elseif t > (1.0 - FK360_RAMP) then
        env = Smoothstep((1.0 - t) / FK360_RAMP)
    else
        env = 1.0
    end

    local dt = math.Clamp(CurTime() - (ent._fk360LastT or CurTime()), 0, 0.05)
    ent._fk360LastT = CurTime()

    ent._fk360Yaw = ent._fk360Yaw + peakSpeed * env * dt
    ent:ManipulateBoneAngles(boneIdx, Angle(0, ent._fk360Yaw, 0), false)
end

-- ============================================================
--  FK360B (FL360B) BONE DRIVER
--  5-step extended variant around the original FK360 spin.
--  Uses its own pulse (GekkoFrontKick360BPulse) but keeps the
--  spin envelope and land blast timing identical to FK360.
-- ============================================================
local function GekkoDoFK360BBone(ent)
    local fk360Duration = ent.FK360_DURATION or 0.9

    if ent._fk360BInited == nil then
        ent._fk360BInited    = true
        ent._fk360BPedIdx    = ent:LookupBone(FK360B_PED_BONE)    or -1
        ent._fk360BPistonIdx = ent:LookupBone(FK360B_PISTON_BONE) or -1
        ent._fk360BPelIdx    = ent:LookupBone(FK360B_PEL_BONE)    or -1
        ent._fk360BStartTime = -9999
        ent._fk360BSpinDur   = fk360Duration
        ent._fk360BTotalDur  = FK360B_PREP_DUR + FK360B_ELONGATE_DUR + fk360Duration + FK360B_LAND_DUR + FK360B_RESTORE_DUR
        ent._fk360BPulseLast = ent:GetNWInt("GekkoFrontKick360BPulse", 0)
        ent._fk360BYaw       = 0
        ent._fk360BWasActive = false
    end

    local pulse = ent:GetNWInt("GekkoFrontKick360BPulse", 0)
    if pulse ~= ent._fk360BPulseLast then
        ent._fk360BPulseLast = pulse
        ent._fk360BStartTime = CurTime()
        ent._fk360BYaw       = 0
        ent._fk360BSpinDur   = JitterDur(fk360Duration)
        ent._fk360BTotalDur  = FK360B_PREP_DUR + FK360B_ELONGATE_DUR + ent._fk360BSpinDur + FK360B_LAND_DUR + FK360B_RESTORE_DUR
        ent._fk360BLastT     = CurTime()

        print(string.format("[GekkoFK360B] pulse=%d  total=%.2f  spin=%.2f",
            pulse, ent._fk360BTotalDur, ent._fk360BSpinDur))
    end

    local pedIdx    = ent._fk360BPedIdx
    local pistonIdx = ent._fk360BPistonIdx
    local pelIdx    = ent._fk360BPelIdx

    if (not pedIdx or pedIdx < 0) and (not pistonIdx or pistonIdx < 0) and (not pelIdx or pelIdx < 0) then
        return
    end

    local elapsed = CurTime() - ent._fk360BStartTime
    local active  = elapsed >= 0 and elapsed < ent._fk360BTotalDur
    if not active then
        if ent._fk360BWasActive then
            ent._fk360BWasActive = false
            if pedIdx    >= 0 then ent:ManipulateBoneAngles(pedIdx, Angle(0,0,0), false) end
            if pistonIdx >= 0 then ent:ManipulateBoneAngles(pistonIdx, Angle(0,0,0), false) end
            if pelIdx    >= 0 then
                ent:ManipulateBoneAngles(pelIdx, Angle(0,0,0), false)
                ent:ManipulateBonePosition(pelIdx, Vector(0,0,0), false)
            end
        end
        return
    end

    ent._fk360BWasActive = true

    local t = elapsed
    local preEnd   = FK360B_PREP_DUR
    local elEnd    = preEnd + FK360B_ELONGATE_DUR
    local spinEnd  = elEnd + ent._fk360BSpinDur
    local landEnd  = spinEnd + FK360B_LAND_DUR
    local totalEnd = ent._fk360BTotalDur

    local function ApplyPedAndPiston(env)
        if pedIdx >= 0 then
            ent:ManipulateBoneAngles(pedIdx, Angle(0, 0, FK360B_PED_ROLL * env), false)
        end
        if pistonIdx >= 0 then
            ent:ManipulateBoneAngles(pistonIdx,
                Angle(FK360B_PISTON_PITCH * env,
                      FK360B_PISTON_YAW   * env,
                      0), false)
        end
    end

    if t < preEnd then
        -- 1) Preparation
        local env = Smoothstep(t / preEnd)
        ApplyPedAndPiston(env)
        if pelIdx >= 0 then
            ent:ManipulateBonePosition(pelIdx, Vector(0,0,0), false)
            ent:ManipulateBoneAngles(pelIdx, Angle(0, ent._fk360BYaw, 0), false)
        end
        return
    end

    if t < elEnd then
        -- 2) Elongation (pelvis Z up to 43)
        ApplyPedAndPiston(1.0)
        local env = Smoothstep((t - preEnd) / (elEnd - preEnd))
        if pelIdx >= 0 then
            ent:ManipulateBonePosition(pelIdx, Vector(0,0, FK360B_PEL_Z_ELONGATE * env), false)
            ent:ManipulateBoneAngles(pelIdx, Angle(0, ent._fk360BYaw, 0), false)
        end
        return
    end

    -- From here on pedestal & piston stay at full prep until restore.
    ApplyPedAndPiston(1.0)

    if t < spinEnd and pelIdx >= 0 then
        -- 3) Spin: identical envelope to FK360, but running only in this window
        local spinElapsed = t - elEnd
        local spinT       = spinElapsed / ent._fk360BSpinDur
        local peakSpeed   = 360.0 / ((1.0 - FK360_RAMP) * ent._fk360BSpinDur)

        local env
        if spinT < FK360_RAMP then
            env = Smoothstep(spinT / FK360_RAMP)
        elseif spinT > (1.0 - FK360_RAMP) then
            env = Smoothstep((1.0 - spinT) / FK360_RAMP)
        else
            env = 1.0
        end

        local now = CurTime()
        local dt  = math.Clamp(now - (ent._fk360BLastT or now), 0, 0.05)
        ent._fk360BLastT = now

        ent._fk360BYaw = ent._fk360BYaw + peakSpeed * env * dt

        ent:ManipulateBonePosition(pelIdx, Vector(0,0, FK360B_PEL_Z_ELONGATE), false)
        ent:ManipulateBoneAngles(pelIdx, Angle(0, ent._fk360BYaw, 0), false)
        return
    end

    if t < landEnd then
        -- 4) Land: pelvis Z drops from 43 to 22, keeping final spin yaw.
        local env = Smoothstep((t - spinEnd) / (landEnd - spinEnd))
        local z   = Lerp(env, FK360B_PEL_Z_ELONGATE, FK360B_PEL_Z_LAND)
        if pelIdx >= 0 then
            ent:ManipulateBonePosition(pelIdx, Vector(0,0, z), false)
            ent:ManipulateBoneAngles(pelIdx, Angle(0, ent._fk360BYaw, 0), false)
        end
        return
    end

    -- 5) Smooth restore to neutral without a second counter-spin.
    local env = Smoothstep((t - landEnd) / (totalEnd - landEnd))
    local z   = Lerp(env, FK360B_PEL_Z_LAND, 0)
    if pelIdx >= 0 then
        ent:ManipulateBonePosition(pelIdx, Vector(0,0, z), false)
        local yaw = ent._fk360BYaw
        if yaw > 180 or yaw < -180 then
            yaw = math.NormalizeAngle(yaw)
        end
        ent:ManipulateBoneAngles(pelIdx, Angle(0, yaw * (1.0 - env), 0), false)
    end

    ApplyPedAndPiston(1.0 - env)
end

-- ============================================================
--  SPINKICK BONE DRIVER
--  Jitter: randomised duration; jitter applied to hip/leg peak angles.
-- ============================================================
local function GekkoDoSpinKickBone(ent)
    if ent._skInited == nil then
        ent._skInited    = true
        ent._skPedIdx    = ent:LookupBone(SK_PED_BONE)  or -1
        ent._skPelIdx    = ent:LookupBone(SK_PEL_BONE)  or -1
        ent._skHipIdx    = ent:LookupBone(SK_HIP_BONE)  or -1
        ent._skUlegIdx   = ent:LookupBone(SK_ULEG_BONE) or -1
        ent._skStartTime = -9999
        ent._skDuration  = SK_DURATION
        ent._skPulseLast = ent:GetNWInt("GekkoSpinKickPulse", 0)
        ent._skYaw       = 0
        ent._skWasActive = false
        ent._skJitPelDrop = SK_PEL_DROP
        ent._skJitHipZ    = SK_HIP_Z
        ent._skJitUlegX   = SK_ULEG_X
    end

    local pulse = ent:GetNWInt("GekkoSpinKickPulse", 0)
    if pulse ~= ent._skPulseLast then
        ent._skPulseLast = pulse
        ent._skStartTime = CurTime()
        ent._skYaw       = 0
        ent._skDuration  = JitterDur(SK_DURATION)
        local function jf() return (math.random() - 0.5) * 2 * JITTER_DEG end
        ent._skJitPelDrop = SK_PEL_DROP + jf()
        ent._skJitHipZ    = SK_HIP_Z    + jf()
        ent._skJitUlegX   = SK_ULEG_X   + jf()

        print(string.format("[GekkoSpinKick] pulse=%d  dur=%.2f", pulse, ent._skDuration))
    end

    local elapsed = CurTime() - ent._skStartTime
    local active  = elapsed >= 0 and elapsed < ent._skDuration
    if not active then
        if ent._skWasActive then
            ent._skWasActive = false
            ent._skYaw = 0

            ReleaseHips(ent, "SPINKICK")

            if ent._skPedIdx  >= 0 then
                ent:ManipulateBoneAngles(ent._skPedIdx,    Angle(0, 0, 0),    false)
            end
            if ent._skPelIdx  >= 0 then
                ent:ManipulateBonePosition(ent._skPelIdx,  Vector(0, 0, 0),   false)
            end
            if ent._skHipIdx  >= 0 then
                ent:ManipulateBoneAngles(ent._skHipIdx,    Angle(0, 0, 0),    false)
            end
            if ent._skUlegIdx >= 0 then
                ent:ManipulateBoneAngles(ent._skUlegIdx,   Angle(0, 0, 0),    false)
            end
        end
        return
    end

    if not ClaimHips(ent, "SPINKICK") then return end
    ent._skWasActive = true

    local t  = elapsed / ent._skDuration
    local dt = math.Clamp(CurTime() - (ent._skLastT or CurTime()), 0, 0.05)
    ent._skLastT = CurTime()

    local peakSpeed = SK_YAW_TOTAL / ((1.0 - SK_RAMP) * ent._skDuration)

    local yawEnv
    if t < SK_RAMP then
        yawEnv = Smoothstep(t / SK_RAMP)
    elseif t < SK_P3_END then
        yawEnv = 1.0
    elseif t < SK_P4_END then
        local localT = (t - SK_P3_END) / (SK_P4_END - SK_P3_END)
        yawEnv = 1.0 - Smoothstep(Smoothstep(localT))
    else
        local localT = (t - SK_P4_END) / (1.0 - SK_P4_END)
        yawEnv = (1.0 - Smoothstep(Smoothstep(Smoothstep(localT)))) * 0.08
    end

    ent._skYaw = ent._skYaw + peakSpeed * yawEnv * dt

    if ent._skPedIdx >= 0 then
        ent:ManipulateBoneAngles(ent._skPedIdx, Angle(0, ent._skYaw, 0), false)
    end

    local crouchEnv
    if t < SK_P1_END then
        crouchEnv = 0
    elseif t < SK_P2_END then
        local localT = (t - SK_P1_END) / (SK_P2_END - SK_P1_END)
        crouchEnv = Smoothstep(localT)
    elseif t < SK_P3_END then
        crouchEnv = 1.0
    elseif t < SK_P4_END then
        local localT = (t - SK_P3_END) / (SK_P4_END - SK_P3_END)
        crouchEnv = 1.0 - Smoothstep(Smoothstep(localT))
    else
        local localT = (t - SK_P4_END) / (1.0 - SK_P4_END)
        crouchEnv = math.max(
            (1.0 - Smoothstep(Smoothstep(Smoothstep(localT)))) * 0.08,
            0
        )
    end

    local legEnv
    if t < SK_P1_END then
        legEnv = 0
    elseif t < SK_P3_END then
        legEnv = 1.0
    else
        legEnv = crouchEnv
    end

    if ent._skPelIdx  >= 0 then
        ent:ManipulateBonePosition(ent._skPelIdx,
            Vector(0, 0, ent._skJitPelDrop * crouchEnv), false)
    end
    if ent._skHipIdx  >= 0 then
        ent:ManipulateBoneAngles(ent._skHipIdx,
            Angle(0, 0, ent._skJitHipZ * crouchEnv), false)
    end
    if ent._skUlegIdx >= 0 then
        ent:ManipulateBoneAngles(ent._skUlegIdx,
            Angle(ent._skJitUlegX * legEnv, 0, 0), false)
    end
end

-- ============================================================
--  FOOTBALL KICK BONE DRIVER  (left leg)
--  Jitter: randomised duration; jitter baked into prep/ext angles.
-- ============================================================
local function GekkoDoFootballKickBone(ent)
    if ent._fkInited == nil then
        ent._fkInited    = true
        ent._fkLHipIdx   = ent:LookupBone(FK_LHIP_BONE) or -1
        ent._fkRHipIdx   = ent:LookupBone(FK_RHIP_BONE) or -1
        ent._fkStartTime = -9999
        ent._fkDuration  = FK_DURATION
        ent._fkPulseLast = ent:GetNWInt("GekkoFootballKickPulse", 0)
        ent._fkWasActive = false
        ent._fkJitLhipYPrep = FK_LHIP_Y_PREP
        ent._fkJitLhipXPrep = FK_LHIP_X_PREP
        ent._fkJitRhipXPrep = FK_RHIP_X_PREP
        ent._fkJitLhipYExt  = FK_LHIP_Y_EXT
    end

    local pulse = ent:GetNWInt("GekkoFootballKickPulse", 0)
    if pulse ~= ent._fkPulseLast then
        ent._fkPulseLast = pulse
        ent._fkStartTime = CurTime()
        ent._fkDuration  = JitterDur(FK_DURATION)
        local function jf() return (math.random() - 0.5) * 2 * JITTER_DEG end
        ent._fkJitLhipYPrep = FK_LHIP_Y_PREP + jf()
        ent._fkJitLhipXPrep = FK_LHIP_X_PREP + jf()
        ent._fkJitRhipXPrep = FK_RHIP_X_PREP + jf()
        ent._fkJitLhipYExt  = FK_LHIP_Y_EXT  + jf()

        print(string.format("[GekkoFootballKick] pulse=%d  dur=%.2f", pulse, ent._fkDuration))
    end

    local elapsed = CurTime() - ent._fkStartTime
    local active  = elapsed >= 0 and elapsed < ent._fkDuration
    if not active then
        if ent._fkWasActive then
            ent._fkWasActive = false

            ReleaseHips(ent, "FOOTBALLKICK")

            if ent._fkLHipIdx >= 0 then
                ent:ManipulateBoneAngles(ent._fkLHipIdx, Angle(0, 0, 0), false)
            end
            if ent._fkRHipIdx >= 0 then
                ent:ManipulateBoneAngles(ent._fkRHipIdx, Angle(0, 0, 0), false)
            end
        end
        return
    end

    if not ClaimHips(ent, "FOOTBALLKICK") then return end
    ent._fkWasActive = true

    local t = elapsed / ent._fkDuration

    local lhipY, lhipX, rhipX
    if t < FK_PHASE_HOLD then
        local env = Smoothstep(t / FK_PHASE_HOLD)
        lhipY =  ent._fkJitLhipYPrep * env
        lhipX =  ent._fkJitLhipXPrep * env
        rhipX =  ent._fkJitRhipXPrep * env
    elseif t < FK_PHASE_EXTEND then
        lhipY =  ent._fkJitLhipYPrep
        lhipX =  ent._fkJitLhipXPrep
        rhipX =  ent._fkJitRhipXPrep
    elseif t < FK_PHASE_RECOVER then
        local env = Smoothstep((t - FK_PHASE_EXTEND) / (FK_PHASE_RECOVER - FK_PHASE_EXTEND))
        lhipY = ent._fkJitLhipYPrep + (ent._fkJitLhipYExt - ent._fkJitLhipYPrep) * env
        lhipX = ent._fkJitLhipXPrep * (1 - env)
        rhipX = ent._fkJitRhipXPrep * (1 - env)
    else
        local env = Smoothstep((t - FK_PHASE_RECOVER) / (1.0 - FK_PHASE_RECOVER))
        lhipY = ent._fkJitLhipYExt * (1 - env)
        lhipX = 0
        rhipX = 0
    end

    if ent._fkLHipIdx >= 0 then
        ent:ManipulateBoneAngles(ent._fkLHipIdx, Angle(lhipX, lhipY, 0), false)
    end
    if ent._fkRHipIdx >= 0 then
        ent:ManipulateBoneAngles(ent._fkRHipIdx, Angle(rhipX, 0, 0),     false)
    end
end

-- ============================================================
--  FOOTBALL KICK MIRRORED BONE DRIVER  (right leg)
--  Jitter: same strategy as left-leg driver.
-- ============================================================
local function GekkoDoFootballKickRBone(ent)
    if ent._fkrInited == nil then
        ent._fkrInited    = true
        ent._fkrRHipIdx   = ent:LookupBone(FKR_RHIP_BONE) or -1
        ent._fkrLHipIdx   = ent:LookupBone(FKR_LHIP_BONE) or -1
        ent._fkrStartTime = -9999
        ent._fkrDuration  = FKR_DURATION
        ent._fkrPulseLast = ent:GetNWInt("GekkoRFootballKickPulse", 0)
        ent._fkrWasActive = false
        ent._fkrJitRhipYPrep = FKR_RHIP_Y_PREP
        ent._fkrJitRhipXPrep = FKR_RHIP_X_PREP
        ent._fkrJitLhipXPrep = FKR_LHIP_X_PREP
        ent._fkrJitRhipYExt  = FKR_RHIP_Y_EXT
    end

    local pulse = ent:GetNWInt("GekkoRFootballKickPulse", 0)
    if pulse ~= ent._fkrPulseLast then
        ent._fkrPulseLast = pulse
        ent._fkrStartTime = CurTime()
        ent._fkrDuration  = JitterDur(FKR_DURATION)
        local function jf() return (math.random() - 0.5) * 2 * JITTER_DEG end
        ent._fkrJitRhipYPrep = FKR_RHIP_Y_PREP + jf()
        ent._fkrJitRhipXPrep = FKR_RHIP_X_PREP + jf()
        ent._fkrJitLhipXPrep = FKR_LHIP_X_PREP + jf()
        ent._fkrJitRhipYExt  = FKR_RHIP_Y_EXT  + jf()

        print(string.format("[GekkoFootballKickR] pulse=%d  dur=%.2f", pulse, ent._fkrDuration))
    end

    local elapsed = CurTime() - ent._fkrStartTime
    local active  = elapsed >= 0 and elapsed < ent._fkrDuration
    if not active then
        if ent._fkrWasActive then
            ent._fkrWasActive = false

            ReleaseHips(ent, "FOOTBALLKICKR")

            if ent._fkrRHipIdx >= 0 then
                ent:ManipulateBoneAngles(ent._fkrRHipIdx, Angle(0, 0, 0), false)
            end
            if ent._fkrLHipIdx >= 0 then
                ent:ManipulateBoneAngles(ent._fkrLHipIdx, Angle(0, 0, 0), false)
            end
        end
        return
    end

    if not ClaimHips(ent, "FOOTBALLKICKR") then return end
    ent._fkrWasActive = true

    local t = elapsed / ent._fkrDuration

    local rhipY, rhipX, lhipX
    if t < FKR_PHASE_HOLD then
        local env = Smoothstep(t / FKR_PHASE_HOLD)
        rhipY =  ent._fkrJitRhipYPrep * env
        rhipX =  ent._fkrJitRhipXPrep * env
        lhipX =  ent._fkrJitLhipXPrep * env
    elseif t < FKR_PHASE_EXTEND then
        rhipY =  ent._fkrJitRhipYPrep
        rhipX =  ent._fkrJitRhipXPrep
        lhipX =  ent._fkrJitLhipXPrep
    elseif t < FKR_PHASE_RECOVER then
        local env = Smoothstep((t - FKR_PHASE_EXTEND) / (FKR_PHASE_RECOVER - FKR_PHASE_EXTEND))
        rhipY = ent._fkrJitRhipYPrep + (ent._fkrJitRhipYExt - ent._fkrJitRhipYPrep) * env
        rhipX = ent._fkrJitRhipXPrep * (1 - env)
        lhipX = ent._fkrJitLhipXPrep * (1 - env)
    else
        local env = Smoothstep((t - FKR_PHASE_RECOVER) / (1.0 - FKR_PHASE_RECOVER))
        rhipY = ent._fkrJitRhipYExt * (1 - env)
        rhipX = 0
        lhipX = 0
    end

    if ent._fkrRHipIdx >= 0 then
        ent:ManipulateBoneAngles(ent._fkrRHipIdx, Angle(rhipX, rhipY, 0), false)
    end
    if ent._fkrLHipIdx >= 0 then
        ent:ManipulateBoneAngles(ent._fkrLHipIdx, Angle(lhipX, 0, 0),     false)
    end
end

-- ============================================================
--  DIAGONAL KICK BONE DRIVER
--  Jitter: randomised duration; jitter baked into all 4 keyframe angles.
-- ============================================================
local function GekkoDoDiagonalKickBone(ent)
    if ent._dgkInited == nil then
        ent._dgkInited    = true
        ent._dgkLHipIdx   = ent:LookupBone(DGK_LHIP_BONE) or -1
        ent._dgkRHipIdx   = ent:LookupBone(DGK_RHIP_BONE) or -1
        ent._dgkStartTime = -9999
        ent._dgkDuration  = DGK_DURATION
        ent._dgkPulseLast = ent:GetNWInt("GekkoDiagonalKickPulse", 0)
        ent._dgkWasActive = false
        ent._dgkJitP1L = DGK_P1_LHIP
        ent._dgkJitP1R = DGK_P1_RHIP
        ent._dgkJitP3L = DGK_P3_LHIP
        ent._dgkJitP3R = DGK_P3_RHIP
        ent._dgkJitP4L = DGK_P4_LHIP
        ent._dgkJitP4R = DGK_P4_RHIP
    end

    local pulse = ent:GetNWInt("GekkoDiagonalKickPulse", 0)
    if pulse ~= ent._dgkPulseLast then
        ent._dgkPulseLast = pulse
        ent._dgkStartTime = CurTime()
        ent._dgkDuration  = JitterDur(DGK_DURATION)
        ent._dgkJitP1L = JitterAng(DGK_P1_LHIP)
        ent._dgkJitP1R = JitterAng(DGK_P1_RHIP)
        ent._dgkJitP3L = JitterAng(DGK_P3_LHIP)
        ent._dgkJitP3R = JitterAng(DGK_P3_RHIP)
        ent._dgkJitP4L = JitterAng(DGK_P4_LHIP)
        ent._dgkJitP4R = JitterAng(DGK_P4_RHIP)

        print(string.format("[GekkoDiagonalKick] pulse=%d  dur=%.2f", pulse, ent._dgkDuration))
    end

    local elapsed = CurTime() - ent._dgkStartTime
    local active  = elapsed >= 0 and elapsed < ent._dgkDuration
    if not active then
        if ent._dgkWasActive then
            ent._dgkWasActive = false

            ReleaseHips(ent, "DIAGONALKICK")

            if ent._dgkLHipIdx >= 0 then
                ent:ManipulateBoneAngles(ent._dgkLHipIdx, Angle(0, 0, 0), false)
            end
            if ent._dgkRHipIdx >= 0 then
                ent:ManipulateBoneAngles(ent._dgkRHipIdx, Angle(0, 0, 0), false)
            end
        end
        return
    end

    if not ClaimHips(ent, "DIAGONALKICK") then return end
    ent._dgkWasActive = true

    local t     = elapsed / ent._dgkDuration
    local lhip, rhip
    local REST  = Angle(0, 0, 0)

    if t < DGK_P1_END then
        local env = Smoothstep(t / DGK_P1_END)
        lhip = LerpAngle(REST,             ent._dgkJitP1L, env)
        rhip = LerpAngle(REST,             ent._dgkJitP1R, env)
    elseif t < DGK_P2_END then
        lhip = ent._dgkJitP1L
        rhip = ent._dgkJitP1R
    elseif t < DGK_P3_END then
        local env = Smoothstep((t - DGK_P2_END) / (DGK_P3_END - DGK_P2_END))
        lhip = LerpAngle(ent._dgkJitP1L, ent._dgkJitP3L, env)
        rhip = LerpAngle(ent._dgkJitP1R, ent._dgkJitP3R, env)
    elseif t < DGK_P4_END then
        local env = Smoothstep((t - DGK_P3_END) / (DGK_P4_END - DGK_P3_END))
        lhip = LerpAngle(ent._dgkJitP3L, ent._dgkJitP4L, env)
        rhip = LerpAngle(ent._dgkJitP3R, ent._dgkJitP4R, env)
    else
        local env = Smoothstep((t - DGK_P4_END) / (1.0 - DGK_P4_END))
        lhip = LerpAngle(ent._dgkJitP4L, REST, env)
        rhip = LerpAngle(ent._dgkJitP4R, REST, env)
    end

    if ent._dgkLHipIdx >= 0 then
        ent:ManipulateBoneAngles(ent._dgkLHipIdx, lhip, false)
    end
    if ent._dgkRHipIdx >= 0 then
        ent:ManipulateBoneAngles(ent._dgkRHipIdx, rhip, false)
    end
end

-- ============================================================
--  DIAGONAL KICK R BONE DRIVER  (right-leg primary variant)
--  Jitter: randomised duration; jitter baked into all keyframe
--  Angles at the moment each pulse fires, matching the original
--  DiagonalKick convention exactly.
--
--  5-segment timeline (normalised t):
--    [0          , P1_END] ramp  REST → P1  (chamber)
--    [P1_END     , P2_END] hold at P1
--    [P2_END     , P3_END] ramp  P1  → P2  (mid-extension)
--    [P3_END     , P4_END] ramp  P2  → P3  (peak strike)
--    [P4_END     , 1.0   ] ramp  P3  → REST (return)
-- ============================================================
local function GekkoDoDiagonalKickRBone(ent)
    if ent._dgkrInited == nil then
        ent._dgkrInited    = true
        ent._dgkrLHipIdx   = ent:LookupBone(DGKR_LHIP_BONE) or -1
        ent._dgkrRHipIdx   = ent:LookupBone(DGKR_RHIP_BONE) or -1
        ent._dgkrStartTime = -9999
        ent._dgkrDuration  = DGKR_DURATION
        ent._dgkrPulseLast = ent:GetNWInt("GekkoDiagonalKickRPulse", 0)
        ent._dgkrWasActive = false
        ent._dgkrJitP1L    = DGKR_P1_LHIP
        ent._dgkrJitP1R    = DGKR_P1_RHIP
        ent._dgkrJitP2L    = DGKR_P2_LHIP
        ent._dgkrJitP2R    = DGKR_P2_RHIP
        ent._dgkrJitP3L    = DGKR_P3_LHIP
        ent._dgkrJitP3R    = DGKR_P3_RHIP
    end

    local pulse = ent:GetNWInt("GekkoDiagonalKickRPulse", 0)
    if pulse ~= ent._dgkrPulseLast then
        ent._dgkrPulseLast = pulse
        ent._dgkrStartTime = CurTime()
        ent._dgkrDuration  = JitterDur(DGKR_DURATION)
        ent._dgkrJitP1L    = JitterAng(DGKR_P1_LHIP)
        ent._dgkrJitP1R    = JitterAng(DGKR_P1_RHIP)
        ent._dgkrJitP2L    = JitterAng(DGKR_P2_LHIP)
        ent._dgkrJitP2R    = JitterAng(DGKR_P2_RHIP)
        ent._dgkrJitP3L    = JitterAng(DGKR_P3_LHIP)
        ent._dgkrJitP3R    = JitterAng(DGKR_P3_RHIP)

        print(string.format("[GekkoDiagonalKickR] pulse=%d  dur=%.2f", pulse, ent._dgkrDuration))
    end

    local elapsed = CurTime() - ent._dgkrStartTime
    local active  = elapsed >= 0 and elapsed < ent._dgkrDuration
    if not active then
        if ent._dgkrWasActive then
            ent._dgkrWasActive = false

            ReleaseHips(ent, "DIAGONALKICKR")

            if ent._dgkrLHipIdx >= 0 then
                ent:ManipulateBoneAngles(ent._dgkrLHipIdx, Angle(0, 0, 0), false)
            end
            if ent._dgkrRHipIdx >= 0 then
                ent:ManipulateBoneAngles(ent._dgkrRHipIdx, Angle(0, 0, 0), false)
            end
        end
        return
    end

    if not ClaimHips(ent, "DIAGONALKICKR") then return end
    ent._dgkrWasActive = true

    local t    = elapsed / ent._dgkrDuration
    local lhip, rhip
    local REST = Angle(0, 0, 0)

    if t < DGKR_P1_END then
        -- ramp in from REST to step-1 chamber
        local env = Smoothstep(t / DGKR_P1_END)
        lhip = LerpAngle(REST,              ent._dgkrJitP1L, env)
        rhip = LerpAngle(REST,              ent._dgkrJitP1R, env)
    elseif t < DGKR_P2_END then
        -- hold at step-1 chamber
        lhip = ent._dgkrJitP1L
        rhip = ent._dgkrJitP1R
    elseif t < DGKR_P3_END then
        -- ramp step-1 → step-2 mid-extension
        local env = Smoothstep((t - DGKR_P2_END) / (DGKR_P3_END - DGKR_P2_END))
        lhip = LerpAngle(ent._dgkrJitP1L, ent._dgkrJitP2L, env)
        rhip = LerpAngle(ent._dgkrJitP1R, ent._dgkrJitP2R, env)
    elseif t < DGKR_P4_END then
        -- ramp step-2 → step-3 peak strike
        local env = Smoothstep((t - DGKR_P3_END) / (DGKR_P4_END - DGKR_P3_END))
        lhip = LerpAngle(ent._dgkrJitP2L, ent._dgkrJitP3L, env)
        rhip = LerpAngle(ent._dgkrJitP2R, ent._dgkrJitP3R, env)
    else
        -- return peak strike → REST
        local env = Smoothstep((t - DGKR_P4_END) / (1.0 - DGKR_P4_END))
        lhip = LerpAngle(ent._dgkrJitP3L, REST, env)
        rhip = LerpAngle(ent._dgkrJitP3R, REST, env)
    end

    if ent._dgkrLHipIdx >= 0 then
        ent:ManipulateBoneAngles(ent._dgkrLHipIdx, lhip, false)
    end
    if ent._dgkrRHipIdx >= 0 then
        ent:ManipulateBoneAngles(ent._dgkrRHipIdx, rhip, false)
    end
end

-- ============================================================
--  BITE BONE DRIVER
--  Forward lunge attack — drives both hip pistons, pelvis, and
--  b_spine3 across 5 phases.  b_spine3 is the correct lean bone;
--  b_spine4 is the head-tracker and must NOT be driven here.
--  Bones not keyed in a given phase hold their previous keyframe
--  (hip pistons hold P1 through P2; spine holds P2 through P3).
--  Full jitter on every keyframe Angle at pulse-fire time, plus
--  randomised duration.  Head tracking is suppressed for the full
--  duration via ent._biteHeadSuppress (read by GekkoUpdateHead).
-- ============================================================
local function GekkoDoBiteBone(ent)
    if ent._biteInited == nil then
        ent._biteInited    = true
        ent._biteLHipIdx   = ent:LookupBone(BITE_LHIP_BONE)   or -1
        ent._biteRHipIdx   = ent:LookupBone(BITE_RHIP_BONE)   or -1
        ent._bitePelvisIdx = ent:LookupBone(BITE_PELVIS_BONE) or -1
        ent._biteSpineIdx  = ent:LookupBone(BITE_SPINE4_BONE) or -1   -- b_spine3
        ent._bitePedIdx    = ent:LookupBone(BITE_PED_BONE)    or -1
        ent._biteStartTime = -9999
        ent._biteDuration  = BITE_DURATION
        ent._bitePulseLast = ent:GetNWInt("GekkoBitePulse", 0)
        ent._biteWasActive    = false
        ent._biteHeadSuppress = false
        -- initial jitter cache mirrors base constants
        ent._biteJitP0L  = BITE_P0_LHIP
        ent._biteJitP0R  = BITE_P0_RHIP
        ent._biteJitP0Pv = BITE_P0_PELVIS
        ent._biteJitP0S4 = BITE_P0_SPINE4
        ent._biteJitP1L  = BITE_P1_LHIP
        ent._biteJitP1R  = BITE_P1_RHIP
        ent._biteJitP1Pv = BITE_P1_PELVIS
        ent._biteJitP1S4 = BITE_P1_SPINE4
        ent._biteJitP2Pv = BITE_P2_PELVIS
        ent._biteJitP2S4 = BITE_P2_SPINE4
        ent._biteJitP3L  = BITE_P3_LHIP
        ent._biteJitP3R  = BITE_P3_RHIP
        ent._biteJitP3Pv = BITE_P3_PELVIS
        ent._biteJitP3S4 = BITE_P3_SPINE4
    end

    local pulse = ent:GetNWInt("GekkoBitePulse", 0)
    if pulse ~= ent._bitePulseLast then
        ent._bitePulseLast = pulse
        ent._biteStartTime = CurTime()
        ent._biteDuration  = JitterDur(BITE_DURATION)
        ent._biteJitP0L  = JitterAng(BITE_P0_LHIP)
        ent._biteJitP0R  = JitterAng(BITE_P0_RHIP)
        ent._biteJitP0Pv = JitterAng(BITE_P0_PELVIS)
        ent._biteJitP0S4 = JitterAng(BITE_P0_SPINE4)
        ent._biteJitP1L  = JitterAng(BITE_P1_LHIP)
        ent._biteJitP1R  = JitterAng(BITE_P1_RHIP)
        ent._biteJitP1Pv = JitterAng(BITE_P1_PELVIS)
        ent._biteJitP1S4 = JitterAng(BITE_P1_SPINE4)
        ent._biteJitP2Pv = JitterAng(BITE_P2_PELVIS)
        ent._biteJitP2S4 = JitterAng(BITE_P2_SPINE4)
        ent._biteJitP3L  = JitterAng(BITE_P3_LHIP)
        ent._biteJitP3R  = JitterAng(BITE_P3_RHIP)
        ent._biteJitP3Pv = JitterAng(BITE_P3_PELVIS)
        ent._biteJitP3S4 = JitterAng(BITE_P3_SPINE4)

        print(string.format("[GekkoBite] pulse=%d  dur=%.2f", pulse, ent._biteDuration))
    end

    local elapsed = CurTime() - ent._biteStartTime
    local active  = elapsed >= 0 and elapsed < ent._biteDuration
    if not active then
        if ent._biteWasActive then
            ent._biteWasActive    = false
            ent._biteHeadSuppress = false   -- restore head tracking
            ReleaseHips(ent, "BITE")
            if ent._biteLHipIdx   >= 0 then
                ent:ManipulateBoneAngles(ent._biteLHipIdx,   Angle(0,0,0), false)
            end
            if ent._biteRHipIdx   >= 0 then
                ent:ManipulateBoneAngles(ent._biteRHipIdx,   Angle(0,0,0), false)
            end
            if ent._bitePelvisIdx >= 0 then
                ent:ManipulateBoneAngles(ent._bitePelvisIdx,  Angle(0,0,0),  false)
                ent:ManipulateBonePosition(ent._bitePelvisIdx, Vector(0,0,0), false)
            end
            if ent._biteSpineIdx  >= 0 then
                ent:ManipulateBoneAngles(ent._biteSpineIdx,  Angle(0,0,0), false)
            end
            if ent._bitePedIdx    >= 0 then
                ent:ManipulateBonePosition(ent._bitePedIdx, Vector(0,0,0), false)
            end
        end
        return
    end

    if not ClaimHips(ent, "BITE") then return end
    ent._biteWasActive    = true
    ent._biteHeadSuppress = true   -- suppress GekkoUpdateHead for full duration

    local t    = elapsed / ent._biteDuration
    local REST = Angle(0, 0, 0)
    local lhip, rhip, pelvis, spine

    if t < BITE_P0_END then
        -- ramp REST → phase-0 wind-up
        local env = Smoothstep(t / BITE_P0_END)
        lhip   = LerpAngle(REST,              ent._biteJitP0L,  env)
        rhip   = LerpAngle(REST,              ent._biteJitP0R,  env)
        pelvis = REST
        spine  = REST

    elseif t < BITE_P1_END then
        -- ramp phase-0 → phase-1  (head charges backward)
        local env = Smoothstep((t - BITE_P0_END) / (BITE_P1_END - BITE_P0_END))
        lhip   = LerpAngle(ent._biteJitP0L,  ent._biteJitP1L,  env)
        rhip   = LerpAngle(ent._biteJitP0R,  ent._biteJitP1R,  env)
        pelvis = LerpAngle(ent._biteJitP0Pv, ent._biteJitP1Pv, env)
        spine  = REST   -- spine stays at rest through phase 1

    elseif t < BITE_P2_END then
        -- ramp phase-1 → phase-2  (body lean / spine charge)
        -- hip pistons hold their phase-1 value during this window
        local env = Smoothstep((t - BITE_P1_END) / (BITE_P2_END - BITE_P1_END))
        lhip   = ent._biteJitP1L
        rhip   = ent._biteJitP1R
        pelvis = LerpAngle(ent._biteJitP1Pv, ent._biteJitP2Pv, env)
        spine  = LerpAngle(ent._biteJitP1S4, ent._biteJitP2S4, env)

    elseif t < BITE_P3_END then
        -- ramp phase-2 → phase-3  (full bite strike)
        -- spine holds its phase-2 value; hips drive to phase-3
        local env = Smoothstep((t - BITE_P2_END) / (BITE_P3_END - BITE_P2_END))
        lhip   = LerpAngle(ent._biteJitP1L,  ent._biteJitP3L,  env)
        rhip   = LerpAngle(ent._biteJitP1R,  ent._biteJitP3R,  env)
        pelvis = LerpAngle(ent._biteJitP2Pv, ent._biteJitP3Pv, env)
        spine  = ent._biteJitP3S4   -- identical to P2 spine

    elseif t < BITE_P4_END then
        -- smooth return phase-3 → REST
        local env = Smoothstep((t - BITE_P3_END) / (BITE_P4_END - BITE_P3_END))
        lhip   = LerpAngle(ent._biteJitP3L,  REST, env)
        rhip   = LerpAngle(ent._biteJitP3R,  REST, env)
        pelvis = LerpAngle(ent._biteJitP3Pv, REST, env)
        spine  = LerpAngle(ent._biteJitP3S4, REST, env)

    else
        lhip   = REST
        rhip   = REST
        pelvis = REST
        spine  = REST
    end

    if ent._biteLHipIdx   >= 0 then
        ent:ManipulateBoneAngles(ent._biteLHipIdx,   lhip,   false)
    end
    if ent._biteRHipIdx   >= 0 then
        ent:ManipulateBoneAngles(ent._biteRHipIdx,   rhip,   false)
    end
    if ent._bitePelvisIdx >= 0 then
        ent:ManipulateBoneAngles(ent._bitePelvisIdx, pelvis, false)
    end
    if ent._biteSpineIdx  >= 0 then
        ent:ManipulateBoneAngles(ent._biteSpineIdx,  spine,  false)
    end

    -- Pedestal crouch: smooth arc for the full attack duration.
    -- Ramps down over first BITE_PED_RAMP fraction, holds at BITE_PED_Z
    -- through the strike, ramps back to 0 over the last BITE_PED_RAMP fraction.
    -- Writes position Z only — no angles — so it cannot conflict with
    -- FK360B (roll) or SpinKick (yaw) which only write pedestal angles.
    if ent._bitePedIdx >= 0 then
        local pedEnv
        if t < BITE_PED_RAMP then
            pedEnv = Smoothstep(t / BITE_PED_RAMP)
        elseif t > (1.0 - BITE_PED_RAMP) then
            pedEnv = Smoothstep((1.0 - t) / BITE_PED_RAMP)
        else
            pedEnv = 1.0
        end
        ent:ManipulateBonePosition(ent._bitePedIdx,
            Vector(0, 0, BITE_PED_Z * pedEnv), false)
    end
end

-- ============================================================
--  TORQUE KICK BONE DRIVER
--  Jitter: randomised duration; jitter baked into all 4 keyframe
--  Angle pairs at pulse-fire time.  Follows the exact same
--  ClaimHips + WasActive pattern as every other hip driver.
-- ============================================================
local function GekkoDoTorqueKickBone(ent)
    if ent._tkInited == nil then
        ent._tkInited    = true
        ent._tkLHipIdx   = ent:LookupBone(TK_LHIP_BONE) or -1
        ent._tkRHipIdx   = ent:LookupBone(TK_RHIP_BONE) or -1
        ent._tkStartTime = -9999
        ent._tkDuration  = TK_DURATION
        ent._tkPulseLast = ent:GetNWInt("GekkoTorqueKickPulse", 0)
        ent._tkWasActive = false
        ent._tkJitP1L    = TK_P1_LHIP
        ent._tkJitP1R    = TK_P1_RHIP
        ent._tkJitP2L    = TK_P2_LHIP
        ent._tkJitP2R    = TK_P2_RHIP
        ent._tkJitP3L    = TK_P3_LHIP
        ent._tkJitP3R    = TK_P3_RHIP
        ent._tkJitP4L    = TK_P4_LHIP
        ent._tkJitP4R    = TK_P4_RHIP
    end

    local pulse = ent:GetNWInt("GekkoTorqueKickPulse", 0)
    if pulse ~= ent._tkPulseLast then
        ent._tkPulseLast = pulse
        ent._tkStartTime = CurTime()
        ent._tkDuration  = JitterDur(TK_DURATION)
        ent._tkJitP1L    = JitterAng(TK_P1_LHIP)
        ent._tkJitP1R    = JitterAng(TK_P1_RHIP)
        ent._tkJitP2L    = JitterAng(TK_P2_LHIP)
        ent._tkJitP2R    = JitterAng(TK_P2_RHIP)
        ent._tkJitP3L    = JitterAng(TK_P3_LHIP)
        ent._tkJitP3R    = JitterAng(TK_P3_RHIP)
        ent._tkJitP4L    = JitterAng(TK_P4_LHIP)
        ent._tkJitP4R    = JitterAng(TK_P4_RHIP)

        print(string.format("[GekkoTorqueKick] pulse=%d  dur=%.2f", pulse, ent._tkDuration))
    end

    local elapsed = CurTime() - ent._tkStartTime
    local active  = elapsed >= 0 and elapsed < ent._tkDuration
    if not active then
        if ent._tkWasActive then
            ent._tkWasActive = false
            ReleaseHips(ent, "TORQUEKICK")
            if ent._tkLHipIdx >= 0 then
                ent:ManipulateBoneAngles(ent._tkLHipIdx, Angle(0,0,0), false)
            end
            if ent._tkRHipIdx >= 0 then
                ent:ManipulateBoneAngles(ent._tkRHipIdx, Angle(0,0,0), false)
            end
        end
        return
    end

    if not ClaimHips(ent, "TORQUEKICK") then return end
    ent._tkWasActive = true

    local t    = elapsed / ent._tkDuration
    local REST = Angle(0, 0, 0)
    local lhip, rhip

    if t < TK_P1_END then
        -- ramp REST → preparation
        local env = Smoothstep(t / TK_P1_END)
        lhip = LerpAngle(REST,           ent._tkJitP1L, env)
        rhip = LerpAngle(REST,           ent._tkJitP1R, env)

    elseif t < TK_P2_END then
        -- ramp preparation → posture
        local env = Smoothstep((t - TK_P1_END) / (TK_P2_END - TK_P1_END))
        lhip = LerpAngle(ent._tkJitP1L, ent._tkJitP2L, env)
        rhip = LerpAngle(ent._tkJitP1R, ent._tkJitP2R, env)

    elseif t < TK_P3_END then
        -- ramp posture → kick peak
        local env = Smoothstep((t - TK_P2_END) / (TK_P3_END - TK_P2_END))
        lhip = LerpAngle(ent._tkJitP2L, ent._tkJitP3L, env)
        rhip = LerpAngle(ent._tkJitP2R, ent._tkJitP3R, env)

    elseif t < TK_P4_END then
        -- ramp kick peak → recoil
        local env = Smoothstep((t - TK_P3_END) / (TK_P4_END - TK_P3_END))
        lhip = LerpAngle(ent._tkJitP3L, ent._tkJitP4L, env)
        rhip = LerpAngle(ent._tkJitP3R, ent._tkJitP4R, env)

    else
        -- smooth return recoil → REST
        local env = Smoothstep((t - TK_P4_END) / (1.0 - TK_P4_END))
        lhip = LerpAngle(ent._tkJitP4L, REST, env)
        rhip = LerpAngle(ent._tkJitP4R, REST, env)
    end

    if ent._tkLHipIdx >= 0 then
        ent:ManipulateBoneAngles(ent._tkLHipIdx, lhip, false)
    end
    if ent._tkRHipIdx >= 0 then
        ent:ManipulateBoneAngles(ent._tkRHipIdx, rhip, false)
    end
end

-- ============================================================
--  SPINNING CAPOEIRA BONE DRIVER
--  Drives both hip pistons AND pelvis (angles + position Z)
--  across 8 phases (7 keyframes + return).
--  Pelvis position Z starts accumulating at step 4 and is
--  zeroed cleanly in the inactive reset.
--  ClaimHips("SPINNINGCAPOEIRA") makes it mutually exclusive
--  with every other hip/pelvis driver.
--  Jitter: JitterAng on all angle keyframes; scalar jitter on
--  all pelvis Z values.
-- ============================================================
local function GekkoDoSpinningCapoeiraBone(ent)
    if ent._spcInited == nil then
        ent._spcInited    = true
        ent._spcLHipIdx   = ent:LookupBone(SPC_LHIP_BONE)   or -1
        ent._spcRHipIdx   = ent:LookupBone(SPC_RHIP_BONE)   or -1
        ent._spcPelIdx    = ent:LookupBone(SPC_PELVIS_BONE)  or -1
        ent._spcStartTime = -9999
        ent._spcDuration  = SPC_DURATION
        ent._spcPulseLast = ent:GetNWInt("GekkoSpinningCapoeiraPulse", 0)
        ent._spcWasActive = false
        -- jitter cache (initialised to base values)
        ent._spcJitP1L  = SPC_P1_LHIP  ;  ent._spcJitP1R  = SPC_P1_RHIP
        ent._spcJitP1Pv = SPC_P1_PELVIS;  ent._spcJitP1Pz = SPC_P1_PELZ
        ent._spcJitP2L  = SPC_P2_LHIP  ;  ent._spcJitP2R  = SPC_P2_RHIP
        ent._spcJitP2Pv = SPC_P2_PELVIS;  ent._spcJitP2Pz = SPC_P2_PELZ
        ent._spcJitP3L  = SPC_P3_LHIP  ;  ent._spcJitP3R  = SPC_P3_RHIP
        ent._spcJitP3Pv = SPC_P3_PELVIS;  ent._spcJitP3Pz = SPC_P3_PELZ
        ent._spcJitP4L  = SPC_P4_LHIP  ;  ent._spcJitP4R  = SPC_P4_RHIP
        ent._spcJitP4Pv = SPC_P4_PELVIS;  ent._spcJitP4Pz = SPC_P4_PELZ
        ent._spcJitP5L  = SPC_P5_LHIP  ;  ent._spcJitP5R  = SPC_P5_RHIP
        ent._spcJitP5Pv = SPC_P5_PELVIS;  ent._spcJitP5Pz = SPC_P5_PELZ
        ent._spcJitP6L  = SPC_P6_LHIP  ;  ent._spcJitP6R  = SPC_P6_RHIP
        ent._spcJitP6Pv = SPC_P6_PELVIS;  ent._spcJitP6Pz = SPC_P6_PELZ
        ent._spcJitP7L  = SPC_P7_LHIP  ;  ent._spcJitP7R  = SPC_P7_RHIP
        ent._spcJitP7Pv = SPC_P7_PELVIS;  ent._spcJitP7Pz = SPC_P7_PELZ
    end

    local pulse = ent:GetNWInt("GekkoSpinningCapoeiraPulse", 0)
    if pulse ~= ent._spcPulseLast then
        ent._spcPulseLast = pulse
        ent._spcStartTime = CurTime()
        ent._spcDuration  = JitterDur(SPC_DURATION)

        local function jf() return (math.random() - 0.5) * 2 * JITTER_DEG end

        ent._spcJitP1L  = JitterAng(SPC_P1_LHIP)  ;  ent._spcJitP1R  = JitterAng(SPC_P1_RHIP)
        ent._spcJitP1Pv = JitterAng(SPC_P1_PELVIS) ;  ent._spcJitP1Pz = SPC_P1_PELZ + jf()
        ent._spcJitP2L  = JitterAng(SPC_P2_LHIP)  ;  ent._spcJitP2R  = JitterAng(SPC_P2_RHIP)
        ent._spcJitP2Pv = JitterAng(SPC_P2_PELVIS) ;  ent._spcJitP2Pz = SPC_P2_PELZ + jf()
        ent._spcJitP3L  = JitterAng(SPC_P3_LHIP)  ;  ent._spcJitP3R  = JitterAng(SPC_P3_RHIP)
        ent._spcJitP3Pv = JitterAng(SPC_P3_PELVIS) ;  ent._spcJitP3Pz = SPC_P3_PELZ + jf()
        ent._spcJitP4L  = JitterAng(SPC_P4_LHIP)  ;  ent._spcJitP4R  = JitterAng(SPC_P4_RHIP)
        ent._spcJitP4Pv = JitterAng(SPC_P4_PELVIS) ;  ent._spcJitP4Pz = SPC_P4_PELZ + jf()
        ent._spcJitP5L  = JitterAng(SPC_P5_LHIP)  ;  ent._spcJitP5R  = JitterAng(SPC_P5_RHIP)
        ent._spcJitP5Pv = JitterAng(SPC_P5_PELVIS) ;  ent._spcJitP5Pz = SPC_P5_PELZ + jf()
        ent._spcJitP6L  = JitterAng(SPC_P6_LHIP)  ;  ent._spcJitP6R  = JitterAng(SPC_P6_RHIP)
        ent._spcJitP6Pv = JitterAng(SPC_P6_PELVIS) ;  ent._spcJitP6Pz = SPC_P6_PELZ + jf()
        ent._spcJitP7L  = JitterAng(SPC_P7_LHIP)  ;  ent._spcJitP7R  = JitterAng(SPC_P7_RHIP)
        ent._spcJitP7Pv = JitterAng(SPC_P7_PELVIS) ;  ent._spcJitP7Pz = SPC_P7_PELZ + jf()

        print(string.format("[GekkoSpinningCapoeira] pulse=%d  dur=%.2f", pulse, ent._spcDuration))
    end

    local elapsed = CurTime() - ent._spcStartTime
    local active  = elapsed >= 0 and elapsed < ent._spcDuration
    if not active then
        if ent._spcWasActive then
            ent._spcWasActive = false
            ReleaseHips(ent, "SPINNINGCAPOEIRA")
            if ent._spcLHipIdx >= 0 then
                ent:ManipulateBoneAngles(ent._spcLHipIdx, Angle(0,0,0), false)
            end
            if ent._spcRHipIdx >= 0 then
                ent:ManipulateBoneAngles(ent._spcRHipIdx, Angle(0,0,0), false)
            end
            if ent._spcPelIdx  >= 0 then
                ent:ManipulateBoneAngles(ent._spcPelIdx,   Angle(0,0,0),  false)
                ent:ManipulateBonePosition(ent._spcPelIdx, Vector(0,0,0), false)
            end
        end
        return
    end

    if not ClaimHips(ent, "SPINNINGCAPOEIRA") then return end
    ent._spcWasActive = true

    -- Rescale phase boundaries to the jitter-shortened duration.
    local d   = ent._spcDuration
    local t   = elapsed / d
    local REST = Angle(0, 0, 0)

    local p1 = SPC_P1_END
    local p2 = SPC_P2_END
    local p3 = SPC_P3_END
    local p4 = SPC_P4_END
    local p5 = SPC_P5_END
    local p6 = SPC_P6_END
    local p7 = SPC_P7_END

    local lhip, rhip, pelAng, pelZ

    if t < p1 then
        local env = Smoothstep(t / p1)
        lhip   = LerpAngle(REST,              ent._spcJitP1L,  env)
        rhip   = LerpAngle(REST,              ent._spcJitP1R,  env)
        pelAng = LerpAngle(REST,              ent._spcJitP1Pv, env)
        pelZ   = Lerp(env, 0, ent._spcJitP1Pz)

    elseif t < p2 then
        local env = Smoothstep((t - p1) / (p2 - p1))
        lhip   = LerpAngle(ent._spcJitP1L,  ent._spcJitP2L,  env)
        rhip   = LerpAngle(ent._spcJitP1R,  ent._spcJitP2R,  env)
        pelAng = LerpAngle(ent._spcJitP1Pv, ent._spcJitP2Pv, env)
        pelZ   = Lerp(env, ent._spcJitP1Pz, ent._spcJitP2Pz)

    elseif t < p3 then
        local env = Smoothstep((t - p2) / (p3 - p2))
        lhip   = LerpAngle(ent._spcJitP2L,  ent._spcJitP3L,  env)
        rhip   = LerpAngle(ent._spcJitP2R,  ent._spcJitP3R,  env)
        pelAng = LerpAngle(ent._spcJitP2Pv, ent._spcJitP3Pv, env)
        pelZ   = Lerp(env, ent._spcJitP2Pz, ent._spcJitP3Pz)

    elseif t < p4 then
        local env = Smoothstep((t - p3) / (p4 - p3))
        lhip   = LerpAngle(ent._spcJitP3L,  ent._spcJitP4L,  env)
        rhip   = LerpAngle(ent._spcJitP3R,  ent._spcJitP4R,  env)
        pelAng = LerpAngle(ent._spcJitP3Pv, ent._spcJitP4Pv, env)
        pelZ   = Lerp(env, ent._spcJitP3Pz, ent._spcJitP4Pz)

    elseif t < p5 then
        local env = Smoothstep((t - p4) / (p5 - p4))
        lhip   = LerpAngle(ent._spcJitP4L,  ent._spcJitP5L,  env)
        rhip   = LerpAngle(ent._spcJitP4R,  ent._spcJitP5R,  env)
        pelAng = LerpAngle(ent._spcJitP4Pv, ent._spcJitP5Pv, env)
        pelZ   = Lerp(env, ent._spcJitP4Pz, ent._spcJitP5Pz)

    elseif t < p6 then
        local env = Smoothstep((t - p5) / (p6 - p5))
        lhip   = LerpAngle(ent._spcJitP5L,  ent._spcJitP6L,  env)
        rhip   = LerpAngle(ent._spcJitP5R,  ent._spcJitP6R,  env)
        pelAng = LerpAngle(ent._spcJitP5Pv, ent._spcJitP6Pv, env)
        pelZ   = Lerp(env, ent._spcJitP5Pz, ent._spcJitP6Pz)

    elseif t < p7 then
        local env = Smoothstep((t - p6) / (p7 - p6))
        lhip   = LerpAngle(ent._spcJitP6L,  ent._spcJitP7L,  env)
        rhip   = LerpAngle(ent._spcJitP6R,  ent._spcJitP7R,  env)
        pelAng = LerpAngle(ent._spcJitP6Pv, ent._spcJitP7Pv, env)
        pelZ   = Lerp(env, ent._spcJitP6Pz, ent._spcJitP7Pz)

    else
        -- smooth return P7 → REST
        local env = Smoothstep((t - p7) / (1.0 - p7))
        lhip   = LerpAngle(ent._spcJitP7L,  REST, env)
        rhip   = LerpAngle(ent._spcJitP7R,  REST, env)
        pelAng = LerpAngle(ent._spcJitP7Pv, REST, env)
        pelZ   = Lerp(env, ent._spcJitP7Pz, 0)
    end

    if ent._spcLHipIdx >= 0 then
        ent:ManipulateBoneAngles(ent._spcLHipIdx, lhip,   false)
    end
    if ent._spcRHipIdx >= 0 then
        ent:ManipulateBoneAngles(ent._spcRHipIdx, rhip,   false)
    end
    if ent._spcPelIdx  >= 0 then
        ent:ManipulateBoneAngles(ent._spcPelIdx,   pelAng,          false)
        ent:ManipulateBonePosition(ent._spcPelIdx, Vector(0,0,pelZ), false)
    end
end

-- ============================================================
--  HEEL HOOK BONE DRIVER
--  Jitter: randomised duration; jitter on all scalar peak values.
-- ============================================================
local function GekkoDoHeelHookBone(ent)
    if ent._hhInited == nil then
        ent._hhInited    = true
        ent._hhHipIdx    = ent:LookupBone(HH_HIP_BONE)    or -1
        ent._hhPelIdx    = ent:LookupBone(HH_PELVIS_BONE) or -1
        ent._hhSpineIdx  = ent:LookupBone(HH_SPINE_BONE)  or -1
        ent._hhStartTime = -9999
        ent._hhDuration  = HH_DURATION_CL
        ent._hhPulseLast = ent:GetNWInt("GekkoHeelHookPulse", 0)
        ent._hhWasActive = false
        ent._hhJitChamberPitch = HH_HIP_CHAMBER_PITCH
        ent._hhJitExtendRoll   = HH_HIP_EXTEND_ROLL
        ent._hhJitHookYaw      = HH_HIP_HOOK_YAW
        ent._hhJitPelYaw       = HH_PELVIS_YAW
        ent._hhJitPelPitch     = HH_PELVIS_PITCH
        ent._hhJitSpineLean    = HH_SPINE_LEAN
    end

    local pulse = ent:GetNWInt("GekkoHeelHookPulse", 0)
    if pulse ~= ent._hhPulseLast then
        ent._hhPulseLast = pulse
        ent._hhStartTime = CurTime()
        ent._hhDuration  = JitterDur(HH_DURATION_CL)
        local function jf() return (math.random() - 0.5) * 2 * JITTER_DEG end
        ent._hhJitChamberPitch = HH_HIP_CHAMBER_PITCH + jf()
        ent._hhJitExtendRoll   = HH_HIP_EXTEND_ROLL   + jf()
        ent._hhJitHookYaw      = HH_HIP_HOOK_YAW      + jf()
        ent._hhJitPelYaw       = HH_PELVIS_YAW        + jf()
        ent._hhJitPelPitch     = HH_PELVIS_PITCH       + jf()
        ent._hhJitSpineLean    = HH_SPINE_LEAN         + jf()

        print(string.format("[GekkoHeelHook] pulse=%d  dur=%.2f", pulse, ent._hhDuration))
    end

    local elapsed = CurTime() - ent._hhStartTime
    local active  = elapsed >= 0 and elapsed < ent._hhDuration
    if not active then
        if ent._hhWasActive then
            ent._hhWasActive = false

            ReleaseHips(ent, "HEELHOOK")

            if ent._hhHipIdx   >= 0 then
                ent:ManipulateBoneAngles(ent._hhHipIdx,   Angle(0, 0, 0), false)
            end
            if ent._hhPelIdx   >= 0 then
                ent:ManipulateBoneAngles(ent._hhPelIdx,   Angle(0, 0, 0), false)
            end
            if ent._hhSpineIdx >= 0 then
                ent:ManipulateBoneAngles(ent._hhSpineIdx, Angle(0, 0, 0), false)
            end
        end
        return
    end

    if not ClaimHips(ent, "HEELHOOK") then return end
    ent._hhWasActive = true

    local t    = elapsed / ent._hhDuration
    local P1   = 0.200
    local P2   = 0.440
    local P3   = 0.650
    local P4   = 0.800

    local function PhaseEnv(t0, t1)
        return Smoothstep(math.Clamp((t - t0) / (t1 - t0), 0, 1))
    end

    local hipPitch, hipRoll, hipYaw
    if t < P1 then
        hipPitch = ent._hhJitChamberPitch * PhaseEnv(0, P1)
        hipRoll  = 0
        hipYaw   = 0
    elseif t < P2 then
        hipPitch = ent._hhJitChamberPitch
        hipRoll  = 0
        hipYaw   = 0
    elseif t < P3 then
        hipPitch = ent._hhJitChamberPitch
        hipRoll  = ent._hhJitExtendRoll * PhaseEnv(P2, P3)
        hipYaw   = 0
    elseif t < P4 then
        local env = PhaseEnv(P3, P4)
        hipPitch = ent._hhJitChamberPitch * (1 - env * 0.3)
        hipRoll  = ent._hhJitExtendRoll   * (1 - env)
        hipYaw   = ent._hhJitHookYaw      * env
    else
        local env = PhaseEnv(P4, 1.0)
        hipPitch = ent._hhJitChamberPitch * (0.7 - env * 0.7)
        hipRoll  = 0
        hipYaw   = ent._hhJitHookYaw * (1 - env)
    end

    if ent._hhHipIdx >= 0 then
        ent:ManipulateBoneAngles(ent._hhHipIdx,
            Angle(hipPitch, hipYaw, hipRoll), false)
    end

    local pelYaw, pelPitch
    if t < P1 then
        pelYaw   = ent._hhJitPelYaw * PhaseEnv(0, P1) * 0.5
        pelPitch = 0
    elseif t < P2 then
        pelYaw   = ent._hhJitPelYaw * (0.5 + 0.5 * PhaseEnv(P1, P2))
        pelPitch = 0
    elseif t < P3 then
        pelYaw   = ent._hhJitPelYaw
        pelPitch = ent._hhJitPelPitch * PhaseEnv(P2, P3)
    elseif t < P4 then
        local env = PhaseEnv(P3, P4)
        pelYaw   = ent._hhJitPelYaw   * (1 - env * 0.6)
        pelPitch = ent._hhJitPelPitch * (1 - env)
    else
        pelYaw   = ent._hhJitPelYaw * 0.4 * (1 - PhaseEnv(P4, 1.0))
        pelPitch = 0
    end

    if ent._hhPelIdx >= 0 then
        ent:ManipulateBoneAngles(ent._hhPelIdx,
            Angle(pelPitch, pelYaw, 0), false)
    end

    local spineLean
    if t < P1 then
        spineLean = 0
    elseif t < P3 then
        spineLean = ent._hhJitSpineLean * PhaseEnv(P1, P3)
    elseif t < P4 then
        spineLean = ent._hhJitSpineLean
    else
        spineLean = ent._hhJitSpineLean * (1 - PhaseEnv(P4, 1.0))
    end

    if ent._hhSpineIdx >= 0 then
        ent:ManipulateBoneAngles(ent._hhSpineIdx,
            Angle(0, 0, spineLean), false)
    end
end

-- ============================================================
--  SIDE HOOK KICK BONE DRIVER
--  Jitter: randomised duration; jitter baked into all keyframe Angles.
-- ============================================================
local function GekkoDoSideHookKickBone(ent)
    if ent._shkInited == nil then
        ent._shkInited    = true
        ent._shkLHipIdx   = ent:LookupBone(SHK_LHIP_BONE) or -1
        ent._shkRHipIdx   = ent:LookupBone(SHK_RHIP_BONE) or -1
        ent._shkStartTime = -9999
        ent._shkDuration  = SHK_DURATION
        ent._shkPulseLast = ent:GetNWInt("GekkoSideHookKickPulse", 0)
        ent._shkWasActive = false
        ent._shkJitP1L = SHK_P1_LHIP
        ent._shkJitP1R = SHK_P1_RHIP
        ent._shkJitP2L = SHK_P2_LHIP
        ent._shkJitP2R = SHK_P2_RHIP
        ent._shkJitP3R = SHK_P3_RHIP
        ent._shkJitP4L = SHK_P4_LHIP
        ent._shkJitP4R = SHK_P4_RHIP
    end

    local pulse = ent:GetNWInt("GekkoSideHookKickPulse", 0)
    if pulse ~= ent._shkPulseLast then
        ent._shkPulseLast = pulse
        ent._shkStartTime = CurTime()
        ent._shkDuration  = JitterDur(SHK_DURATION)
        ent._shkJitP1L = JitterAng(SHK_P1_LHIP)
        ent._shkJitP1R = JitterAng(SHK_P1_RHIP)
        ent._shkJitP2L = JitterAng(SHK_P2_LHIP)
        ent._shkJitP2R = JitterAng(SHK_P2_RHIP)
        ent._shkJitP3R = JitterAng(SHK_P3_RHIP)
        ent._shkJitP4L = JitterAng(SHK_P4_LHIP)
        ent._shkJitP4R = JitterAng(SHK_P4_RHIP)

        print(string.format("[GekkoSideHookKick] pulse=%d  dur=%.2f", pulse, ent._shkDuration))
    end

    local elapsed = CurTime() - ent._shkStartTime
    local active  = elapsed >= 0 and elapsed < ent._shkDuration
    if not active then
        if ent._shkWasActive then
            ent._shkWasActive = false

            ReleaseHips(ent, "SIDEHOOKKICK")

            if ent._shkLHipIdx >= 0 then
                ent:ManipulateBoneAngles(ent._shkLHipIdx, Angle(0, 0, 0), false)
            end
            if ent._shkRHipIdx >= 0 then
                ent:ManipulateBoneAngles(ent._shkRHipIdx, Angle(0, 0, 0), false)
            end
        end
        return
    end

    if not ClaimHips(ent, "SIDEHOOKKICK") then return end
    ent._shkWasActive = true

    local t    = elapsed / ent._shkDuration
    local REST = SHK_REST

    local lhip, rhip
    if t < SHK_P1_END then
        local env = Smoothstep(t / SHK_P1_END)
        lhip = LerpAngle(REST, ent._shkJitP1L, env)
        rhip = LerpAngle(REST, ent._shkJitP1R, env)
    elseif t < SHK_P2_END then
        local env = Smoothstep((t - SHK_P1_END) / (SHK_P2_END - SHK_P1_END))
        lhip = LerpAngle(ent._shkJitP1L, ent._shkJitP2L, env)
        rhip = LerpAngle(ent._shkJitP1R, ent._shkJitP2R, env)
    elseif t < SHK_P3_END then
        local env = Smoothstep((t - SHK_P2_END) / (SHK_P3_END - SHK_P2_END))
        lhip = ent._shkJitP2L
        rhip = LerpAngle(ent._shkJitP2R, ent._shkJitP3R, env)
    elseif t < SHK_P4_END then
        local env = Smoothstep((t - SHK_P3_END) / (SHK_P4_END - SHK_P3_END))
        lhip = LerpAngle(ent._shkJitP2L, ent._shkJitP4L, env)
        rhip = LerpAngle(ent._shkJitP3R, ent._shkJitP4R, env)
    else
        local env = Smoothstep((t - SHK_P4_END) / (1.0 - SHK_P4_END))
        lhip = LerpAngle(ent._shkJitP4L, REST, env)
        rhip = LerpAngle(ent._shkJitP4R, REST, env)
    end

    if ent._shkLHipIdx >= 0 then
        ent:ManipulateBoneAngles(ent._shkLHipIdx, lhip, false)
    end
    if ent._shkRHipIdx >= 0 then
        ent:ManipulateBoneAngles(ent._shkRHipIdx, rhip, false)
    end
end

-- ============================================================
--  AXE KICK BONE DRIVER (left leg original)
--  Jitter: randomised duration; jitter baked into keyframe Angles.
-- ============================================================
local function GekkoDoAxeKickBone(ent)
    if ent._akInited == nil then
        ent._akInited    = true
        ent._akLHipIdx   = ent:LookupBone(AK_LHIP_BONE)  or -1
        ent._akRHipIdx   = ent:LookupBone(AK_RHIP_BONE)  or -1
        ent._akSpineIdx  = ent:LookupBone(AK_SPINE_BONE) or -1
        ent._akStartTime = -9999
        ent._akDuration  = AK_DURATION
        ent._akPulseLast = ent:GetNWInt("GekkoAxeKickPulse", 0)
        ent._akWasActive = false
        ent._akJitP1L  = AK_P1_LHIP
        ent._akJitP1S  = AK_P1_SPINE
        ent._akJitP3L  = AK_P3_LHIP
        ent._akJitP3R  = AK_P3_RHIP
        ent._akJitP3S  = AK_P3_SPINE
    end

    local pulse = ent:GetNWInt("GekkoAxeKickPulse", 0)
    if pulse ~= ent._akPulseLast then
        ent._akPulseLast = pulse
        ent._akStartTime = CurTime()
        ent._akDuration  = JitterDur(AK_DURATION)
        ent._akJitP1L  = JitterAng(AK_P1_LHIP)
        ent._akJitP1S  = JitterAng(AK_P1_SPINE)
        ent._akJitP3L  = JitterAng(AK_P3_LHIP)
        ent._akJitP3R  = JitterAng(AK_P3_RHIP)
        ent._akJitP3S  = JitterAng(AK_P3_SPINE)

        print(string.format("[GekkoAxeKick] pulse=%d  dur=%.2f", pulse, ent._akDuration))
    end

    local elapsed = CurTime() - ent._akStartTime
    local active  = elapsed >= 0 and elapsed < ent._akDuration
    if not active then
        if ent._akWasActive then
            ent._akWasActive = false

            ReleaseHips(ent, "AXEKICK")

            if ent._akLHipIdx  >= 0 then
                ent:ManipulateBoneAngles(ent._akLHipIdx,  Angle(0,0,0), false)
            end
            if ent._akRHipIdx  >= 0 then
                ent:ManipulateBoneAngles(ent._akRHipIdx,  Angle(0,0,0), false)
            end
            if ent._akSpineIdx >= 0 then
                ent:ManipulateBoneAngles(ent._akSpineIdx, Angle(0,0,0), false)
            end
        end
        return
    end

    if not ClaimHips(ent, "AXEKICK") then return end
    ent._akWasActive = true

    local t    = elapsed / ent._akDuration
    local REST = AK_REST

    local lhip, rhip, spine
    if t < AK_P1_END then
        local env = Smoothstep(t / AK_P1_END)
        lhip  = LerpAngle(REST, ent._akJitP1L, env)
        rhip  = REST
        spine = LerpAngle(REST, ent._akJitP1S, env)
    elseif t < AK_P2_END then
        lhip  = ent._akJitP1L
        rhip  = REST
        spine = ent._akJitP1S
    elseif t < AK_P3_END then
        local env = Smoothstep(Smoothstep((t - AK_P2_END) / (AK_P3_END - AK_P2_END)))
        lhip  = LerpAngle(ent._akJitP1L, ent._akJitP3L, env)
        rhip  = LerpAngle(REST,          ent._akJitP3R, env)
        spine = LerpAngle(ent._akJitP1S, ent._akJitP3S, env)
    else
        local env = Smoothstep((t - AK_P3_END) / (1.0 - AK_P3_END))
        lhip  = LerpAngle(ent._akJitP3L, REST, env)
        rhip  = LerpAngle(ent._akJitP3R, REST, env)
        spine = LerpAngle(ent._akJitP3S, REST, env)
    end

    if ent._akLHipIdx  >= 0 then
        ent:ManipulateBoneAngles(ent._akLHipIdx,  lhip,  false)
    end
    if ent._akRHipIdx  >= 0 then
        ent:ManipulateBoneAngles(ent._akRHipIdx,  rhip,  false)
    end
    if ent._akSpineIdx >= 0 then
        ent:ManipulateBoneAngles(ent._akSpineIdx, spine, false)
    end
end

-- ============================================================
--  AXE KICK BONE DRIVER (right leg mirror)
--  Jitter: same strategy as left-leg axe kick.
-- ============================================================
local function GekkoDoAxeKickRBone(ent)
    if ent._akrInited == nil then
        ent._akrInited    = true
        ent._akrLHipIdx   = ent:LookupBone("b_r_hippiston1")  or -1
        ent._akrRHipIdx   = ent:LookupBone("b_l_hippiston1")  or -1
        ent._akrSpineIdx  = ent:LookupBone(AK_SPINE_BONE) or -1
        ent._akrStartTime = -9999
        ent._akrDuration  = AK_DURATION
        ent._akrPulseLast = ent:GetNWInt("GekkoRAxeKickPulse", 0)
        ent._akrWasActive = false
        ent._akrJitP1L  = AK_P1_LHIP
        ent._akrJitP1S  = AK_P1_SPINE
        ent._akrJitP3L  = AK_P3_LHIP
        ent._akrJitP3R  = AK_P3_RHIP
        ent._akrJitP3S  = AK_P3_SPINE
    end

    local pulse = ent:GetNWInt("GekkoRAxeKickPulse", 0)
    if pulse ~= ent._akrPulseLast then
        ent._akrPulseLast = pulse
        ent._akrStartTime = CurTime()
        ent._akrDuration  = JitterDur(AK_DURATION)
        ent._akrJitP1L  = JitterAng(AK_P1_LHIP)
        ent._akrJitP1S  = JitterAng(AK_P1_SPINE)
        ent._akrJitP3L  = JitterAng(AK_P3_LHIP)
        ent._akrJitP3R  = JitterAng(AK_P3_RHIP)
        ent._akrJitP3S  = JitterAng(AK_P3_SPINE)

        print(string.format("[GekkoRAxeKick] pulse=%d  dur=%.2f", pulse, ent._akrDuration))
    end

    local elapsed = CurTime() - ent._akrStartTime
    local active  = elapsed >= 0 and elapsed < ent._akrDuration
    if not active then
        if ent._akrWasActive then
            ent._akrWasActive = false

            ReleaseHips(ent, "RAXEKICK")

            if ent._akrLHipIdx  >= 0 then
                ent:ManipulateBoneAngles(ent._akrLHipIdx,  Angle(0,0,0), false)
            end
            if ent._akrRHipIdx  >= 0 then
                ent:ManipulateBoneAngles(ent._akrRHipIdx,  Angle(0,0,0), false)
            end
            if ent._akrSpineIdx >= 0 then
                ent:ManipulateBoneAngles(ent._akrSpineIdx, Angle(0,0,0), false)
            end
        end
        return
    end

    if not ClaimHips(ent, "RAXEKICK") then return end
    ent._akrWasActive = true

    local t    = elapsed / ent._akrDuration
    local REST = AK_REST

    local lhip, rhip, spine
    if t < AK_P1_END then
        local env = Smoothstep(t / AK_P1_END)
        lhip  = LerpAngle(REST, ent._akrJitP1L, env)
        rhip  = REST
        spine = LerpAngle(REST, ent._akrJitP1S, env)
    elseif t < AK_P2_END then
        lhip  = ent._akrJitP1L
        rhip  = REST
        spine = ent._akrJitP1S
    elseif t < AK_P3_END then
        local env = Smoothstep(Smoothstep((t - AK_P2_END) / (AK_P3_END - AK_P2_END)))
        lhip  = LerpAngle(ent._akrJitP1L, ent._akrJitP3L, env)
        rhip  = LerpAngle(REST,           ent._akrJitP3R, env)
        spine = LerpAngle(ent._akrJitP1S, ent._akrJitP3S, env)
    else
        local env = Smoothstep((t - AK_P3_END) / (1.0 - AK_P3_END))
        lhip  = LerpAngle(ent._akrJitP3L, REST, env)
        rhip  = LerpAngle(ent._akrJitP3R, REST, env)
        spine = LerpAngle(ent._akrJitP3S, REST, env)
    end

    if ent._akrLHipIdx  >= 0 then
        ent:ManipulateBoneAngles(ent._akrLHipIdx,  lhip,  false)
    end
    if ent._akrRHipIdx  >= 0 then
        ent:ManipulateBoneAngles(ent._akrRHipIdx,  rhip,  false)
    end
    if ent._akrSpineIdx >= 0 then
        ent:ManipulateBoneAngles(ent._akrSpineIdx, spine, false)
    end
end

-- ============================================================
--  JUMP KICK BONE DRIVER
--  Jitter: randomised duration; jitter baked into keyframe Angles.
-- ============================================================
local function GekkoDoJumpKickBone(ent)
    if ent._jkInited == nil then
        ent._jkInited    = true
        ent._jkLHipIdx   = ent:LookupBone(JK_LHIP_BONE) or -1
        ent._jkRHipIdx   = ent:LookupBone(JK_RHIP_BONE) or -1
        ent._jkPedIdx    = ent:LookupBone(JK_PED_BONE)  or -1
        ent._jkStartTime = -9999
        ent._jkDuration  = JK_DURATION
        ent._jkPulseLast = ent:GetNWInt("GekkoJumpKickPulse", 0)
        ent._jkWasActive = false
        ent._jkJitP1L   = JK_P1_LHIP
        ent._jkJitP1R   = JK_P1_RHIP
        ent._jkJitP2L   = JK_P2_LHIP
        ent._jkJitP2R   = JK_P2_RHIP
        ent._jkJitP3L   = JK_P3_LHIP
        ent._jkJitP3PA  = JK_P3_PED_ANG
    end

    local pulse = ent:GetNWInt("GekkoJumpKickPulse", 0)
    if pulse ~= ent._jkPulseLast then
        ent._jkPulseLast = pulse
        ent._jkStartTime = CurTime()
        ent._jkDuration  = JitterDur(JK_DURATION)
        ent._jkJitP1L   = JitterAng(JK_P1_LHIP)
        ent._jkJitP1R   = JitterAng(JK_P2_RHIP)
        ent._jkJitP2L   = JitterAng(JK_P2_LHIP)
        ent._jkJitP2R   = JitterAng(JK_P2_RHIP)
        ent._jkJitP3L   = JitterAng(JK_P3_LHIP)
        ent._jkJitP3PA  = JitterAng(JK_P3_PED_ANG)

        print(string.format("[GekkoJumpKick] pulse=%d  dur=%.2f", pulse, ent._jkDuration))
    end

    local elapsed = CurTime() - ent._jkStartTime
    local active  = elapsed >= 0 and elapsed < ent._jkDuration
    if not active then
        if ent._jkWasActive then
            ent._jkWasActive = false

            ReleaseHips(ent, "JUMPKICK")

            if ent._jkLHipIdx >= 0 then
                ent:ManipulateBoneAngles(ent._jkLHipIdx,    JK_REST,     false)
            end
            if ent._jkRHipIdx >= 0 then
                ent:ManipulateBoneAngles(ent._jkRHipIdx,    JK_REST,     false)
            end
            if ent._jkPedIdx  >= 0 then
                ent:ManipulateBoneAngles(ent._jkPedIdx,     JK_REST,     false)
                ent:ManipulateBonePosition(ent._jkPedIdx,   JK_REST_POS, false)
            end
        end
        return
    end

    if not ClaimHips(ent, "JUMPKICK") then return end
    ent._jkWasActive = true

    local t = elapsed / ent._jkDuration

    local lhip, rhip, pedAng, pedPos

    if t < JK_P1_END then
        local env = Smoothstep(t / JK_P1_END)
        lhip   = LerpAngle(JK_REST,         ent._jkJitP1L,   env)
        rhip   = LerpAngle(JK_REST,         ent._jkJitP1R,   env)
        pedAng = JK_REST
        pedPos = JK_REST_POS
    elseif t < JK_P2_END then
        local env = Smoothstep((t - JK_P1_END) / (JK_P2_END - JK_P1_END))
        lhip   = LerpAngle(ent._jkJitP1L, ent._jkJitP2L,    env)
        rhip   = ent._jkJitP2R

        pedAng = JK_REST
        pedPos = Vector(
            Lerp(env, 0, JK_P2_PED_POS.x),
            0,
            Lerp(env, 0, JK_P2_PED_POS.z)
        )
    elseif t < JK_P3_END then
        local env = Smoothstep((t - JK_P2_END) / (JK_P3_END - JK_P2_END))
        lhip   = LerpAngle(ent._jkJitP2L, ent._jkJitP3L,    env)
        rhip   = LerpAngle(ent._jkJitP2R, JK_REST,          env)
        pedAng = LerpAngle(JK_REST,        ent._jkJitP3PA,   env)
        pedPos = Vector(
            Lerp(env, JK_P2_PED_POS.x, 0),
            0,
            Lerp(env, JK_P2_PED_POS.z, 0)
        )
    else
        local env = Smoothstep((t - JK_P3_END) / (1.0 - JK_P3_END))
        lhip   = LerpAngle(ent._jkJitP3L,  JK_REST,  env)
        rhip   = JK_REST
        pedAng = LerpAngle(ent._jkJitP3PA, JK_REST,  env)
        pedPos = JK_REST_POS
    end

    if ent._jkLHipIdx >= 0 then
        ent:ManipulateBoneAngles(ent._jkLHipIdx,   lhip,   false)
    end
    if ent._jkRHipIdx >= 0 then
        ent:ManipulateBoneAngles(ent._jkRHipIdx,   rhip,   false)
    end
    if ent._jkPedIdx  >= 0 then
        ent:ManipulateBoneAngles(ent._jkPedIdx,    pedAng, false)
        ent:ManipulateBonePosition(ent._jkPedIdx,  pedPos, false)
    end
end

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