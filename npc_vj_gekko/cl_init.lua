include("shared.lua")

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
local JUMP_NONE    = 0
local JUMP_RISING  = 1
local JUMP_FALLING = 2
local JUMP_LAND    = 3

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
--  KICK ANIMATION  (b_r_upperleg)
-- ============================================================
local KICK_WINDOW     = 1.0
local KICK_BONE_NAME  = "b_r_upperleg"
local KICK_BONE_ANGLE = Angle(112, 0, 0)
local KICK_BONE_RESET = Angle(0,   0, 0)

-- ============================================================
--  HEADBUTT ANIMATION
-- ============================================================
local HB_DURATION       = 0.8
local HB_PEAK           = 0.4
local HB_SPINE3_ANG_X   = -60
local HB_PEDESTAL_POS_X =  70
local HB_PEDESTAL_POS_Z = -45
local HB_SPINE3_BONE    = "b_spine3"
local HB_PEDESTAL_BONE  = "b_pedestal"

-- ============================================================
--  FK360 ANIMATION
-- ============================================================
local FK360_RAMP     = 0.15
local FK360_BONE     = "b_pelvis"

-- ============================================================
--  SPINKICK ANIMATION
-- ============================================================
local SK_DURATION = 0.9
local SK_P1_END   = 0.330
local SK_P2_END   = 0.500
local SK_P3_END   = 0.670
local SK_P4_END   = 0.800
local SK_RAMP       = 0.10
local SK_YAW_TOTAL  = 590
local SK_PED_BONE   = "b_Pedestal"
local SK_PEL_BONE   = "b_pelvis"
local SK_HIP_BONE   = "b_r_hippiston1"
local SK_ULEG_BONE  = "b_r_upperleg"
local SK_PEL_DROP   = -50
local SK_HIP_Z      = -22
local SK_ULEG_X     = 140

-- ============================================================
--  FOOTBALL KICK ANIMATION
-- ============================================================
local FK_DURATION      = 1.1
local FK_PHASE_HOLD    = 0.300 / FK_DURATION
local FK_PHASE_EXTEND  = 0.550 / FK_DURATION
local FK_PHASE_RECOVER = 0.700 / FK_DURATION
local FK_LHIP_Y_PREP   =  105
local FK_LHIP_X_PREP   =   36
local FK_RHIP_X_PREP   =   36
local FK_LHIP_Y_EXT    = -105
local FK_LHIP_BONE     = "b_l_hippiston1"
local FK_RHIP_BONE     = "b_r_hippiston1"

-- ============================================================
--  DIAGONAL KICK ANIMATION
-- ============================================================
local DGK_DURATION = 1.0
local DGK_P1_END   = 0.300 / DGK_DURATION
local DGK_P2_END   = 0.600 / DGK_DURATION
local DGK_P3_END   = 0.750 / DGK_DURATION
local DGK_P4_END   = 0.950 / DGK_DURATION
local DGK_P1_LHIP  = Angle( -8, -22,  43)
local DGK_P1_RHIP  = Angle(-32,   0,   0)
local DGK_P3_LHIP  = Angle( -8, -22, 105)
local DGK_P3_RHIP  = Angle(109,   0,   0)
local DGK_P4_LHIP  = Angle(136,   0,  12)
local DGK_P4_RHIP  = Angle(  0,   0,   0)
local DGK_LHIP_BONE = "b_l_hippiston1"
local DGK_RHIP_BONE = "b_r_hippiston1"

-- ============================================================
--  HEEL HOOK ANIMATION
-- ============================================================
local HH_DURATION_CL        = 0.8
local HH_HIP_CHAMBER_PITCH  =  85
local HH_HIP_EXTEND_ROLL    =  30
local HH_HIP_HOOK_YAW       = -35
local HH_PELVIS_YAW         =  28
local HH_PELVIS_PITCH       =   8
local HH_SPINE_LEAN         =  12
local HH_HIP_BONE    = "b_l_hippiston1"
local HH_PELVIS_BONE = "b_pelvis"
local HH_SPINE_BONE  = "b_spine3"

-- ============================================================
--  SIDE HOOK KICK ANIMATION
-- ============================================================
local SHK_DURATION = 1.1
local SHK_P1_END = 0.200 / SHK_DURATION
local SHK_P2_END = 0.400 / SHK_DURATION
local SHK_P3_END = 0.550 / SHK_DURATION
local SHK_P4_END = 0.700 / SHK_DURATION
local SHK_P1_LHIP = Angle(-74,  0,   0)
local SHK_P1_RHIP = Angle(-102, 0,   0)
local SHK_P2_LHIP = Angle(-25,  0,   0)
local SHK_P2_RHIP = Angle( -8,  0, -64)
local SHK_P3_LHIP = Angle(-25,  0,   0)
local SHK_P3_RHIP = Angle(  0,  0, -120)
local SHK_P4_LHIP = Angle(-57,  0, -29)
local SHK_P4_RHIP = Angle(-12,  0, -25)
local SHK_REST    = Angle(0, 0, 0)
local SHK_LHIP_BONE = "b_l_hippiston1"
local SHK_RHIP_BONE = "b_r_hippiston1"

-- ============================================================
--  AXE KICK ANIMATION
-- ============================================================
local AK_DURATION = 1.1
local AK_P1_END   = 0.350 / AK_DURATION
local AK_P2_END   = 0.550 / AK_DURATION
local AK_P3_END   = 0.700 / AK_DURATION

local AK_P1_LHIP   = Angle(  0, -133,   0)
local AK_P1_SPINE  = Angle(  5,  -12, -39)

