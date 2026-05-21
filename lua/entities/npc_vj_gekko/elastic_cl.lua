-- ============================================================
--  ELASTIC SLING SYSTEM  (client-side)
--
--  THREE PHASES per beam:
--
--  [EXTENDING]  t = 0->1  over  dist / EXTEND_SPEED  seconds
--  [ATTACHED]   full verlet sag, both endpoints live
--  [RETRACTING] tip travels back to gekko via same cosine path
--
--  On key-smash break (b.breakRetracting == true):
--    Every frame the retracting tip position is computed.
--    EmitRetractTrail() fires at that exact world position:
--      * gekko_bloodstream effect (blood mist + stream)
--      * orange spark particles
--    Throttled by b.trailNextT at TRAIL_INTERVAL seconds.
-- ============================================================

-- ============================================================
--  CONFIG
-- ============================================================
local ROPE_NODES      = 14
local ROPE_GRAVITY    = Vector(0, 0, -340)
local ROPE_DAMPING    = 0.86
local ROPE_CONSTRAINT = 6
local ROPE_SLACK      = 1.06

local EXTEND_SPEED      = 600
local EXTEND_AMP        = 28
local EXTEND_FREQ_START = 2.5
local EXTEND_FREQ_END   = 6.0
local EXTEND_JITTER     = 3.2

-- Trail emit interval during break-retract (~18 Hz)
local TRAIL_INTERVAL = 0.055

-- ============================================================
--  STATE
-- ============================================================
local activeBeams    = {}
local GEKKO_ORIGIN_Z = 180

-- ============================================================
--  SOUNDS
-- ============================================================
local SHOOT_SOUNDS = {
    "gekko/elastic/shoot_1.wav",
    "gekko/elastic/shoot_2.wav",
    "gekko/elastic/shoot_3.wav",
    "gekko/elastic/shoot_4.wav",
    "gekko/elastic/shoot_5.wav",
}
local TENTACLE_LOOP   = "gekko/elastic/tentaclepull_1.wav"
local TENTACLE_STAB   = "gekko/elastic/tentacle_stab.wav"
local TENTACLE_DETACH = "gekko/elastic/tentacle_stab.wav"

-- ============================================================
--  ROPE SIMULATION
-- ============================================================
local function RopeNodes_Create(startPos, endPos)
    local nodes = {}
    local segs  = ROPE_NODES - 1
    for i = 0, segs do
        local t   = i / segs
        local pos = LerpVector(t, startPos, endPos)
        nodes[i + 1] = {
            pos  = Vector(pos.x, pos.y, pos.z),
            prev = Vector(pos.x, pos.y, pos.z),
        }
    end
    return nodes
end

