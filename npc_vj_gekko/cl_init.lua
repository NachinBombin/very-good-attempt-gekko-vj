include("shared.lua")

-- ============================================================
--  BONE OWNERSHIP TABLE
--
--  Central registry: maps bone-name → owning driver name (or nil).
--  A driver calls BoneClaim(name, owner, duration) to take a bone.
--  BoneOwned(name, owner) returns true only if that driver owns it.
--  BoneRelease(name) is called once by the owner on expiry.
--
--  Rules:
--    • Higher-priority drivers claim first each Think/Draw.
--    • A driver must NOT write a bone it does not own.
--    • On release the driver writes a single reset then goes silent.
-- ============================================================
local _boneOwner   = {}   -- [boneName] = { owner=string, expiry=number }

local function BoneClaim(name, owner, expiry)
    _boneOwner[name] = { owner = owner, expiry = expiry }
end

local function BoneOwned(name, owner)
    local rec = _boneOwner[name]
    if not rec then return false end
    if CurTime() > rec.expiry then
        _boneOwner[name] = nil
        return false
    end
    return rec.owner == owner
end

local function BoneExpired(name)
    local rec = _boneOwner[name]
    if not rec then return true end
    if CurTime() > rec.expiry then
        _boneOwner[name] = nil
        return true
    end
    return false
end

-- ============================================================
--  LOW-LEVEL HELPERS
-- ============================================================
local function SetBoneAng(ent, name, ang)
    local id = ent:LookupBone(name)
    if id and id >= 0 then ent:ManipulateBoneAngles(id, ang, false) end
end

local function SetBonePos(ent, name, pos)
    local id = ent:LookupBone(name)
    if id and id >= 0 then ent:ManipulateBonePosition(id, pos, false) end
end

local function SetBoneAngIdx(ent, idx, ang)
    if idx and idx >= 0 then ent:ManipulateBoneAngles(idx, ang, false) end
end

local function SetBonePosIdx(ent, idx, pos)
    if idx and idx >= 0 then ent:ManipulateBonePosition(idx, pos, false) end
end

-- ============================================================
--  JUMP STATE CONSTANTS  (mirror shared.lua)
-- ============================================================
local JUMP_NONE    = 0
local JUMP_RISING  = 1
local JUMP_FALLING = 2
local JUMP_LAND    = 3

-- ============================================================
--  SMOOTHSTEP
-- ============================================================
local function Smoothstep(t)
    t = math.Clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

-- ============================================================
--  DRIVER: STOMP LEGS
--  Bones owned: b_r_thigh, b_r_upperleg, b_r_calf, b_r_foot,
--               b_r_toe, b_l_thigh, b_l_upperleg, b_l_calf,
--               b_l_foot, b_l_toe, b_pelvis (angle only),
--               b_r_hippiston1, b_l_hippiston1
-- ============================================================
local DRIVER_STOMP = "stomp"

local function GekkoStompLegs(ent)
    local t      = CurTime()
    local freq   = 14
    local amp    = 55
    local phaseR = t * freq
    local phaseL = t * freq + math.pi

    -- Each bone is only written if no higher-priority driver owns it
    local function W(name, ang)
        if BoneExpired(name) then SetBoneAng(ent, name, ang) end
    end

    W("b_r_thigh",      Angle(math.sin(phaseR)         * amp,        0, 0))
    W("b_r_upperleg",   Angle(math.sin(phaseR + 0.4)   * amp * 0.7,  0, 0))
    W("b_r_calf",       Angle(math.sin(phaseR + 0.9)   * amp * 0.5,  0, 0))
    W("b_r_foot",       Angle(math.sin(phaseR + 1.2)   * -amp * 0.4, 0, 0))
    W("b_r_toe",        Angle(math.sin(phaseR + 1.5)   * -amp * 0.3, 0, 0))
    W("b_l_thigh",      Angle(math.sin(phaseL)         * amp,        0, 0))
    W("b_l_upperleg",   Angle(math.sin(phaseL + 0.4)   * amp * 0.7,  0, 0))
    W("b_l_calf",       Angle(math.sin(phaseL + 0.9)   * amp * 0.5,  0, 0))
    W("b_l_foot",       Angle(math.sin(phaseL + 1.2)   * -amp * 0.4, 0, 0))
    W("b_l_toe",        Angle(math.sin(phaseL + 1.5)   * -amp * 0.3, 0, 0))
    W("b_r_hippiston1", Angle(math.sin(phaseR) * amp * 0.4, 0, 0))
    W("b_l_hippiston1", Angle(math.sin(phaseL) * amp * 0.4, 0, 0))

    -- b_pelvis angle: only write if not owned by a higher-priority driver
    if BoneExpired("b_pelvis_ang") then
        local slam = math.abs(math.sin(t * freq * 0.5)) * 12
        SetBoneAng(ent, "b_pelvis", Angle(slam, 0, 0))
    end