local AK_P3_LHIP   = Angle(  0,   -5,   0)
local AK_P3_RHIP   = Angle(  0,  -31,   0)
local AK_P3_SPINE  = Angle(-17,    0,   0)

local AK_REST      = Angle(0, 0, 0)

local AK_LHIP_BONE  = "b_l_hippiston1"
local AK_RHIP_BONE  = "b_r_hippiston1"
local AK_SPINE_BONE = "b_spine3"

-- ============================================================
--  JUMP KICK ANIMATION
--
--  4 phases over JK_DURATION = 1.6 s  (t = 0..1):
--
--  Phase 1  [0.000 - 0.300]  Preparation - leg chambers, weight shifts
--    b_l_hippiston1  -> Angle(58,  0,  -8)   (left leg loads back)
--    b_r_hippiston1  -> Angle(88,  0, -36)   (right leg braces)
--
--  Phase 2  [0.300 - 0.550]  Kick + forward hop  (server fires damage at 0.55 s)
--    b_l_hippiston1  -> Angle(56,  0,  79)   (left leg extends forward/up)
--    b_r_hippiston1  -> Angle(88,  0, -36)   (right stays braced)
--    b_pedestal pos  -> Vector(30, 0, 13)    (body hops forward)
--
--  Phase 3  [0.550 - 1.000]  Falling - body tilts as Gekko descends
--    b_l_hippiston1  -> Angle(0,  43,  0)    (leg hangs loose)
--    b_pedestal ang  -> Angle(0,  20,  0)    (body yaws slightly)
--    b_pedestal pos  -> Vector(0,  0,  0)    (re-centres)
--
--  Phase 4  [1.000 - 1.600]  Smooth recovery to rest
--    All bones lerp back to Angle/Vector(0,0,0).
--
--  Mutex key : "JUMPKICK"
--  NW signal : GekkoJumpKickPulse
-- ============================================================
local JK_DURATION = 1.6
local JK_P1_END   = 0.300 / JK_DURATION   -- ~0.1875
local JK_P2_END   = 0.550 / JK_DURATION   -- ~0.3438
local JK_P3_END   = 1.000 / JK_DURATION   -- ~0.6250
-- Phase 4 ends at 1.0

-- Phase 1 peaks
local JK_P1_LHIP  = Angle(58,  0,  -8)
local JK_P1_RHIP  = Angle(88,  0, -36)

-- Phase 2 peaks  (kick extension)
local JK_P2_LHIP  = Angle(56,  0,  79)
local JK_P2_RHIP  = Angle(88,  0, -36)   -- unchanged from P1
local JK_P2_PED_POS = Vector(30, 0, 13)

-- Phase 3 peaks  (falling)
local JK_P3_LHIP    = Angle(0,  43,  0)
local JK_P3_PED_ANG = Angle(0,  20,  0)
local JK_P3_PED_POS = Vector(0,  0,  0)

local JK_REST       = Angle(0, 0, 0)
local JK_REST_POS   = Vector(0, 0, 0)

local JK_LHIP_BONE  = "b_l_hippiston1"
local JK_RHIP_BONE  = "b_r_hippiston1"
local JK_PED_BONE   = "b_pedestal"

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
local CRUSH_IMPACT_SOUNDS = {
    "physics/body/body_medium_impact_hard1.wav",
    "physics/body/body_medium_impact_hard2.wav",
    "physics/body/body_medium_impact_hard3.wav",
    "physics/body/body_medium_impact_hard4.wav",
    "physics/body/body_medium_impact_hard5.wav",
    "physics/body/body_medium_impact_hard6.wav",
}

local CRUSH_SHAKE_RADIUS = 900

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
local SONAR_SOUND          = "mac_bo2_m32/Sonar intercept.wav"
local SONAR_DURATION       = 3.0
local SONAR_PULSE_COUNT    = 3
local SONAR_PULSE_INTERVAL = 0.6
local SONAR_RING_THICKNESS = 3
local SONAR_PEAK_ALPHA     = 100
local SONAR_TINT_ALPHA     = 40
local SONAR_R = 200
local SONAR_G = 0
local SONAR_B = 0
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
        DrawRingOutline(cx, cy, radius, SONAR_RING_THICKNESS, SONAR_R, SONAR_G, SONAR_B, finalAlpha)
    end