local function RopeNodes_Simulate(nodes, anchorA, anchorB, dt, tipNodeIdx)
    local n          = #nodes
    local dtSq       = dt * dt
    local damp       = ROPE_DAMPING
    local freezeFrom = tipNodeIdx or n

    for i = 2, n - 1 do
        if i >= freezeFrom then
            nodes[i].pos  = Vector(anchorB.x, anchorB.y, anchorB.z)
            nodes[i].prev = Vector(anchorB.x, anchorB.y, anchorB.z)
        else
            local nd  = nodes[i]
            local cur = nd.pos
            local prv = nd.prev
            local vx  = (cur.x - prv.x) * damp
            local vy  = (cur.y - prv.y) * damp
            local vz  = (cur.z - prv.z) * damp
            nd.prev = Vector(cur.x, cur.y, cur.z)
            nd.pos  = Vector(
                cur.x + vx + ROPE_GRAVITY.x * dtSq,
                cur.y + vy + ROPE_GRAVITY.y * dtSq,
                cur.z + vz + ROPE_GRAVITY.z * dtSq
            )
        end
    end

    nodes[1].pos  = Vector(anchorA.x, anchorA.y, anchorA.z)
    nodes[1].prev = Vector(anchorA.x, anchorA.y, anchorA.z)
    nodes[n].pos  = Vector(anchorB.x, anchorB.y, anchorB.z)
    nodes[n].prev = Vector(anchorB.x, anchorB.y, anchorB.z)

    local liveSegs = freezeFrom - 1
    if liveSegs < 1 then return end

    local rawDist = anchorA:Distance(anchorB)
    local restLen = (rawDist / (n - 1)) * ROPE_SLACK

    for _ = 1, ROPE_CONSTRAINT do
        for i = 1, liveSegs do
            local a  = nodes[i]
            local b  = nodes[i + 1]
            local dx = b.pos.x - a.pos.x
            local dy = b.pos.y - a.pos.y
            local dz = b.pos.z - a.pos.z
            local d  = math.sqrt(dx*dx + dy*dy + dz*dz)
            if d < 0.001 then continue end
            local diff       = (d - restLen) / d * 0.5
            local cx, cy, cz = dx*diff, dy*diff, dz*diff
            if i ~= 1 then
                a.pos.x = a.pos.x + cx
                a.pos.y = a.pos.y + cy
                a.pos.z = a.pos.z + cz
            end
            if i + 1 <= freezeFrom then
                b.pos.x = b.pos.x - cx
                b.pos.y = b.pos.y - cy
                b.pos.z = b.pos.z - cz
            end
        end
        nodes[1].pos = Vector(anchorA.x, anchorA.y, anchorA.z)
        nodes[n].pos = Vector(anchorB.x, anchorB.y, anchorB.z)
    end
end

-- ============================================================
--  COSINE TIP POSITION
-- ============================================================
local function TipPos_Cosine(t, anchorA, target, right, upVec, elapsed)
    local base = LerpVector(t, anchorA, target)
    local env  = (math.sin(t * math.pi)) ^ 0.7
    local amp  = EXTEND_AMP * env
    local freq  = EXTEND_FREQ_START + (EXTEND_FREQ_END - EXTEND_FREQ_START) * math.abs(t - 0.5) * 2
    local phase = elapsed * freq * math.pi * 2
    local offR = math.cos(phase)              * amp
    local offU = math.sin(phase * 0.7 + 1.1) * amp * 0.65
    return Vector(
        base.x + right.x * offR + upVec.x * offU,
        base.y + right.y * offR + upVec.y * offU,
        base.z + right.z * offR + upVec.z * offU
    )
end

-- ============================================================
--  ATTACH DUST
-- ============================================================
local function SpawnAttachDust(pos)
    local emitter = ParticleEmitter(pos, false)
    if not emitter then return end
    for _ = 1, 18 do
        local p = emitter:Add("particle/smokesprites_000" .. math.random(1, 9), pos)
        if not p then continue end
        local dir = VectorRand(); dir.z = math.abs(dir.z)
        p:SetVelocity(dir * math.Rand(40, 120))
        p:SetLifeTime(0)
        p:SetDieTime(math.Rand(0.35, 0.7))
        p:SetStartAlpha(math.Rand(120, 180))
        p:SetEndAlpha(0)
        p:SetStartSize(math.Rand(4, 9))
        p:SetEndSize(math.Rand(14, 28))
        p:SetColor(200, 190, 170)
        p:SetAirResistance(60)
        p:SetGravity(Vector(0, 0, 18))
        p:SetRoll(math.Rand(0, 360))
        p:SetRollDelta(math.Rand(-0.6, 0.6))
    end
    emitter:Finish()
end

-- ============================================================
--  BLOOD MIST  (direct ParticleEmitter — no util.Effect needed)
--  Used for both break burst and retract trail.
-- ============================================================
local function SpawnBloodMist(pos, norm, count, speedScale)
    local emitter = ParticleEmitter(pos, true)
    if not emitter then return end
    count      = count or 14
    speedScale = speedScale or 1.0
    for _ = 1, count do
        local p = emitter:Add("particle/smokesprites_000" .. math.random(1, 9), pos)
        if not p then continue end
        local vel = norm * math.Rand(40, 90) * speedScale + VectorRand() * (25 * speedScale)
        p:SetVelocity(vel)
        p:SetLifeTime(0)
        p:SetDieTime(math.Rand(0.3, 0.75))
        p:SetStartAlpha(math.Rand(140, 200))
        p:SetEndAlpha(0)
        p:SetStartSize(math.Rand(5, 11))
        p:SetEndSize(math.Rand(20, 45))
        p:SetColor(210, 25, 25)
        p:SetAirResistance(45)
        p:SetGravity(Vector(0, 0, -14))
        p:SetRoll(math.Rand(0, 360))
        p:SetRollDelta(math.Rand(-0.5, 0.5))
    end
    emitter:Finish()