end

-- ============================================================
--  DRIVER: KICK  (b_r_upperleg angle)
-- ============================================================
local DRIVER_KICK  = "kick"
local KICK_WINDOW  = 1.0
local KICK_BONE    = "b_r_upperleg"
local KICK_ANG_ON  = Angle(112, 0, 0)
local KICK_ANG_OFF = Angle(0,   0, 0)

local function GekkoDoKickBone(ent)
    if ent._kickInited == nil then
        ent._kickInited    = true
        ent._kickBoneIdx   = ent:LookupBone(KICK_BONE) or -1
        ent._kickEndTime   = 0
        ent._kickPulseLast = ent:GetNWInt("GekkoKickPulse", 0)
        ent._kickWasActive = false
    end

    local pulse = ent:GetNWInt("GekkoKickPulse", 0)
    if pulse ~= ent._kickPulseLast then
        ent._kickPulseLast = pulse
        ent._kickEndTime   = CurTime() + KICK_WINDOW
    end

    local active = CurTime() < ent._kickEndTime
    local idx    = ent._kickBoneIdx

    if active then
        -- Claim the bone for the window duration
        BoneClaim(KICK_BONE, DRIVER_KICK, ent._kickEndTime)
        ent._kickWasActive = true
        SetBoneAngIdx(ent, idx, KICK_ANG_ON)

    elseif ent._kickWasActive then
        -- Release: reset once, then silence
        ent._kickWasActive = false
        _boneOwner[KICK_BONE] = nil
        SetBoneAngIdx(ent, idx, KICK_ANG_OFF)
    end
    -- idle: write nothing
end

-- ============================================================
--  DRIVER: HEADBUTT  (b_spine3 angle, b_pedestal position)
-- ============================================================
local DRIVER_HB      = "headbutt"
local HB_DURATION    = 0.8
local HB_PEAK        = 0.4
local HB_SPINE3_X    = -60
local HB_PED_POS_X   =  70
local HB_PED_POS_Z   = -45
local HB_SPINE3_BONE = "b_spine3"
local HB_PED_BONE    = "b_pedestal"

local function GekkoDoHeadbuttBone(ent)
    if ent._hbInited == nil then
        ent._hbInited      = true
        ent._hbSpineIdx    = ent:LookupBone(HB_SPINE3_BONE) or -1
        ent._hbPedestalIdx = ent:LookupBone(HB_PED_BONE)    or -1
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
    local active  = (elapsed >= 0 and elapsed < HB_DURATION)

    if active then
        local expiry = ent._hbStartTime + HB_DURATION
        BoneClaim(HB_SPINE3_BONE, DRIVER_HB, expiry)
        BoneClaim(HB_PED_BONE,    DRIVER_HB, expiry)
        ent._hbWasActive = true

        local t = elapsed / HB_DURATION
        local env
        if t < HB_PEAK then
            env = Smoothstep(t / HB_PEAK)
        else
            env = Smoothstep(1 - (t - HB_PEAK) / (1 - HB_PEAK))
        end

        SetBoneAngIdx(ent, ent._hbSpineIdx,    Angle(HB_SPINE3_X * env, 0, 0))
        SetBonePosIdx(ent, ent._hbPedestalIdx, Vector(HB_PED_POS_X * env, 0, HB_PED_POS_Z * env))

    elseif ent._hbWasActive then
        ent._hbWasActive = false
        _boneOwner[HB_SPINE3_BONE] = nil
        _boneOwner[HB_PED_BONE]    = nil
        SetBoneAngIdx(ent, ent._hbSpineIdx,    Angle(0, 0, 0))
        SetBonePosIdx(ent, ent._hbPedestalIdx, Vector(0, 0, 0))
    end