end)

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
--  HEAD DRIVER
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
        targetYaw   = math.Clamp(math.NormalizeAngle(toEnemy.y - ent:GetAngles().y), -HEAD_LIMIT,   HEAD_LIMIT)
        targetPitch = math.Clamp(toEnemy.p,                                           HEAD_PITCH_UP, HEAD_PITCH_DOWN)
    end
    local maxStep   = HEAD_SPEED * dt
    local yawDiff   = math.NormalizeAngle(targetYaw - ent._headYaw)
    ent._headYaw    = math.Clamp(ent._headYaw   + math.Clamp(yawDiff,   -maxStep, maxStep), -HEAD_LIMIT,   HEAD_LIMIT)
    local pitchDiff = targetPitch - ent._headPitch
    ent._headPitch  = math.Clamp(ent._headPitch + math.Clamp(pitchDiff, -maxStep, maxStep),  HEAD_PITCH_UP, HEAD_PITCH_DOWN)
    ent:ManipulateBoneAngles(bone, Angle(-ent._headYaw, 0, ent._headPitch), false)
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
        SpawnBloodBlob(origin + Vector(0, 0, math.Rand(20, 120) * s), dir, math.Rand(800, 2200), math.Rand(8, 22))
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
        SpawnBloodBlob(origin + Vector(0, 0, ringH), dir, math.Rand(700, 2400), math.Rand(10, 28))
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
            math.Rand(600, 2800), math.Rand(10, 30)
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
            math.Rand(1000, 3000), math.Rand(8, 24)
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
        SpawnBloodBlob(origin + Vector(0, 0, math.Rand(5, 40) * s), dir, math.Rand(600, 2000), math.Rand(14, 36))
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
--  KICK BONE DRIVER
-- ============================================================
local function GekkoDoKickBone(ent)
    if ent._kickBoneIdx == nil then
        ent._kickBoneIdx   = ent:LookupBone(KICK_BONE_NAME) or -1
        ent._kickEndTime   = 0
        ent._kickPulseLast = ent:GetNWInt("GekkoKickPulse", 0)
        ent._kickWasActive = false
    end
    local pulse = ent:GetNWInt("GekkoKickPulse", 0)
    if pulse ~= ent._kickPulseLast then
        ent._kickPulseLast = pulse
        ent._kickEndTime   = math.max(ent._kickEndTime, CurTime() + KICK_WINDOW)
    end
    local boneIdx = ent._kickBoneIdx
    if not boneIdx or boneIdx < 0 then return end
    local active = CurTime() < ent._kickEndTime
    if active then
        ent._kickWasActive = true
        ent:ManipulateBoneAngles(boneIdx, KICK_BONE_ANGLE, false)
    elseif ent._kickWasActive then
        ent._kickWasActive = false
        ent:ManipulateBoneAngles(boneIdx, KICK_BONE_RESET, false)
    end
end

-- ============================================================
--  HEADBUTT BONE DRIVER
-- ============================================================
local function GekkoDoHeadbuttBone(ent)
    if ent._hbInited == nil then
        ent._hbInited      = true
        ent._hbSpineIdx    = ent:LookupBone(HB_SPINE3_BONE)   or -1
        ent._hbPedestalIdx = ent:LookupBone(HB_PEDESTAL_BONE) or -1
        ent._hbStartTime   = -9999
        ent._hbPulseLast   = ent:GetNWInt("GekkoHeadbuttPulse", 0)
        ent._hbWasActive   = false
    end
    local pulse = ent:GetNWInt("GekkoHeadbuttPulse", 0)
    if pulse ~= ent._hbPulseLast then
        ent._hbPulseLast = pulse
        ent._hbStartTime = CurTime()
        print(string.format("[GekkoHeadbutt] pulse=%d", pulse))
    end
    local elapsed = CurTime() - ent._hbStartTime
    local active  = elapsed >= 0 and elapsed < HB_DURATION
    if not active then
        if ent._hbWasActive then
            ent._hbWasActive = false
            if ent._hbSpineIdx    >= 0 then ent:ManipulateBoneAngles(ent._hbSpineIdx,    Angle(0, 0, 0),    false) end
            if ent._hbPedestalIdx >= 0 then ent:ManipulateBonePosition(ent._hbPedestalIdx, Vector(0, 0, 0), false) end
        end
        return
    end
    ent._hbWasActive = true
    local t = elapsed / HB_DURATION
    local env
    if t < HB_PEAK then
        env = Smoothstep(t / HB_PEAK)
    else
        env = Smoothstep(1 - (t - HB_PEAK) / (1 - HB_PEAK))
    end
    if ent._hbSpineIdx >= 0 then
        ent:ManipulateBoneAngles(ent._hbSpineIdx, Angle(HB_SPINE3_ANG_X * env, 0, 0), false)
    end
    if ent._hbPedestalIdx >= 0 then
        ent:ManipulateBonePosition(ent._hbPedestalIdx, Vector(HB_PEDESTAL_POS_X * env, 0, HB_PEDESTAL_POS_Z * env), false)
    end
end