end

-- ============================================================
--  BREAK EFFECTS  (one-shot burst at snap point)
-- ============================================================
local _breakFlashEnd = 0

local function SpawnBreakEffects(pos, enemy)
    local norm = Vector(0, 0, 1)
    if IsValid(enemy) then norm = enemy:GetForward() * -1 end

    -- Blood mist burst — large, obvious, 22 particles
    SpawnBloodMist(pos, norm, 22, 1.4)

    -- gekko_bloodstream effect for the dripping stream trail
    local ed = EffectData()
    ed:SetOrigin(pos)
    ed:SetNormal(norm)
    ed:SetEntity(IsValid(enemy) and enemy or game.GetWorld())
    util.Effect("gekko_bloodstream", ed, true, true)

    -- Orange sparks
    local sparker = ParticleEmitter(pos, true)
    if sparker then
        local right = norm:Cross(Vector(0, 0, 1))
        if right:LengthSqr() < 0.001 then right = norm:Cross(Vector(0, 1, 0)) end
        right:Normalize()
        local up = right:Cross(norm):GetNormalized()
        local sr = math.rad(55)
        for _ = 1, math.random(20, 35) do
            local p = sparker:Add("effects/spark", pos)
            if not p then continue end
            local dir = (norm
                + right * math.sin(math.Rand(-sr, sr))
                + up    * math.sin(math.Rand(-sr, sr))):GetNormalized()
            p:SetVelocity(dir * math.Rand(150, 400))
            p:SetLifeTime(0)
            p:SetDieTime(math.Rand(0.15, 0.45))
            p:SetStartAlpha(255)
            p:SetEndAlpha(0)
            p:SetStartSize(math.Rand(1.2, 3.0))
            p:SetEndSize(0)
            p:SetColor(255, math.random(180, 255), math.random(0, 60))
            p:SetGravity(Vector(0, 0, -300))
            p:SetAirResistance(20)
            p:SetCollide(true)
            p:SetBounce(0.3)
        end
        sparker:Finish()
    end

    for _ = 1, math.random(3, 6) do
        local ox = math.Rand(-30, 30)
        local oy = math.Rand(-30, 30)
        util.Decal("Blood", pos + Vector(ox, oy, 20), pos + Vector(ox, oy, -96))
    end

    local ply = LocalPlayer()
    if IsValid(ply) and ply:GetPos():Distance(pos) < 700 then
        _breakFlashEnd = CurTime() + 0.18
    end
end

hook.Add("HUDPaint", "GekkoElasticBreakFlash", function()
    if CurTime() >= _breakFlashEnd then return end
    local alpha = math.Remap(CurTime(), _breakFlashEnd - 0.18, _breakFlashEnd, 55, 0)
    surface.SetDrawColor(255, 255, 255, math.Clamp(alpha, 0, 55))
    surface.DrawRect(0, 0, ScrW(), ScrH())
end)