end

-- ============================================================
--  DRIVER: FRONT KICK 360  (b_pelvis angle pitch — forward flip)
--
--  Uses the virtual key "b_pelvis_ang" for the ownership table
--  to distinguish from b_pelvis position (used by SpinKick).
-- ============================================================
local DRIVER_FK360    = "fk360"
local FK360_DURATION  = 0.8
local FK360_RAMP      = 0.15
local FK360_BONE      = "b_pelvis"
local FK360_OWNER_KEY = "b_pelvis_ang"   -- virtual ownership slot

local function GekkoDoFrontKick360Bone(ent)
    if ent._fk360Inited == nil then
        ent._fk360Inited    = true
        ent._fk360BoneIdx   = ent:LookupBone(FK360_BONE) or -1
        ent._fk360StartTime = -9999
        ent._fk360PulseLast = ent:GetNWInt("GekkoFrontKick360Pulse", 0)
        ent._fk360Pitch     = 0
        ent._fk360LastT     = CurTime()
        ent._fk360WasActive = false
    end

    local pulse = ent:GetNWInt("GekkoFrontKick360Pulse", 0)
    if pulse ~= ent._fk360PulseLast then
        ent._fk360PulseLast = pulse
        ent._fk360StartTime = CurTime()
        ent._fk360Pitch     = 0
        ent._fk360LastT     = CurTime()
        print(string.format("[GekkoFrontKick360] pulse=%d", pulse))
    end

    local elapsed = CurTime() - ent._fk360StartTime
    local active  = (elapsed >= 0 and elapsed < FK360_DURATION)

    if active then
        -- SpinKick has higher priority — if it owns b_pelvis_ang, yield
        if BoneOwned(FK360_OWNER_KEY, DRIVER_FK360) == false and
           not BoneExpired(FK360_OWNER_KEY) then
            -- someone else owns it (SpinKick); do not write
            return
        end

        local expiry = ent._fk360StartTime + FK360_DURATION
        BoneClaim(FK360_OWNER_KEY, DRIVER_FK360, expiry)
        ent._fk360WasActive = true

        local peakSpeed = 360.0 / ((1.0 - FK360_RAMP) * FK360_DURATION)
        local t = elapsed / FK360_DURATION
        local env
        if t < FK360_RAMP then
            env = Smoothstep(t / FK360_RAMP)
        elseif t > (1.0 - FK360_RAMP) then
            env = Smoothstep((1.0 - t) / FK360_RAMP)
        else
            env = 1.0
        end

        local now = CurTime()
        local dt  = math.Clamp(now - ent._fk360LastT, 0, 0.05)
        ent._fk360LastT = now
        ent._fk360Pitch = ent._fk360Pitch + peakSpeed * env * dt

        SetBoneAngIdx(ent, ent._fk360BoneIdx, Angle(ent._fk360Pitch, 0, 0))

    elseif ent._fk360WasActive then
        ent._fk360WasActive = false
        _boneOwner[FK360_OWNER_KEY] = nil
        ent._fk360Pitch = 0
        SetBoneAngIdx(ent, ent._fk360BoneIdx, Angle(0, 0, 0))
    end
end

-- ============================================================
--  DRIVER: SPIN KICK  (4th kick — highest bone priority)
--
--  Bones owned exclusively during window:
--    b_Pedestal     → angle Y (yaw spin)
--    b_pelvis_ang   → angle (pitch — body tips forward into spin)
--    b_pelvis_pos   → position Z (body drops)
--    b_r_hippiston1 → angle Z
--    b_r_upperleg   → angle X
--
--  This driver claims all five slots at the start of the window.
--  Every other driver sees these slots as owned and skips them.
-- ============================================================
local DRIVER_SK        = "spinkick"
local SK_DURATION      = 0.9
local SK_RAMP          = 0.12

local SK_PED_BONE      = "b_Pedestal"
local SK_PELVIS_BONE   = "b_pelvis"
local SK_HIPPISTON_BONE= "b_r_hippiston1"
local SK_UPPERLEG_BONE = "b_r_upperleg"