-- ============================================================
--  FK360 BONE DRIVER
-- ============================================================
local function GekkoDoFK360Bone(ent)
    local fk360Duration = ent.FK360_DURATION or 0.9
    if ent._fk360Inited == nil then
        ent._fk360Inited    = true
        ent._fk360BoneIdx   = ent:LookupBone(FK360_BONE) or -1
        ent._fk360StartTime = -9999
        ent._fk360PulseLast = ent:GetNWInt("GekkoFrontKick360Pulse", 0)
        ent._fk360Yaw       = 0
        ent._fk360WasActive = false
    end
    local pulse = ent:GetNWInt("GekkoFrontKick360Pulse", 0)
    if pulse ~= ent._fk360PulseLast then
        ent._fk360PulseLast = pulse
        ent._fk360StartTime = CurTime()
        ent._fk360Yaw       = 0
        print(string.format("[GekkoFK360] pulse=%d  duration=%.2f", pulse, fk360Duration))
    end
    local boneIdx = ent._fk360BoneIdx
    if not boneIdx or boneIdx < 0 then return end
    local elapsed = CurTime() - ent._fk360StartTime
    local active  = elapsed >= 0 and elapsed < fk360Duration
    if not active then
        if ent._fk360WasActive then
            ent._fk360WasActive = false
            ent._fk360Yaw = 0
            ent:ManipulateBoneAngles(boneIdx, Angle(0, 0, 0), false)
        end
        return
    end
    ent._fk360WasActive = true
    local peakSpeed = 360.0 / ((1.0 - FK360_RAMP) * fk360Duration)
    local t = elapsed / fk360Duration
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
--  SPINKICK BONE DRIVER  (mutex: SPINKICK)
-- ============================================================
local function GekkoDoSpinKickBone(ent)
    if ent._skInited == nil then
        ent._skInited    = true
        ent._skPedIdx    = ent:LookupBone(SK_PED_BONE)  or -1
        ent._skPelIdx    = ent:LookupBone(SK_PEL_BONE)  or -1
        ent._skHipIdx    = ent:LookupBone(SK_HIP_BONE)  or -1
        ent._skUlegIdx   = ent:LookupBone(SK_ULEG_BONE) or -1
        ent._skStartTime = -9999
        ent._skPulseLast = ent:GetNWInt("GekkoSpinKickPulse", 0)
        ent._skYaw       = 0
        ent._skWasActive = false
    end
    local pulse = ent:GetNWInt("GekkoSpinKickPulse", 0)
    if pulse ~= ent._skPulseLast then
        ent._skPulseLast = pulse
        ent._skStartTime = CurTime()
        ent._skYaw       = 0
        print(string.format("[GekkoSpinKick] pulse=%d", pulse))
    end
    local elapsed = CurTime() - ent._skStartTime
    local active  = elapsed >= 0 and elapsed < SK_DURATION
    if not active then
        if ent._skWasActive then
            ent._skWasActive = false
            ent._skYaw = 0
            ReleaseHips(ent, "SPINKICK")
            if ent._skPedIdx  >= 0 then ent:ManipulateBoneAngles(ent._skPedIdx,    Angle(0, 0, 0),    false) end
            if ent._skPelIdx  >= 0 then ent:ManipulateBonePosition(ent._skPelIdx,  Vector(0, 0, 0),   false) end
            if ent._skHipIdx  >= 0 then ent:ManipulateBoneAngles(ent._skHipIdx,    Angle(0, 0, 0),    false) end
            if ent._skUlegIdx >= 0 then ent:ManipulateBoneAngles(ent._skUlegIdx,   Angle(0, 0, 0),    false) end
        end
        return
    end
    if not ClaimHips(ent, "SPINKICK") then return end
    ent._skWasActive = true
    local t  = elapsed / SK_DURATION
    local dt = math.Clamp(CurTime() - (ent._skLastT or CurTime()), 0, 0.05)
    ent._skLastT = CurTime()
    local peakSpeed = SK_YAW_TOTAL / ((1.0 - SK_RAMP) * SK_DURATION)
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
    if ent._skPedIdx >= 0 then ent:ManipulateBoneAngles(ent._skPedIdx, Angle(0, ent._skYaw, 0), false) end
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
        crouchEnv = math.max((1.0 - Smoothstep(Smoothstep(Smoothstep(localT)))) * 0.08, 0)
    end
    local legEnv
    if t < SK_P1_END then
        legEnv = 0
    elseif t < SK_P3_END then
        legEnv = 1.0
    else
        legEnv = crouchEnv
    end
    if ent._skPelIdx  >= 0 then ent:ManipulateBonePosition(ent._skPelIdx,  Vector(0, 0, SK_PEL_DROP * crouchEnv), false) end
    if ent._skHipIdx  >= 0 then ent:ManipulateBoneAngles(ent._skHipIdx,    Angle(0, 0, SK_HIP_Z    * crouchEnv), false) end
    if ent._skUlegIdx >= 0 then ent:ManipulateBoneAngles(ent._skUlegIdx,   Angle(SK_ULEG_X * legEnv, 0, 0),       false) end
end

-- ============================================================
--  FOOTBALL KICK BONE DRIVER  (mutex: FOOTBALLKICK)
-- ============================================================
local function GekkoDoFootballKickBone(ent)
    if ent._fkInited == nil then
        ent._fkInited    = true
        ent._fkLHipIdx   = ent:LookupBone(FK_LHIP_BONE) or -1
        ent._fkRHipIdx   = ent:LookupBone(FK_RHIP_BONE) or -1
        ent._fkStartTime = -9999
        ent._fkPulseLast = ent:GetNWInt("GekkoFootballKickPulse", 0)
        ent._fkWasActive = false
    end
    local pulse = ent:GetNWInt("GekkoFootballKickPulse", 0)
    if pulse ~= ent._fkPulseLast then
        ent._fkPulseLast = pulse
        ent._fkStartTime = CurTime()
        print(string.format("[GekkoFootballKick] pulse=%d", pulse))
    end
    local elapsed = CurTime() - ent._fkStartTime
    local active  = elapsed >= 0 and elapsed < FK_DURATION
    if not active then
        if ent._fkWasActive then
            ent._fkWasActive = false
            ReleaseHips(ent, "FOOTBALLKICK")
            if ent._fkLHipIdx >= 0 then ent:ManipulateBoneAngles(ent._fkLHipIdx, Angle(0, 0, 0), false) end
            if ent._fkRHipIdx >= 0 then ent:ManipulateBoneAngles(ent._fkRHipIdx, Angle(0, 0, 0), false) end
        end
        return
    end
    if not ClaimHips(ent, "FOOTBALLKICK") then return end
    ent._fkWasActive = true
    local t = elapsed / FK_DURATION
    local lhipY, lhipX, rhipX
    if t < FK_PHASE_HOLD then
        local env = Smoothstep(t / FK_PHASE_HOLD)
        lhipY =  FK_LHIP_Y_PREP * env
        lhipX =  FK_LHIP_X_PREP * env
        rhipX =  FK_RHIP_X_PREP * env
    elseif t < FK_PHASE_EXTEND then
        lhipY =  FK_LHIP_Y_PREP
        lhipX =  FK_LHIP_X_PREP
        rhipX =  FK_RHIP_X_PREP
    elseif t < FK_PHASE_RECOVER then
        local env = Smoothstep((t - FK_PHASE_EXTEND) / (FK_PHASE_RECOVER - FK_PHASE_EXTEND))
        lhipY = FK_LHIP_Y_PREP + (FK_LHIP_Y_EXT - FK_LHIP_Y_PREP) * env
        lhipX = FK_LHIP_X_PREP * (1 - env)
        rhipX = FK_RHIP_X_PREP * (1 - env)
    else
        local env = Smoothstep((t - FK_PHASE_RECOVER) / (1.0 - FK_PHASE_RECOVER))
        lhipY = FK_LHIP_Y_EXT * (1 - env)
        lhipX = 0
        rhipX = 0
    end
    if ent._fkLHipIdx >= 0 then ent:ManipulateBoneAngles(ent._fkLHipIdx, Angle(lhipX, lhipY, 0), false) end
    if ent._fkRHipIdx >= 0 then ent:ManipulateBoneAngles(ent._fkRHipIdx, Angle(rhipX, 0, 0),     false) end