-- ============================================================
--  RETRACT TRAIL TICK
--
--  Called every frame during break-retract.
--  Blood mist + spark burst at the exact moving tip position.
--  Throttled by b.trailNextT at TRAIL_INTERVAL seconds.
-- ============================================================
local function EmitRetractTrail(tipPos, towardGekko, now, b)
    if now < b.trailNextT then return end
    b.trailNextT = now + TRAIL_INTERVAL

    local norm = towardGekko:GetNormalized()

    -- Blood mist: small burst, 6 particles per tick to avoid spam
    SpawnBloodMist(tipPos, norm, 6, 0.7)

    -- Spark burst at tip
    local sparker = ParticleEmitter(tipPos, false)
    if sparker then
        for _ = 1, math.random(3, 6) do
            local p = sparker:Add("effects/spark", tipPos)
            if not p then continue end
            local dir = VectorRand():GetNormalized()
            p:SetVelocity(dir * math.Rand(80, 220))
            p:SetLifeTime(0)
            p:SetDieTime(math.Rand(0.07, 0.20))
            p:SetStartAlpha(255)
            p:SetEndAlpha(0)
            p:SetStartSize(math.Rand(0.8, 2.2))
            p:SetEndSize(0)
            p:SetColor(255, math.random(100, 200), 0)
            p:SetGravity(Vector(0, 0, -200))
            p:SetAirResistance(15)
            p:SetCollide(true)
            p:SetBounce(0.2)
        end
        sparker:Finish()
    end
end

-- ============================================================
--  BEGIN RETRACT
-- ============================================================
local function BeginRetract(b, now, isBreak)
    if b.retracting then return end
    b.retracting      = true
    b.breakRetracting = isBreak == true
    b.retractStartT   = now
    b.trailNextT      = now

    if b.extendDone then
        b.retractOrigin = IsValid(b.enemy) and
            (b.enemy:GetPos() + b.endOffset) or b.extendTarget
    else
        local elapsed  = now - b.spawnTime
        local traveled = math.min(elapsed * EXTEND_SPEED, b.extendDist)
        local t        = traveled / b.extendDist
        local anchorA  = IsValid(b.gekko) and
            (b.gekko:GetPos() + b.startOffset) or b.extendTarget
        b.retractOrigin = TipPos_Cosine(
            t, anchorA, b.extendTarget,
            b.extendRight, b.extendUp, elapsed
        )
    end

    local anchorA_now = IsValid(b.gekko) and
        (b.gekko:GetPos() + b.startOffset) or b.extendTarget
    b.retractDist    = math.max(b.retractOrigin:Distance(anchorA_now), 1)
    b.retractElapsed = 0

    if b.loopSnd then b.loopSnd:Stop() b.loopSnd = nil end
end

-- ============================================================
--  FIND BEAM FOR ENEMY
-- ============================================================
local function FindBeamForEnemy(enemy)
    for _, b in ipairs(activeBeams) do
        if b.enemy == enemy then return b end
    end
end

-- ============================================================
--  FIX: force-drop all beams targeting the local player
-- ============================================================
local function DropLocalPlayerBeams()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local now = CurTime()
    for _, b in ipairs(activeBeams) do
        if b.enemy == ply and not b.retracting then
            BeginRetract(b, now, false)
        end
    end
end

hook.Add("InitPostEntity", "GekkoElasticClearOnSpawn", function()
    DropLocalPlayerBeams()
end)

hook.Add("PostEntityCreated", "GekkoElasticRespawnClear", function(ent)
    if not IsValid(ent) then return end
    if not ent:IsPlayer() then return end
    if ent ~= LocalPlayer() then return end
    DropLocalPlayerBeams()
end)

-- ============================================================
--  DRAW HOOK
-- ============================================================
local _lastFrameT = 0

