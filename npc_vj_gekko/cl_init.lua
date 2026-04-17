include("shared.lua")
include("muzzleflash_system.lua")

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
local BLOOD_SIZE   = 0.35
local BLOOD_DECAL  = "Blood"
local BLOOD_DECAL2 = "YellowBlood"

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
        e.SetMagnitude = e.SetMagnitude or e.SetMagnitude
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

local function GekkoDoBloodSplat(ent)
    local packed = ent:GetNWInt("GekkoBloodSplat", 0)
    if packed == 0 then return end

    local pulse = math.floor(packed / 8)
    if pulse == (ent._lastBloodPulse or 0) then return end
    ent._lastBloodPulse = pulse

    local variant = (packed % 8) + 1
    local origin  = ent:GetPos() + Vector(0, 0, 80)
    local fwd     = ent:GetForward()

    if     variant == 1 then BloodVariant_Geyser(origin)
    elseif variant == 2 then BloodVariant_RadialRing(origin)
    elseif variant == 3 then BloodVariant_BurstCloud(origin)
    elseif variant == 4 then BloodVariant_ArcShower(origin, fwd)
    elseif variant == 5 then BloodVariant_GroundPool(ent:GetPos())
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
        local env = Smoothstep(t / preEnd)
        ApplyPedAndPiston(env)
        if pelIdx >= 0 then
            ent:ManipulateBonePosition(pelIdx, Vector(0,0,0), false)
            ent:ManipulateBoneAngles(pelIdx, Angle(0, ent._fk360BYaw, 0), false)
        end
        return
    end

    if t < elEnd then
        ApplyPedAndPiston(1.0)
        local env = Smoothstep((t - preEnd) / (elEnd - preEnd))
        if pelIdx >= 0 then
            ent:ManipulateBonePosition(pelIdx, Vector(0,0, FK360B_PEL_Z_ELONGATE * env), false)
            ent:ManipulateBoneAngles(pelIdx, Angle(0, ent._fk360BYaw, 0), false)
        end
        return
    end

    ApplyPedAndPiston(1.0)

    if t < spinEnd and pelIdx >= 0 then
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
        local env = Smoothstep((t - spinEnd) / (landEnd - spinEnd))
        local z   = Lerp(env, FK360B_PEL_Z_ELONGATE, FK360B_PEL_Z_LAND)
        if pelIdx >= 0 then
            ent:ManipulateBonePosition(pelIdx, Vector(0,0, z), false)
            ent:ManipulateBoneAngles(pelIdx, Angle(0, ent._fk360BYaw, 0), false)
        end
        return
    end

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

    local env
    if t < SK_RAMP then
        env = Smoothstep(t / SK_RAMP)
    elseif t > (1.0 - SK_RAMP) then
        env = Smoothstep((1.0 - t) / SK_RAMP)
    else
        env = 1.0
    end

    ent._skYaw = ent._skYaw + peakSpeed * env * dt

    local phase = t / (SK_P4_END / ent._skDuration)

    if ent._skPedIdx >= 0 then
        ent:ManipulateBoneAngles(ent._skPedIdx, Angle(0, ent._skYaw, 0), false)
    end
    if ent._skPelIdx >= 0 then
        ent:ManipulateBonePosition(ent._skPelIdx, Vector(0, 0, ent._skJitPelDrop * env), false)
    end
    if ent._skHipIdx >= 0 then
        ent:ManipulateBoneAngles(ent._skHipIdx, Angle(0, 0, ent._skJitHipZ * env), false)
    end
    if ent._skUlegIdx >= 0 then
        ent:ManipulateBoneAngles(ent._skUlegIdx, Angle(ent._skJitUlegX * env, 0, 0), false)
    end
end

-- ============================================================
--  ENT:Initialize  (client)
-- ============================================================
function ENT:Initialize()
    self._spineBone = self:LookupBone("b_spine4") or -1
end

-- ============================================================
--  ENT:Think  (client)
-- ============================================================
function ENT:Think()
    local dt = FrameTime()

    GekkoUpdateHead(self, dt)
    GekkoSyncFootsteps(self)
    GekkoFootShake(self)
    GekkoDoJumpDust(self)
    GekkoDoLandDust(self)
    GekkoDoFK360LandDust(self)
    GekkoDoMGFX(self)
    GekkoDoBloodSplat(self)
    GekkoMF_Think(self) 
    GekkoDoKickBone(self)
    GekkoDoKickLBone(self)
    GekkoDoHeadbuttBone(self)
    GekkoDoFK360Bone(self)
    GekkoDoFK360BBone(self)
    GekkoDoSpinKickBone(self)

    -- Grounded pose
    if self:GetNWBool("GekkoLegsDisabled", false) then
        GekkoApplyGroundedPose(self)
    end
end