end

-- ============================================================
--  DIAGONAL KICK BONE DRIVER  (mutex: DIAGONALKICK)
-- ============================================================
local function GekkoDoDiagonalKickBone(ent)
    if ent._dgkInited == nil then
        ent._dgkInited    = true
        ent._dgkLHipIdx   = ent:LookupBone(DGK_LHIP_BONE) or -1
        ent._dgkRHipIdx   = ent:LookupBone(DGK_RHIP_BONE) or -1
        ent._dgkStartTime = -9999
        ent._dgkPulseLast = ent:GetNWInt("GekkoDiagonalKickPulse", 0)
        ent._dgkWasActive = false
    end
    local pulse = ent:GetNWInt("GekkoDiagonalKickPulse", 0)
    if pulse ~= ent._dgkPulseLast then
        ent._dgkPulseLast = pulse
        ent._dgkStartTime = CurTime()
        print(string.format("[GekkoDiagonalKick] pulse=%d", pulse))
    end
    local elapsed = CurTime() - ent._dgkStartTime
    local active  = elapsed >= 0 and elapsed < DGK_DURATION
    if not active then
        if ent._dgkWasActive then
            ent._dgkWasActive = false
            ReleaseHips(ent, "DIAGONALKICK")
            if ent._dgkLHipIdx >= 0 then ent:ManipulateBoneAngles(ent._dgkLHipIdx, Angle(0, 0, 0), false) end
            if ent._dgkRHipIdx >= 0 then ent:ManipulateBoneAngles(ent._dgkRHipIdx, Angle(0, 0, 0), false) end
        end
        return
    end
    if not ClaimHips(ent, "DIAGONALKICK") then return end
    ent._dgkWasActive = true
    local t     = elapsed / DGK_DURATION
    local lhip, rhip
    local REST  = Angle(0, 0, 0)
    if t < DGK_P1_END then
        local env = Smoothstep(t / DGK_P1_END)
        lhip = LerpAngle(REST,       DGK_P1_LHIP, env)
        rhip = LerpAngle(REST,       DGK_P1_RHIP, env)
    elseif t < DGK_P2_END then
        lhip = DGK_P1_LHIP
        rhip = DGK_P1_RHIP
    elseif t < DGK_P3_END then
        local env = Smoothstep((t - DGK_P2_END) / (DGK_P3_END - DGK_P2_END))
        lhip = LerpAngle(DGK_P1_LHIP, DGK_P3_LHIP, env)
        rhip = LerpAngle(DGK_P1_RHIP, DGK_P3_RHIP, env)
    elseif t < DGK_P4_END then
        local env = Smoothstep((t - DGK_P3_END) / (DGK_P4_END - DGK_P3_END))
        lhip = LerpAngle(DGK_P3_LHIP, DGK_P4_LHIP, env)
        rhip = LerpAngle(DGK_P3_RHIP, DGK_P4_RHIP, env)
    else
        local env = Smoothstep((t - DGK_P4_END) / (1.0 - DGK_P4_END))
        lhip = LerpAngle(DGK_P4_LHIP, REST, env)
        rhip = LerpAngle(DGK_P4_RHIP, REST, env)
    end
    if ent._dgkLHipIdx >= 0 then ent:ManipulateBoneAngles(ent._dgkLHipIdx, lhip, false) end
    if ent._dgkRHipIdx >= 0 then ent:ManipulateBoneAngles(ent._dgkRHipIdx, rhip, false) end
end