-- Virtual ownership keys (distinguish angle vs position on same bone)
local SK_OWN_PED       = "b_Pedestal_ang"
local SK_OWN_PELVIS_ANG= "b_pelvis_ang"
local SK_OWN_PELVIS_POS= "b_pelvis_pos"
local SK_OWN_HIPPISTON = "b_r_hippiston1"
local SK_OWN_UPPERLEG  = "b_r_upperleg"

-- Pose parameters — tuned from working test
local SK_PELVIS_DROP   = -50    -- position Z
local SK_PELVIS_PITCH  = 45     -- angle P (tips body forward into flip)
local SK_HIPPISTON_Z   = -22    -- angle roll
local SK_UPPERLEG_X    = 120    -- angle pitch (leg raised)

local function GekkoDoSpinKickBone(ent)
    if ent._skInited == nil then
        ent._skInited        = true
        ent._skPedIdx        = ent:LookupBone(SK_PED_BONE)       or -1
        ent._skPelvisIdx     = ent:LookupBone(SK_PELVIS_BONE)    or -1
        ent._skHippistonIdx  = ent:LookupBone(SK_HIPPISTON_BONE) or -1
        ent._skUpperlegIdx   = ent:LookupBone(SK_UPPERLEG_BONE)  or -1
        ent._skStartTime     = -9999
        ent._skPulseLast     = ent:GetNWInt("GekkoSpinKickPulse", 0)
        ent._skYaw           = 0
        ent._skLastT         = CurTime()
        ent._skWasActive     = false
    end

    local pulse = ent:GetNWInt("GekkoSpinKickPulse", 0)
    if pulse ~= ent._skPulseLast then
        ent._skPulseLast = pulse
        ent._skStartTime = CurTime()
        ent._skYaw       = 0
        ent._skLastT     = CurTime()
        print(string.format("[GekkoSpinKick] pulse=%d", pulse))
    end

    local elapsed = CurTime() - ent._skStartTime
    local active  = (elapsed >= 0 and elapsed < SK_DURATION)

    if active then
        -- Claim all bones for the full window duration
        local expiry = ent._skStartTime + SK_DURATION
        BoneClaim(SK_OWN_PED,        DRIVER_SK, expiry)
        BoneClaim(SK_OWN_PELVIS_ANG, DRIVER_SK, expiry)
        BoneClaim(SK_OWN_PELVIS_POS, DRIVER_SK, expiry)
        BoneClaim(SK_OWN_HIPPISTON,  DRIVER_SK, expiry)
        BoneClaim(SK_OWN_UPPERLEG,   DRIVER_SK, expiry)
        ent._skWasActive = true

        -- Ramp envelope
        local peakSpeed = 360.0 / ((1.0 - SK_RAMP) * SK_DURATION)
        local t = elapsed / SK_DURATION
        local env
        if t < SK_RAMP then
            env = Smoothstep(t / SK_RAMP)
        elseif t > (1.0 - SK_RAMP) then
            env = Smoothstep((1.0 - t) / SK_RAMP)
        else
            env = 1.0
        end

        local now = CurTime()
        local dt  = math.Clamp(now - ent._skLastT, 0, 0.05)
        ent._skLastT = now
        ent._skYaw   = ent._skYaw + peakSpeed * env * dt

        -- b_Pedestal: yaw spin
        SetBoneAngIdx(ent, ent._skPedIdx, Angle(0, ent._skYaw, 0))

        -- b_pelvis: drop body down + tip it forward into the spin
        SetBonePosIdx(ent, ent._skPelvisIdx, Vector(0, 0, SK_PELVIS_DROP))
        SetBoneAngIdx(ent, ent._skPelvisIdx, Angle(SK_PELVIS_PITCH * env, 0, 0))

        -- Leg pose
        SetBoneAngIdx(ent, ent._skHippistonIdx, Angle(0, 0, SK_HIPPISTON_Z))
        SetBoneAngIdx(ent, ent._skUpperlegIdx,  Angle(SK_UPPERLEG_X, 0, 0))

    elseif ent._skWasActive then
        -- Release all bones once, then silence
        ent._skWasActive = false
        ent._skYaw       = 0
        _boneOwner[SK_OWN_PED]        = nil
        _boneOwner[SK_OWN_PELVIS_ANG] = nil
        _boneOwner[SK_OWN_PELVIS_POS] = nil
        _boneOwner[SK_OWN_HIPPISTON]  = nil
        _boneOwner[SK_OWN_UPPERLEG]   = nil

        SetBoneAngIdx(ent, ent._skPedIdx,        Angle(0, 0, 0))
        SetBonePosIdx(ent, ent._skPelvisIdx,     Vector(0, 0, 0))
        SetBoneAngIdx(ent, ent._skPelvisIdx,     Angle(0, 0, 0))
        SetBoneAngIdx(ent, ent._skHippistonIdx,  Angle(0, 0, 0))
        SetBoneAngIdx(ent, ent._skUpperlegIdx,   Angle(0, 0, 0))
    end
    -- idle: write nothing
