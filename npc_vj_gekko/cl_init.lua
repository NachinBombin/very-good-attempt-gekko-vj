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
--  CRUSH HIT — net receiver
--  Plays a random body impact sound at the hit position and
--  fires a boosted screen shake from the Gekko's position.
-- ============================================================
local CRUSH_IMPACT_SOUNDS = {
    "physics/body/body_medium_impact_hard1.wav",
    "physics/body/body_medium_impact_hard2.wav",
    "physics/body/body_medium_impact_hard3.wav",
    "physics/body/body_medium_impact_hard4.wav",
    "physics/body/body_medium_impact_hard5.wav",
    "physics/body/body_medium_impact_hard6.wav",
}

local CRUSH_SHAKE_RADIUS = 750   -- matches SHAKE_FAR_DIST
local CRUSH_SHAKE_AMP    = 22    -- ~2x the walk-stomp near amplitude
local CRUSH_SHAKE_FREQ   = 18
local CRUSH_SHAKE_DUR    = 0.25

net.Receive("GekkoCrushHit", function()
    local hitPos   = net.ReadVector()
    local gekkoPos = net.ReadVector()

    -- Sound at the point of impact
    sound.Play(
        CRUSH_IMPACT_SOUNDS[math.random(#CRUSH_IMPACT_SOUNDS)],
        hitPos,
        85,     -- volume
        100     -- pitch
    )

    -- Boosted shake — distance-attenuated from the Gekko
    local ply = LocalPlayer()
    if IsValid(ply) then
        local dist  = ply:GetPos():Distance(gekkoPos)
        local alpha = 1 - math.Clamp(dist / CRUSH_SHAKE_RADIUS, 0, 1)
        if alpha > 0 then
            util.ScreenShake(
                gekkoPos,
                CRUSH_SHAKE_AMP * alpha,
                CRUSH_SHAKE_FREQ,
                CRUSH_SHAKE_DUR,
                CRUSH_SHAKE_RADIUS
            )
        end
    end
end)

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
--  HEAD DRIVER  (b_spine4)  — YAW + PITCH
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
--  JUMP DUST  (ThumperDust: Origin, Scale, Entity)
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
--  LAND DUST  (ThumperDust: Origin, Scale, Entity)
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
--  MG FIRING FX
--  RifleShellEject: Entity, Origin, Angles
--  ManhackSparks: intermittent
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
--  EXAGGERATED BLOOD SPLATTER
--
--  NW int "GekkoBloodSplat" packs:
--    high bits (>> 3) = rolling pulse   (changes every trigger)
--    low 3 bits       = variant index   (0-4)
--
--  5 variants — all massive, all different:
--    1  Geyser      — tall vertical column of blood blobs
--    2  Radial ring — blood sprays outward in a flat ring
--    3  Burst cloud — dense omnidirectional burst
--    4  Arc shower  — forward-biased high arc spray
--    5  Ground pool — low splat spread wide on the floor
-- ============================================================
local BLOOD_DECAL   = "Blood"
local BLOOD_DECAL2  = "YellowBlood"

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
    local e = EffectData()
    e:SetOrigin(pos)
    e:SetNormal(dir)
    e:SetScale(scale)
    e:SetMagnitude(speed * 0.05)
    e:SetRadius(math.random(12, 36))
    util.Effect("BloodImpact", e, false)

    local e2 = EffectData()
    e2:SetOrigin(pos)
    e2:SetNormal(dir)
    e2:SetScale(scale * math.Rand(0.6, 1.4))
    e2:SetMagnitude(math.Rand(8, 22))
    util.Effect("BloodSpray", e2, false)

    local tr = util.TraceLine({
        start  = pos,
        endpos = pos + dir * speed,
        mask   = MASK_SOLID_BRUSHONLY,
    })
    if tr.Hit then
        local decalName = (math.random(1, 6) == 1) and BLOOD_DECAL2 or BLOOD_DECAL
        util.Decal(decalName, tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal)
    end
end

local function BloodVariant_Geyser(origin)
    local count = math.random(18, 32)
    for _ = 1, count do
        local spread  = math.Rand(0.0, 0.35)
        local dir     = Vector(
            (math.random() - 0.5) * 2 * spread,
            (math.random() - 0.5) * 2 * spread,
            math.Rand(0.7, 1.0)
        )
        dir:Normalize()
        local spawnH  = math.Rand(20, 120)
        local speed   = math.Rand(800, 2200)
        local scale   = math.Rand(8, 22)
        SpawnBloodBlob(origin + Vector(0, 0, spawnH), dir, speed, scale)
    end
    for _ = 1, math.random(4, 8) do
        local e = EffectData()
        e:SetOrigin(origin + Vector((math.random()-0.5)*80, (math.random()-0.5)*80, 4))
        e:SetNormal(Vector(0,0,1))
        e:SetScale(math.Rand(12, 28))
        e:SetMagnitude(math.Rand(10, 30))
        util.Effect("BloodImpact", e, false)
    end
end

local function BloodVariant_RadialRing(origin)
    local spokes  = math.random(20, 36)
    local ringH   = math.Rand(40, 100)
    for i = 1, spokes do
        local angle = (i / spokes) * math.pi * 2
        local dir   = Vector(
            math.cos(angle),
            math.sin(angle),
            math.Rand(-0.15, 0.35)
        )
        dir:Normalize()
        local speed = math.Rand(700, 2400)
        local scale = math.Rand(10, 28)
        SpawnBloodBlob(origin + Vector(0,0,ringH), dir, speed, scale)
    end
    for _ = 1, math.random(6, 12) do
        local e = EffectData()
        e:SetOrigin(origin + Vector(0,0,ringH))
        e:SetNormal(RandBiasedDir(Vector(0,0,1), 0.3))
        e:SetScale(math.Rand(15, 35))
        e:SetMagnitude(math.Rand(15, 40))
        util.Effect("BloodImpact", e, false)
    end
end

local function BloodVariant_BurstCloud(origin)
    local count = math.random(28, 50)
    for _ = 1, count do
        local dir   = RandBiasedDir(Vector(0,0,0.4), 0)
        local h     = math.Rand(30, 160)
        local speed = math.Rand(600, 2800)
        local scale = math.Rand(10, 30)
        SpawnBloodBlob(origin + Vector(0, 0, h), dir, speed, scale)
    end
    for _ = 1, math.random(8, 16) do
        local e = EffectData()
        e:SetOrigin(origin + Vector(
            (math.random()-0.5)*120,
            (math.random()-0.5)*120,
            math.Rand(10, 180)
        ))
        e:SetNormal(RandBiasedDir(Vector(0,0,1), 0.2))
        e:SetScale(math.Rand(18, 40))
        e:SetMagnitude(math.Rand(20, 50))
        util.Effect("BloodImpact", e, false)
    end
end

local function BloodVariant_ArcShower(origin, forwardDir)
    local count = math.random(22, 40)
    for _ = 1, count do
        local dir   = RandBiasedDir(forwardDir + Vector(0,0,0.5), 0.55)
        local h     = math.Rand(60, 180)
        local speed = math.Rand(1000, 3000)
        local scale = math.Rand(8, 24)
        SpawnBloodBlob(origin + Vector(0, 0, h), dir, speed, scale)
    end
    for _ = 1, math.random(4, 10) do
        local side  = RandBiasedDir(Vector(
            (math.random()-0.5)*2, (math.random()-0.5)*2, 0.1), 0.1)
        local e = EffectData()
        e:SetOrigin(origin + Vector(0, 0, math.Rand(30, 100)))
        e:SetNormal(side)
        e:SetScale(math.Rand(12, 32))
        e:SetMagnitude(math.Rand(12, 35))
        util.Effect("BloodImpact", e, false)
    end
end

local function BloodVariant_GroundPool(origin)
    local count = math.random(20, 38)
    for _ = 1, count do
        local angle = math.Rand(0, math.pi * 2)
        local dir   = Vector(
            math.cos(angle),
            math.sin(angle),
            math.Rand(-0.05, 0.25)
        )
        dir:Normalize()
        local speed = math.Rand(600, 2000)
        local scale = math.Rand(14, 36)
        SpawnBloodBlob(origin + Vector(0, 0, math.Rand(5, 40)), dir, speed, scale)
    end
    for _ = 1, math.random(5, 10) do
        local e = EffectData()
        e:SetOrigin(origin + Vector(
            (math.random()-0.5)*100,
            (math.random()-0.5)*100,
            2
        ))
        e:SetNormal(Vector(0, 0, 1))
        e:SetScale(math.Rand(20, 50))
        e:SetMagnitude(math.Rand(20, 55))
        util.Effect("BloodImpact", e, false)
    end
end

local function GekkoDoBloodSplat(ent)
    local packed = ent:GetNWInt("GekkoBloodSplat", 0)
    if packed == 0 then return end

    local pulse   = math.floor(packed / 8)
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
--  THINK  — all effect dispatches here
-- ============================================================
function ENT:Think()
    GekkoDoJumpDust(self)
    GekkoDoLandDust(self)
    GekkoDoMGFX(self)
    GekkoDoBloodSplat(self)
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

    self:DrawModel()
end