-- ============================================================
--  HEEL HOOK BONE DRIVER  (mutex: HEELHOOK)
-- ============================================================
local function GekkoDoHeelHookBone(ent)
    if ent._hhInited == nil then
        ent._hhInited    = true
        ent._hhHipIdx    = ent:LookupBone(HH_HIP_BONE)    or -1
        ent._hhPelIdx    = ent:LookupBone(HH_PELVIS_BONE) or -1
        ent._hhSpineIdx  = ent:LookupBone(HH_SPINE_BONE)  or -1
        ent._hhStartTime = -9999
        ent._hhPulseLast = ent:GetNWInt("GekkoHeelHookPulse", 0)
        ent._hhWasActive = false
    end
    local pulse = ent:GetNWInt("GekkoHeelHookPulse", 0)
    if pulse ~= ent._hhPulseLast then
        ent._hhPulseLast = pulse
        ent._hhStartTime = CurTime()
        print(string.format("[GekkoHeelHook] pulse=%d", pulse))
    end
    local elapsed = CurTime() - ent._hhStartTime
    local active  = elapsed >= 0 and elapsed < HH_DURATION_CL
    if not active then
        if ent._hhWasActive then
            ent._hhWasActive = false
            ReleaseHips(ent, "HEELHOOK")
            if ent._hhHipIdx   >= 0 then ent:ManipulateBoneAngles(ent._hhHipIdx,   Angle(0, 0, 0), false) end
            if ent._hhPelIdx   >= 0 then ent:ManipulateBoneAngles(ent._hhPelIdx,   Angle(0, 0, 0), false) end
            if ent._hhSpineIdx >= 0 then ent:ManipulateBoneAngles(ent._hhSpineIdx, Angle(0, 0, 0), false) end
        end
        return
    end
    if not ClaimHips(ent, "HEELHOOK") then return end
    ent._hhWasActive = true
    local t    = elapsed / HH_DURATION_CL
    local P1 = 0.200; local P2 = 0.440; local P3 = 0.650; local P4 = 0.800
    local function PhaseEnv(t0, t1) return Smoothstep(math.Clamp((t - t0) / (t1 - t0), 0, 1)) end
    local hipPitch, hipRoll, hipYaw
    if t < P1 then
        hipPitch = HH_HIP_CHAMBER_PITCH * PhaseEnv(0, P1); hipRoll = 0; hipYaw = 0
    elseif t < P2 then
        hipPitch = HH_HIP_CHAMBER_PITCH; hipRoll = 0; hipYaw = 0
    elseif t < P3 then
        hipPitch = HH_HIP_CHAMBER_PITCH; hipRoll = HH_HIP_EXTEND_ROLL * PhaseEnv(P2, P3); hipYaw = 0
    elseif t < P4 then
        local env = PhaseEnv(P3, P4)
        hipPitch = HH_HIP_CHAMBER_PITCH * (1 - env * 0.3); hipRoll = HH_HIP_EXTEND_ROLL * (1 - env); hipYaw = HH_HIP_HOOK_YAW * env
    else
        local env = PhaseEnv(P4, 1.0)
        hipPitch = HH_HIP_CHAMBER_PITCH * (0.7 - env * 0.7); hipRoll = 0; hipYaw = HH_HIP_HOOK_YAW * (1 - env)
    end
    if ent._hhHipIdx >= 0 then ent:ManipulateBoneAngles(ent._hhHipIdx, Angle(hipPitch, hipYaw, hipRoll), false) end
    local pelYaw, pelPitch
    if t < P1 then
        pelYaw = HH_PELVIS_YAW * PhaseEnv(0, P1) * 0.5; pelPitch = 0
    elseif t < P2 then
        pelYaw = HH_PELVIS_YAW * (0.5 + 0.5 * PhaseEnv(P1, P2)); pelPitch = 0
    elseif t < P3 then
        pelYaw = HH_PELVIS_YAW; pelPitch = HH_PELVIS_PITCH * PhaseEnv(P2, P3)
    elseif t < P4 then
        local env = PhaseEnv(P3, P4)
        pelYaw = HH_PELVIS_YAW * (1 - env * 0.6); pelPitch = HH_PELVIS_PITCH * (1 - env)
    else
        pelYaw = HH_PELVIS_YAW * 0.4 * (1 - PhaseEnv(P4, 1.0)); pelPitch = 0
    end
    if ent._hhPelIdx >= 0 then ent:ManipulateBoneAngles(ent._hhPelIdx, Angle(pelPitch, pelYaw, 0), false) end
    local spineLean
    if t < P1 then spineLean = 0
    elseif t < P3 then spineLean = HH_SPINE_LEAN * PhaseEnv(P1, P3)
    elseif t < P4 then spineLean = HH_SPINE_LEAN
    else spineLean = HH_SPINE_LEAN * (1 - PhaseEnv(P4, 1.0))
    end
    if ent._hhSpineIdx >= 0 then ent:ManipulateBoneAngles(ent._hhSpineIdx, Angle(0, 0, spineLean), false) end
end

-- ============================================================
--  SIDE HOOK KICK BONE DRIVER  (mutex: SIDEHOOKKICK)
-- ============================================================
local function GekkoDoSideHookKickBone(ent)
    if ent._shkInited == nil then
        ent._shkInited    = true
        ent._shkLHipIdx   = ent:LookupBone(SHK_LHIP_BONE) or -1
        ent._shkRHipIdx   = ent:LookupBone(SHK_RHIP_BONE) or -1
        ent._shkStartTime = -9999
        ent._shkPulseLast = ent:GetNWInt("GekkoSideHookKickPulse", 0)
        ent._shkWasActive = false
    end
    local pulse = ent:GetNWInt("GekkoSideHookKickPulse", 0)
    if pulse ~= ent._shkPulseLast then
        ent._shkPulseLast = pulse
        ent._shkStartTime = CurTime()
        print(string.format("[GekkoSideHookKick] pulse=%d", pulse))
    end
    local elapsed = CurTime() - ent._shkStartTime
    local active  = elapsed >= 0 and elapsed < SHK_DURATION
    if not active then
        if ent._shkWasActive then
            ent._shkWasActive = false
            ReleaseHips(ent, "SIDEHOOKKICK")
            if ent._shkLHipIdx >= 0 then ent:ManipulateBoneAngles(ent._shkLHipIdx, Angle(0, 0, 0), false) end
            if ent._shkRHipIdx >= 0 then ent:ManipulateBoneAngles(ent._shkRHipIdx, Angle(0, 0, 0), false) end
        end
        return
    end
    if not ClaimHips(ent, "SIDEHOOKKICK") then return end
    ent._shkWasActive = true
    local t    = elapsed / SHK_DURATION
    local REST = SHK_REST
    local lhip, rhip
    if t < SHK_P1_END then
        local env = Smoothstep(t / SHK_P1_END)
        lhip = LerpAngle(REST, SHK_P1_LHIP, env); rhip = LerpAngle(REST, SHK_P1_RHIP, env)
    elseif t < SHK_P2_END then
        local env = Smoothstep((t - SHK_P1_END) / (SHK_P2_END - SHK_P1_END))
        lhip = LerpAngle(SHK_P1_LHIP, SHK_P2_LHIP, env); rhip = LerpAngle(SHK_P1_RHIP, SHK_P2_RHIP, env)
    elseif t < SHK_P3_END then
        local env = Smoothstep((t - SHK_P2_END) / (SHK_P3_END - SHK_P2_END))
        lhip = SHK_P2_LHIP; rhip = LerpAngle(SHK_P2_RHIP, SHK_P3_RHIP, env)
    elseif t < SHK_P4_END then
        local env = Smoothstep((t - SHK_P3_END) / (SHK_P4_END - SHK_P3_END))
        lhip = LerpAngle(SHK_P2_LHIP, SHK_P4_LHIP, env); rhip = LerpAngle(SHK_P3_RHIP, SHK_P4_RHIP, env)
    else
        local env = Smoothstep((t - SHK_P4_END) / (1.0 - SHK_P4_END))
        lhip = LerpAngle(SHK_P4_LHIP, REST, env); rhip = LerpAngle(SHK_P4_RHIP, REST, env)
    end
    if ent._shkLHipIdx >= 0 then ent:ManipulateBoneAngles(ent._shkLHipIdx, lhip, false) end
    if ent._shkRHipIdx >= 0 then ent:ManipulateBoneAngles(ent._shkRHipIdx, rhip, false) end