hook.Add("PostDrawOpaqueRenderables", "GekkoElasticBeamDraw", function()
    if #activeBeams == 0 then return end

    local now = CurTime()
    local dt  = math.Clamp(now - _lastFrameT, 0.001, 0.05)
    _lastFrameT = now

    local mat = Material("cable/cable2")
    local i   = 1

    while i <= #activeBeams do
        local b = activeBeams[i]

        if not IsValid(b.gekko) then
            if b.loopSnd then b.loopSnd:Stop() b.loopSnd = nil end
            table.remove(activeBeams, i)
        else
            local anchorA = b.gekko:GetPos() + b.startOffset

            -- ------------------------------------------------
            --  RETRACT PHASE
            -- ------------------------------------------------
            if b.retracting then
                b.retractElapsed = b.retractElapsed + dt

                local traveled = b.retractElapsed * EXTEND_SPEED
                local t        = 1 - math.min(traveled / b.retractDist, 1)

                if t <= 0 then
                    if b.loopSnd then b.loopSnd:Stop() b.loopSnd = nil end
                    table.remove(activeBeams, i)
                else
                    local tipPos = TipPos_Cosine(
                        t, anchorA, b.retractOrigin,
                        b.extendRight, b.extendUp,
                        now - b.spawnTime
                    )

                    if b.breakRetracting then
                        local towardGekko = anchorA - tipPos
                        EmitRetractTrail(tipPos, towardGekko, now, b)
                    end

                    local tipNodeIdx = math.max(2,
                        math.floor(t * (ROPE_NODES - 1)) + 2)

                    local jNode = b.nodes[math.max(1, tipNodeIdx - 1)]
                    if jNode then
                        jNode.pos.x = jNode.pos.x + math.Rand(-EXTEND_JITTER, EXTEND_JITTER)
                        jNode.pos.y = jNode.pos.y + math.Rand(-EXTEND_JITTER, EXTEND_JITTER)
                        jNode.pos.z = jNode.pos.z + math.Rand(-EXTEND_JITTER * 0.5, EXTEND_JITTER * 0.5)
                    end

                    RopeNodes_Simulate(b.nodes, anchorA, tipPos, dt, tipNodeIdx)

                    render.SetMaterial(mat)
                    local drawTo = math.min(tipNodeIdx - 1, ROPE_NODES - 1)
                    for s = 1, drawTo do
                        render.DrawBeam(
                            b.nodes[s].pos,
                            b.nodes[s + 1].pos,
                            b.width, 0, 1, b.color
                        )
                    end
                    i = i + 1
                end

            elseif IsValid(b.enemy) and b.enemy:IsPlayer()
                   and b.enemy == LocalPlayer()
                   and not b.enemy:Alive() then
                BeginRetract(b, now, false)
                i = i + 1

            elseif not IsValid(b.enemy) then
                BeginRetract(b, now, false)
                i = i + 1
            else
                local anchorB = b.enemy:GetPos() + b.endOffset
                local tipPos     = anchorB
                local tipNodeIdx = ROPE_NODES

                if not b.extendDone then
                    local elapsed  = now - b.spawnTime
                    local traveled = elapsed * EXTEND_SPEED

                    if traveled >= b.extendDist then
                        b.extendDone = true
                        SpawnAttachDust(anchorB)
                    else
                        local t = traveled / b.extendDist
                        tipPos = TipPos_Cosine(
                            t, anchorA, b.extendTarget,
                            b.extendRight, b.extendUp, elapsed
                        )
                        tipNodeIdx = math.max(2,
                            math.floor(t * (ROPE_NODES - 1)) + 2)

                        local jNode = b.nodes[math.max(1, tipNodeIdx - 1)]
                        if jNode then
                            jNode.pos.x = jNode.pos.x + math.Rand(-EXTEND_JITTER, EXTEND_JITTER)
                            jNode.pos.y = jNode.pos.y + math.Rand(-EXTEND_JITTER, EXTEND_JITTER)
                            jNode.pos.z = jNode.pos.z + math.Rand(-EXTEND_JITTER * 0.5, EXTEND_JITTER * 0.5)
                        end
                    end
                end

                RopeNodes_Simulate(b.nodes, anchorA, tipPos, dt, tipNodeIdx)

                render.SetMaterial(mat)
                local drawTo = b.extendDone and (ROPE_NODES - 1) or (tipNodeIdx - 1)
                drawTo = math.min(drawTo, ROPE_NODES - 1)
                for s = 1, drawTo do
                    render.DrawBeam(
                        b.nodes[s].pos,
                        b.nodes[s + 1].pos,
                        b.width, 0, 1, b.color
                    )
                end
                i = i + 1
            end
        end
    end
end)