end

-- ============================================================
--  DRIVER: HEAD  (b_spine4 angle)
-- ============================================================
local HEAD_LIMIT      =  50
local HEAD_PITCH_UP   = -60
local HEAD_PITCH_DOWN =  60
local HEAD_SPEED      =  30

local function GekkoUpdateHead(ent, dt)
    local bone = ent._spineBone
    if not bone or bone < 0 then return end
    ent._headYaw   = ent._headYaw   or 0
    ent._headPitch = ent._headPitch or 0
    local enemy      = ent:GetNWEntity("GekkoEnemy", NULL)
    local tgtYaw, tgtPitch = 0, 0
    if IsValid(enemy) then
        local bm  = ent:GetBoneMatrix(bone)
        local pos = bm and bm:GetTranslation() or (ent:GetPos() + Vector(0, 0, 130))
        local toE = (enemy:GetPos() + Vector(0, 0, 40) - pos):Angle()
        tgtYaw   = math.Clamp(math.NormalizeAngle(toE.y - ent:GetAngles().y), -HEAD_LIMIT, HEAD_LIMIT)
        tgtPitch = math.Clamp(toE.p, HEAD_PITCH_UP, HEAD_PITCH_DOWN)
    end
    local step = HEAD_SPEED * dt
    ent._headYaw   = math.Clamp(ent._headYaw   + math.Clamp(math.NormalizeAngle(tgtYaw   - ent._headYaw),   -step, step), -HEAD_LIMIT,   HEAD_LIMIT)
    ent._headPitch = math.Clamp(ent._headPitch + math.Clamp(tgtPitch - ent._headPitch,                      -step, step),  HEAD_PITCH_UP, HEAD_PITCH_DOWN)
    ent:ManipulateBoneAngles(bone, Angle(-ent._headYaw, 0, ent._headPitch), false)
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
    if vel < 8 then ent._stepPhaseR = nil; ent._stepPhaseL = nil; return end
    local cycleHz = (vel > 160) and 1.1 or 0.71
    local cycleT  = CurTime() * cycleHz * 2 * math.pi
    local sinR = math.sin(cycleT)
    local sinL = math.sin(cycleT + math.pi)
    local prevR = ent._stepPhaseR or sinR
    local prevL = ent._stepPhaseL or sinL
    ent._stepPhaseR = sinR
    ent._stepPhaseL = sinL
    local pitch = (vel > 160) and math.random(58, 68) or math.random(70, 80)
    local vol   = (vel > 160) and 88 or 80
    if prevR > 0 and sinR <= 0 then ent:EmitSound(STEP_SOUNDS[math.random(#STEP_SOUNDS)], vol, pitch) end
    if prevL > 0 and sinL <= 0 then ent:EmitSound(STEP_SOUNDS[math.random(#STEP_SOUNDS)], vol, pitch) end
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
    if not ((prevR > 0 and sinR <= 0) or (prevL > 0 and sinL <= 0)) then return end
    local alpha = 1 - (dist / SHAKE_FAR_DIST)
    local amp   = (dist < SHAKE_NEAR_DIST) and (12 * alpha) or (5 * alpha)
    util.ScreenShake(ent:GetPos(), amp, 14, 0.18, SHAKE_FAR_DIST)
end

-- ============================================================
--  JUMP DUST
-- ============================================================
local function GekkoDoJumpDust(ent)
    local pulse = ent:GetNWInt("GekkoJumpDust", 0)
    if pulse == 0 then return end
    if pulse == ent._lastJumpDustPulse then return end
    ent._lastJumpDustPulse = pulse
    local e = EffectData()
    e:SetOrigin(ent:GetPos()); e:SetScale(math.random(80, 200)); e:SetEntity(ent)
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
    e:SetOrigin(ent:GetPos()); e:SetScale(math.random(80, 200)); e:SetEntity(ent)
    util.Effect("ThumperDust", e, false)
    util.Effect("ThumperDust", e, false)
    util.Effect("ThumperDust", e, false)
end

-- ============================================================
--  MG FIRING FX
-- ============================================================
local ATT_MACHINEGUN  = 3
local SHELL_INTERVAL  = 0.09

local function GekkoDoMGFX(ent)
    if not ent:GetNWBool("GekkoMGFiring", false) then
        ent._nextSparkT = nil; ent._nextShellT = nil; return
    end
    local attData = ent:GetAttachment(ATT_MACHINEGUN)
    if not attData then return end
    local pos, ang = attData.Pos, attData.Ang
    local now = CurTime()
    if not ent._nextShellT or now >= ent._nextShellT then
        ent._nextShellT = now + SHELL_INTERVAL
        local e = EffectData(); e:SetEntity(ent); e:SetOrigin(pos); e:SetAngles(ang)
        util.Effect("RifleShellEject", e, false)
    end
    if not ent._nextSparkT or now >= ent._nextSparkT then
        ent._nextSparkT = now + math.Rand(1.5, 3.5)
        local fwd = ang:Forward()
        local e = EffectData()
        e:SetOrigin(pos + fwd * 8); e:SetNormal(fwd); e:SetAngles(ang); e:SetEntity(ent)
        e:SetMagnitude(math.Rand(2,6)); e:SetScale(math.Rand(0.5,2.0)); e:SetRadius(math.random(8,20))
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
    local r = Vector((math.random()-0.5)*2, (math.random()-0.5)*2, (math.random()-0.5)*2)
    r:Normalize()
    return (r + dir * bias):GetNormalized()
end

local function SpawnBloodBlob(pos, dir, speed, scale)
    local s = BLOOD_SIZE; local sp = speed * s
    local e = EffectData(); e:SetOrigin(pos); e:SetNormal(dir)
    e:SetScale(scale * s); e:SetMagnitude(sp * 0.05); e:SetRadius(math.random(12,36)*s)
    util.Effect("BloodImpact", e, false)
    local e2 = EffectData(); e2:SetOrigin(pos); e2:SetNormal(dir)
    e2:SetScale(scale*math.Rand(0.6,1.4)*s); e2:SetMagnitude(math.Rand(8,22)*s)
    util.Effect("BloodSpray", e2, false)
    local tr = util.TraceLine({start=pos, endpos=pos+dir*sp, mask=MASK_SOLID_BRUSHONLY})
    if tr.Hit then
        util.Decal((math.random(1,6)==1) and BLOOD_DECAL2 or BLOOD_DECAL,
            tr.HitPos+tr.HitNormal, tr.HitPos-tr.HitNormal)
    end
end

local function BloodVariant_Geyser(origin)
    local s=BLOOD_SIZE; local count=math.random(18,32)
    for _=1,count do
        local sp=math.Rand(0,0.35)
        local d=Vector((math.random()-0.5)*2*sp,(math.random()-0.5)*2*sp,math.Rand(0.7,1.0)); d:Normalize()
        SpawnBloodBlob(origin+Vector(0,0,math.Rand(20,120)*s),d,math.Rand(800,2200),math.Rand(8,22))
    end
    for _=1,math.random(4,8) do
        local e=EffectData(); e:SetOrigin(origin+Vector((math.random()-0.5)*80*s,(math.random()-0.5)*80*s,4))
        e:SetNormal(Vector(0,0,1)); e:SetScale(math.Rand(12,28)*s); e:SetMagnitude(math.Rand(10,30)*s)
        util.Effect("BloodImpact",e,false)
    end
end

local function BloodVariant_RadialRing(origin)
    local s=BLOOD_SIZE; local spokes=math.random(20,36); local ringH=math.Rand(40,100)*s
    for i=1,spokes do
        local a=(i/spokes)*math.pi*2
        local d=Vector(math.cos(a),math.sin(a),math.Rand(-0.15,0.35)); d:Normalize()
        SpawnBloodBlob(origin+Vector(0,0,ringH),d,math.Rand(700,2400),math.Rand(10,28))
    end
    for _=1,math.random(6,12) do
        local e=EffectData(); e:SetOrigin(origin+Vector(0,0,ringH))
        e:SetNormal(RandBiasedDir(Vector(0,0,1),0.3)); e:SetScale(math.Rand(15,35)*s); e:SetMagnitude(math.Rand(15,40)*s)
        util.Effect("BloodImpact",e,false)
    end
end

local function BloodVariant_BurstCloud(origin)
    local s=BLOOD_SIZE
    for _=1,math.random(28,50) do
        SpawnBloodBlob(origin+Vector(0,0,math.Rand(30,160)*s),
            RandBiasedDir(Vector(0,0,0.4),0),math.Rand(600,2800),math.Rand(10,30))
    end
    for _=1,math.random(8,16) do
        local e=EffectData()
        e:SetOrigin(origin+Vector((math.random()-0.5)*120*s,(math.random()-0.5)*120*s,math.Rand(10,180)*s))
        e:SetNormal(RandBiasedDir(Vector(0,0,1),0.2)); e:SetScale(math.Rand(18,40)*s); e:SetMagnitude(math.Rand(20,50)*s)
        util.Effect("BloodImpact",e,false)
    end
end

local function BloodVariant_ArcShower(origin, fwd)
    local s=BLOOD_SIZE
    for _=1,math.random(22,40) do
        SpawnBloodBlob(origin+Vector(0,0,math.Rand(60,180)*s),
            RandBiasedDir(fwd+Vector(0,0,0.5),0.55),math.Rand(1000,3000),math.Rand(8,24))
    end
    for _=1,math.random(4,10) do
        local e=EffectData(); e:SetOrigin(origin+Vector(0,0,math.Rand(30,100)*s))
        e:SetNormal(RandBiasedDir(Vector((math.random()-0.5)*2,(math.random()-0.5)*2,0.1),0.1))
        e:SetScale(math.Rand(12,32)*s); e:SetMagnitude(math.Rand(12,35)*s)
        util.Effect("BloodImpact",e,false)
    end
end

local function BloodVariant_GroundPool(origin)
    local s=BLOOD_SIZE
    for _=1,math.random(20,38) do
        local a=math.Rand(0,math.pi*2)
        local d=Vector(math.cos(a),math.sin(a),math.Rand(-0.05,0.25)); d:Normalize()
        SpawnBloodBlob(origin+Vector(0,0,math.Rand(5,40)*s),d,math.Rand(600,2000),math.Rand(14,36))
    end
    for _=1,math.random(5,10) do
        local e=EffectData()
        e:SetOrigin(origin+Vector((math.random()-0.5)*100*s,(math.random()-0.5)*100*s,2))
        e:SetNormal(Vector(0,0,1)); e:SetScale(math.Rand(20,50)*s); e:SetMagnitude(math.Rand(20,55)*s)
        util.Effect("BloodImpact",e,false)
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
--  SONAR LOCK
-- ============================================================
local SONAR_SOUND          = "mac_bo2_m32/Sonar intercept.wav"
local SONAR_DURATION       = 3.0
local SONAR_PULSE_COUNT    = 3
local SONAR_PULSE_INTERVAL = 0.6
local SONAR_RING_THICKNESS = 12
local SONAR_PEAK_ALPHA     = 220
local SONAR_TINT_ALPHA     = 80
local SONAR_R, SONAR_G, SONAR_B = 0, 200, 255
local sonar_startTime = nil
local sonar_active    = false

net.Receive("GekkoSonarLock", function()
    local ply = LocalPlayer()
    if IsValid(ply) then sound.Play(SONAR_SOUND, ply:GetPos(), 75, 100) end
    sonar_startTime = CurTime()
    sonar_active    = true
    print("[GekkoSonar] TRIGGERED  t=" .. tostring(sonar_startTime))
end)

local function DrawRingOutline(cx, cy, radius, thick, r, g, b, a)
    if radius <= 0 or a <= 0 then return end
    local steps  = math.max(48, math.floor(radius * 0.4))
    local prev_x = cx + radius; local prev_y = cy
    for i = 1, steps do
        local ang = (i / steps) * math.pi * 2
        local nx  = cx + math.cos(ang) * radius
        local ny  = cy + math.sin(ang) * radius
        local mx  = (prev_x + nx) * 0.5; local my = (prev_y + ny) * 0.5
        local dx  = nx - prev_x; local dy = ny - prev_y
        local len = math.sqrt(dx*dx + dy*dy)
        if len > 0 then
            surface.SetDrawColor(r, g, b, a)
            surface.DrawRect(math.floor(mx-len*0.5), math.floor(my-thick*0.5), math.ceil(len+1), thick)
        end
        prev_x = nx; prev_y = ny
    end
end

hook.Add("HUDPaint", "GekkoSonarEffect", function()
    if not sonar_active then return end
    local now     = CurTime()
    local elapsed = now - sonar_startTime
    if elapsed >= SONAR_DURATION then sonar_active = false; return end
    local sw, sh   = ScrW(), ScrH()
    local cx, cy   = sw * 0.5, sh * 0.5
    local gFade    = 1 - math.Clamp(elapsed / SONAR_DURATION, 0, 1)
    local tintFade = math.max(0, 1 - elapsed / (SONAR_DURATION * 0.4))
    local tintA    = math.floor(SONAR_TINT_ALPHA * tintFade * gFade)
    if tintA > 0 then surface.SetDrawColor(SONAR_R, SONAR_G, SONAR_B, tintA); surface.DrawRect(0, 0, sw, sh) end
    local maxR = math.sqrt(cx*cx + cy*cy) * 1.1
    for i = 0, SONAR_PULSE_COUNT - 1 do
        local pStart = i * SONAR_PULSE_INTERVAL
        local pAge   = elapsed - pStart
        if pAge < 0 then continue end
        local pDur = SONAR_PULSE_INTERVAL + 0.5
        local t = math.Clamp(pAge / pDur, 0, 1); if t >= 1 then continue end
        local riseEnd = 0.12
        local pA = (t < riseEnd) and (t / riseEnd) or (1 - (t - riseEnd) / (1 - riseEnd))
        pA = pA * pA
        local fA = math.floor(SONAR_PEAK_ALPHA * pA * gFade); if fA <= 0 then continue end
        DrawRingOutline(cx, cy, maxR * (0.05 + t * 0.95), SONAR_RING_THICKNESS, SONAR_R, SONAR_G, SONAR_B, fA)
    end
end)

-- ============================================================
--  THINK
-- ============================================================
function ENT:Think()
    GekkoDoJumpDust(self)
    GekkoDoLandDust(self)
    GekkoDoMGFX(self)
    GekkoDoBloodSplat(self)
end

-- ============================================================
--  DRAW
--
--  Driver execution order (highest bone priority first):
--    1. GekkoDoSpinKickBone      — claims all its bones first
--    2. GekkoDoFrontKick360Bone  — yields to SpinKick on b_pelvis_ang
--    3. GekkoDoHeadbuttBone      — b_spine3, b_pedestal pos
--    4. GekkoDoKickBone          — b_r_upperleg
--    5. GekkoStompLegs           — all leg bones, skips owned ones
--    6. GekkoUpdateHead          — b_spine4 (never contested)
--
--  No driver writes a bone that another driver owns on this frame.
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

    if not landing then GekkoUpdateHead(self, dt) end
    if not landing then GekkoSyncFootsteps(self); GekkoFootShake(self) end

    local grounded = (jumpState == JUMP_NONE)
    local stompEnd = self:GetNWFloat("GekkoStompEnd", 0)
    if t < stompEnd and grounded then GekkoStompLegs(self) end

    -- Attack drivers run in priority order (SpinKick first to claim bones)
    GekkoDoSpinKickBone(self)
    GekkoDoFrontKick360Bone(self)
    GekkoDoHeadbuttBone(self)
    GekkoDoKickBone(self)

    self:DrawModel()
end