end

-- ============================================================
--  AXE KICK BONE DRIVER
-- ============================================================
local function GekkoDoAxeKickBone(ent)
    if ent._akInited == nil then
        ent._akInited    = true
        ent._akLHipIdx   = ent:LookupBone(AK_LHIP_BONE)  or -1
        ent._akRHipIdx   = ent:LookupBone(AK_RHIP_BONE)  or -1
        ent._akSpineIdx  = ent:LookupBone(AK_SPINE_BONE) or -1
        ent._akStartTime = -9999
        ent._akPulseLast = ent:GetNWInt("GekkoAxeKickPulse", 0)
        ent._akWasActive = false
    end

    local pulse = ent:GetNWInt("GekkoAxeKickPulse", 0)
    if pulse ~= ent._akPulseLast then
        ent._akPulseLast = pulse
        ent._akStartTime = CurTime()
        print(string.format("[GekkoAxeKick] pulse=%d", pulse))
    end

    local elapsed = CurTime() - ent._akStartTime
    local active  = elapsed >= 0 and elapsed < AK_DURATION

    if not active then
        if ent._akWasActive then
            ent._akWasActive = false
            ReleaseHips(ent, "AXEKICK")
            if ent._akLHipIdx  >= 0 then ent:ManipulateBoneAngles(ent._akLHipIdx,  Angle(0,0,0), false) end
            if ent._akRHipIdx  >= 0 then ent:ManipulateBoneAngles(ent._akRHipIdx,  Angle(0,0,0), false) end
            if ent._akSpineIdx >= 0 then ent:ManipulateBoneAngles(ent._akSpineIdx, Angle(0,0,0), false) end
        end
        return
    end

    if not ClaimHips(ent, "AXEKICK") then return end
    ent._akWasActive = true

    local t    = elapsed / AK_DURATION
    local REST = AK_REST
    local lhip, rhip, spine

    if t < AK_P1_END then
        local env = Smoothstep(t / AK_P1_END)
        lhip  = LerpAngle(REST,        AK_P1_LHIP,  env)
        rhip  = REST
        spine = LerpAngle(REST,        AK_P1_SPINE, env)
    elseif t < AK_P2_END then
        lhip  = AK_P1_LHIP
        rhip  = REST
        spine = AK_P1_SPINE
    elseif t < AK_P3_END then
        local env = Smoothstep(Smoothstep((t - AK_P2_END) / (AK_P3_END - AK_P2_END)))
        lhip  = LerpAngle(AK_P1_LHIP,  AK_P3_LHIP,  env)
        rhip  = LerpAngle(REST,         AK_P3_RHIP,  env)
        spine = LerpAngle(AK_P1_SPINE,  AK_P3_SPINE, env)
    else
        local env = Smoothstep((t - AK_P3_END) / (1.0 - AK_P3_END))
        lhip  = LerpAngle(AK_P3_LHIP,  REST, env)
        rhip  = LerpAngle(AK_P3_RHIP,  REST, env)
        spine = LerpAngle(AK_P3_SPINE, REST, env)
    end

    if ent._akLHipIdx  >= 0 then ent:ManipulateBoneAngles(ent._akLHipIdx,  lhip,  false) end
    if ent._akRHipIdx  >= 0 then ent:ManipulateBoneAngles(ent._akRHipIdx,  rhip,  false) end
    if ent._akSpineIdx >= 0 then ent:ManipulateBoneAngles(ent._akSpineIdx, spine, false) end
end