-- ============================================================
--  NET: PRE-FIRE SHOOT SOUND
-- ============================================================
net.Receive("GekkoElasticShootSound", function()
    local gekko = net.ReadEntity()
    local snd   = SHOOT_SOUNDS[math.random(#SHOOT_SOUNDS)]
    local pos   = IsValid(gekko) and gekko:GetPos() or Vector(0, 0, 0)
    sound.Play(snd, pos, 90, 100)
end)

-- ============================================================
--  NET: BEAM ATTACH
-- ============================================================
net.Receive("GekkoElasticRope", function()
    local gekko     = net.ReadEntity()
    local enemy     = net.ReadEntity()
    local snapDelay = net.ReadFloat()
    local width     = net.ReadUInt(8)
    local col_r     = net.ReadUInt(8)
    local col_g     = net.ReadUInt(8)
    local col_b     = net.ReadUInt(8)

    if not IsValid(gekko) or not IsValid(enemy) then return end

    local ply = LocalPlayer()
    if IsValid(ply) and enemy == ply and not ply:Alive() then return end

    local startOffset = Vector(0, 0, GEKKO_ORIGIN_Z)
    local endOffset   = Vector(0, 0, 40)
    local anchorA     = gekko:GetPos() + startOffset
    local anchorB     = enemy:GetPos() + endOffset
    local dist        = anchorA:Distance(anchorB)

    local fwd   = (anchorB - anchorA):GetNormalized()
    local right = fwd:Cross(Vector(0, 0, 1))
    if right:LengthSqr() < 0.001 then right = fwd:Cross(Vector(1, 0, 0)) end
    right:Normalize()
    local upVec = right:Cross(fwd):GetNormalized()

    local rollAng = math.Rand(0, math.pi * 2)
    local rightR  = right * math.cos(rollAng) + upVec * math.sin(rollAng)
    local upR     = right * (-math.sin(rollAng)) + upVec * math.cos(rollAng)

    local loopSnd = CreateSound(gekko, TENTACLE_LOOP)
    if loopSnd then loopSnd:SetSoundLevel(100) loopSnd:Play() end

    table.insert(activeBeams, {
        gekko           = gekko,
        enemy           = enemy,
        startOffset     = startOffset,
        endOffset       = endOffset,
        width           = math.max(width, 3),
        color           = Color(col_r, col_g, col_b, 255),
        removeAt        = CurTime() + snapDelay,
        loopSnd         = loopSnd,
        nodes           = RopeNodes_Create(anchorA, anchorB),
        extendDone      = false,
        spawnTime       = CurTime(),
        extendDist      = math.max(dist, 1),
        extendTarget    = Vector(anchorB.x, anchorB.y, anchorB.z),
        extendRight     = rightR,
        extendUp        = upR,
        retracting      = false,
        breakRetracting = false,
        retractStartT   = 0,
        retractOrigin   = Vector(0,0,0),
        retractDist     = 1,
        retractElapsed  = 0,
        trailNextT      = 0,
    })

    if IsValid(ply) then
        local d = ply:GetPos():Distance(enemy:GetPos())
        if d < 600 then
            util.ScreenShake(enemy:GetPos(), 8 * (1 - d / 600), 18, 0.2, 600)
        end
    end
end)

-- ============================================================
--  NET: NATURAL RETRACT
-- ============================================================
net.Receive("GekkoElasticRetract", function()
    local enemy = net.ReadEntity()
    if not IsValid(enemy) then return end
    local b = FindBeamForEnemy(enemy)
    if not b then return end
    sound.Play(TENTACLE_DETACH, IsValid(b.enemy) and b.enemy:GetPos() or Vector(0,0,0), 80, 100)
    BeginRetract(b, CurTime(), false)
end)

-- ============================================================
--  NET: CABLE BREAK  (key-smash / death)
-- ============================================================
net.Receive("GekkoElasticBreak", function()
    local enemy    = net.ReadEntity()
    local breakPos = net.ReadVector()

    local b
    for _, beam in ipairs(activeBeams) do
        if beam.enemy == enemy then b = beam break end
    end

    if b then
        SpawnBreakEffects(breakPos, enemy)
        sound.Play(TENTACLE_STAB, breakPos, 85, 100)
        BeginRetract(b, CurTime(), true)
    end
end)