-- ============================================================
--  JUMP KICK BONE DRIVER  (mutex: JUMPKICK)
--
--  Drives: b_l_hippiston1, b_r_hippiston1, b_pedestal (ang+pos)
--
--  Phase 1  [0, JK_P1_END]   Preparation
--    L hip  ramps to JK_P1_LHIP  Angle(58,  0,  -8)
--    R hip  ramps to JK_P1_RHIP  Angle(88,  0, -36)
--
--  Phase 2  [JK_P1_END, JK_P2_END]  Kick extension + hop
--    L hip  moves to JK_P2_LHIP  Angle(56,  0,  79)
--    R hip  holds  JK_P2_RHIP   Angle(88,  0, -36)
--    Pedestal pos ramps to JK_P2_PED_POS  Vector(30, 0, 13)
--
--  Phase 3  [JK_P2_END, JK_P3_END]  Falling
--    L hip  moves to JK_P3_LHIP  Angle(0,  43,  0)
--    R hip  returns to REST
--    Pedestal ang ramps to JK_P3_PED_ANG  Angle(0, 20, 0)
--    Pedestal pos returns to Vector(0, 0, 0)
--
--  Phase 4  [JK_P3_END, 1.0]  Smooth recovery
--    All bones lerp back to rest.
-- ============================================================
local function GekkoDoJumpKickBone(ent)
    if ent._jkInited == nil then
        ent._jkInited    = true
        ent._jkLHipIdx   = ent:LookupBone(JK_LHIP_BONE) or -1
        ent._jkRHipIdx   = ent:LookupBone(JK_RHIP_BONE) or -1
        ent._jkPedIdx    = ent:LookupBone(JK_PED_BONE)  or -1
        ent._jkStartTime = -9999
        ent._jkPulseLast = ent:GetNWInt("GekkoJumpKickPulse", 0)
        ent._jkWasActive = false
    end

    local pulse = ent:GetNWInt("GekkoJumpKickPulse", 0)
    if pulse ~= ent._jkPulseLast then
        ent._jkPulseLast = pulse
        ent._jkStartTime = CurTime()
        print(string.format("[GekkoJumpKick] pulse=%d", pulse))
    end

    local elapsed = CurTime() - ent._jkStartTime
    local active  = elapsed >= 0 and elapsed < JK_DURATION

    if not active then
        if ent._jkWasActive then
            ent._jkWasActive = false
            ReleaseHips(ent, "JUMPKICK")
            if ent._jkLHipIdx >= 0 then ent:ManipulateBoneAngles(ent._jkLHipIdx,    JK_REST,     false) end
            if ent._jkRHipIdx >= 0 then ent:ManipulateBoneAngles(ent._jkRHipIdx,    JK_REST,     false) end
            if ent._jkPedIdx  >= 0 then ent:ManipulateBoneAngles(ent._jkPedIdx,     JK_REST,     false) end
            if ent._jkPedIdx  >= 0 then ent:ManipulateBonePosition(ent._jkPedIdx,   JK_REST_POS, false) end
        end
        return
    end

    if not ClaimHips(ent, "JUMPKICK") then return end
    ent._jkWasActive = true

    local t = elapsed / JK_DURATION

    local lhip, rhip, pedAng, pedPos

    if t < JK_P1_END then
        -- Phase 1: preparation
        local env = Smoothstep(t / JK_P1_END)
        lhip   = LerpAngle(JK_REST,      JK_P1_LHIP,    env)
        rhip   = LerpAngle(JK_REST,      JK_P1_RHIP,    env)
        pedAng = JK_REST
        pedPos = JK_REST_POS

    elseif t < JK_P2_END then
        -- Phase 2: kick + hop
        local env = Smoothstep((t - JK_P1_END) / (JK_P2_END - JK_P1_END))
        lhip   = LerpAngle(JK_P1_LHIP, JK_P2_LHIP,    env)
        rhip   = JK_P2_RHIP
        pedAng = JK_REST
        pedPos = Vector(
            Lerp(env, 0, JK_P2_PED_POS.x),
            0,
            Lerp(env, 0, JK_P2_PED_POS.z)
        )

    elseif t < JK_P3_END then
        -- Phase 3: falling
        local env = Smoothstep((t - JK_P2_END) / (JK_P3_END - JK_P2_END))
        lhip   = LerpAngle(JK_P2_LHIP, JK_P3_LHIP,    env)
        rhip   = LerpAngle(JK_P2_RHIP, JK_REST,        env)
        pedAng = LerpAngle(JK_REST,     JK_P3_PED_ANG,  env)
        pedPos = Vector(
            Lerp(env, JK_P2_PED_POS.x, 0),
            0,
            Lerp(env, JK_P2_PED_POS.z, 0)
        )

    else
        -- Phase 4: recovery
        local env = Smoothstep((t - JK_P3_END) / (1.0 - JK_P3_END))
        lhip   = LerpAngle(JK_P3_LHIP,    JK_REST,     env)
        rhip   = JK_REST
        pedAng = LerpAngle(JK_P3_PED_ANG, JK_REST,     env)
        pedPos = JK_REST_POS
    end

    if ent._jkLHipIdx >= 0 then ent:ManipulateBoneAngles(ent._jkLHipIdx,   lhip,   false) end
    if ent._jkRHipIdx >= 0 then ent:ManipulateBoneAngles(ent._jkRHipIdx,   rhip,   false) end
    if ent._jkPedIdx  >= 0 then ent:ManipulateBoneAngles(ent._jkPedIdx,    pedAng, false) end
    if ent._jkPedIdx  >= 0 then ent:ManipulateBonePosition(ent._jkPedIdx,  pedPos, false) end
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
    local dt = FrameTime()

    GekkoDoKickBone(self)
    GekkoDoHeadbuttBone(self)
    GekkoDoFK360Bone(self)
    GekkoDoSpinKickBone(self)
    GekkoDoFootballKickBone(self)
    GekkoDoDiagonalKickBone(self)
    GekkoDoHeelHookBone(self)
    GekkoDoSideHookKickBone(self)
    GekkoDoAxeKickBone(self)
    GekkoDoJumpKickBone(self)

    GekkoUpdateHead(self, dt)
    GekkoSyncFootsteps(self)
    GekkoFootShake(self)
    GekkoDoJumpDust(self)
    GekkoDoLandDust(self)
    GekkoDoFK360LandDust(self)
    GekkoDoMGFX(self)
    GekkoDoBloodSplat(self)
end
