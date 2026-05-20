-- ============================================================
--  ELASTIC SLING SYSTEM  (client-side)
--
--  Beam drawn as a SIMULATED ROPE each frame:
--    - N nodes with verlet integration (gravity + damping)
--    - Endpoint nodes pinned to gekko / enemy each frame
--    - render.DrawBeam called per segment between neighbours
--    - Rope wiggles, sags, and swings naturally
--
--  Sounds:
--    shoot_1..5     : played immediately on GekkoElasticShootSound
--    tentaclepull_1 : looped via CreateSound for beam's full lifetime
--    tentacle_stab  : played at break position on cable snap
--
--  Effects:
--    Dust emitter      : spawned at target attach point on beam land
--    Break blood mist  : GUARANTEED heavy mist on cable snap
--    Break sparks      : GUARANTEED spark burst on cable snap
--    Break decals      : blood splats on nearby surfaces
--    Screen flash      : white overlay flash on cable snap (nearby only)
--
--  SERVER SIDE IS COMPLETELY UNCHANGED.
-- ============================================================

-- ============================================================
--  CONFIG
-- ============================================================
local ROPE_NODES      = 12
local ROPE_GRAVITY    = Vector(0, 0, -380)
local ROPE_DAMPING    = 0.88
local ROPE_CONSTRAINT = 6
local ROPE_SLACK      = 1.08

-- ============================================================
--  ACTIVE BEAM TABLE
-- ============================================================
local activeBeams = {}

-- Mid-body visual origin. Intentionally 180, NOT the server physics
-- anchor (380). 180 places the rope at the Gekko's torso / bushmaster
-- muzzle height as it appeared before the rope rewrite.
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
local TENTACLE_LOOP = "gekko/elastic/tentaclepull_1.wav"
local TENTACLE_STAB = "gekko/elastic/tentacle_stab.wav"

-- ============================================================
--  ROPE SIMULATION
-- ============================================================
local function RopeNodes_Create(startPos, endPos)
    local nodes = {}
    local segs  = ROPE_NODES - 1
    for i = 0, segs do
        local t   = i / segs
        local pos = LerpVector(t, startPos, endPos)
        nodes[i + 1] = { pos = pos, prev = Vector(pos.x, pos.y, pos.z) }
    end
    return nodes
end

local function RopeNodes_Simulate(nodes, anchorA, anchorB, dt)
    local n       = #nodes
    local dtSq    = dt * dt
    local gravity = ROPE_GRAVITY
    local damp    = ROPE_DAMPING

    -- 1. Verlet integrate inner nodes
    for i = 2, n - 1 do
        local nd  = nodes[i]
        local cur = nd.pos
        local prv = nd.prev
        local vx  = (cur.x - prv.x) * damp
        local vy  = (cur.y - prv.y) * damp
        local vz  = (cur.z - prv.z) * damp
        nd.prev = Vector(cur.x, cur.y, cur.z)
        nd.pos  = Vector(
            cur.x + vx + gravity.x * dtSq,
            cur.y + vy + gravity.y * dtSq,
            cur.z + vz + gravity.z * dtSq
        )
    end

    -- 2. Pin endpoints
    nodes[1].pos  = Vector(anchorA.x, anchorA.y, anchorA.z)
    nodes[1].prev = Vector(anchorA.x, anchorA.y, anchorA.z)
    nodes[n].pos  = Vector(anchorB.x, anchorB.y, anchorB.z)
    nodes[n].prev = Vector(anchorB.x, anchorB.y, anchorB.z)

    -- 3. Distance constraints
    local segs    = n - 1
    local rawDist = anchorA:Distance(anchorB)
    local restLen = (rawDist / segs) * ROPE_SLACK

    for _ = 1, ROPE_CONSTRAINT do
        for i = 1, segs do
            local a  = nodes[i]
            local b  = nodes[i + 1]
            local dx = b.pos.x - a.pos.x
            local dy = b.pos.y - a.pos.y
            local dz = b.pos.z - a.pos.z
            local d  = math.sqrt(dx*dx + dy*dy + dz*dz)
            if d < 0.001 then continue end
            local diff     = (d - restLen) / d * 0.5
            local cx, cy, cz = dx*diff, dy*diff, dz*diff
            if i ~= 1 then
                a.pos.x = a.pos.x + cx
                a.pos.y = a.pos.y + cy
                a.pos.z = a.pos.z + cz
            end
            if i + 1 ~= n then
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
--  ATTACH DUST  (on beam landing)
-- ============================================================
local function SpawnAttachDust(pos)
    local emitter = ParticleEmitter(pos, false)
    if not emitter then return end
    for _ = 1, 18 do
        local p = emitter:Add("particle/smokesprites_000" .. math.random(1, 9), pos)
        if not p then continue end
        local dir = VectorRand()
        dir.z = math.abs(dir.z)
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
--  BREAK EFFECTS  (all GUARANTEED - no probability rolls)
--
--  Called directly instead of util.Effect("gekko_bloodstream")
--  because that effect has internal 80%/23%/23% probability
--  rolls that silently skip the visuals most of the time.
-- ============================================================
local _breakFlashEnd = 0

local function SpawnBreakEffects(pos, enemy)
    local norm = Vector(0, 0, 1)
    if IsValid(enemy) then
        norm = enemy:GetForward() * -1
    end

    -- Blood mist (heavy, 25 particles)
    local emitter = ParticleEmitter(pos, true)
    if emitter then
        for _ = 1, 25 do
            local p = emitter:Add("particle/smokesprites_000" .. math.random(1, 9), pos)
            if not p then continue end
            local vel = norm * math.Rand(40, 80) + VectorRand() * 24
            p:SetVelocity(vel)
            p:SetLifeTime(0)
            p:SetDieTime(math.Rand(0.8, 1.8))
            p:SetStartAlpha(math.Rand(65, 90))
            p:SetEndAlpha(0)
            p:SetStartSize(math.Rand(8, 14))
            p:SetEndSize(math.Rand(30, 55))
            p:SetColor(210, 30, 30)
            p:SetAirResistance(40)
            p:SetGravity(Vector(0, 0, -12))
            p:SetRoll(math.Rand(0, 360))
            p:SetRollDelta(math.Rand(-0.4, 0.4))
        end
        emitter:Finish()
    end

    -- Sparks (20-35 particles)
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

    -- Blood decals on nearby surfaces
    for _ = 1, math.random(3, 6) do
        local ox = math.Rand(-30, 30)
        local oy = math.Rand(-30, 30)
        util.Decal("Blood",
            pos + Vector(ox, oy,  20),
            pos + Vector(ox, oy, -96)
        )
    end

    -- Screen flash (only for nearby local player)
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
--  REMOVE BEAMS FOR ENEMY
-- ============================================================
local function RemoveBeamsForEnemy(enemy)
    local i = 1
    while i <= #activeBeams do
        local b = activeBeams[i]
        if b.enemy == enemy then
            if b.loopSnd then b.loopSnd:Stop() b.loopSnd = nil end
            table.remove(activeBeams, i)
        else
            i = i + 1
        end
    end
end

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

        if now >= b.removeAt
        or not IsValid(b.gekko)
        or not IsValid(b.enemy) then
            if b.loopSnd then b.loopSnd:Stop() b.loopSnd = nil end
            table.remove(activeBeams, i)
        else
            local anchorA = b.gekko:GetPos() + b.startOffset
            local anchorB = b.enemy:GetPos()  + b.endOffset

            RopeNodes_Simulate(b.nodes, anchorA, anchorB, dt)

            render.SetMaterial(mat)
            local nodes = b.nodes
            for s = 1, #nodes - 1 do
                render.DrawBeam(
                    nodes[s].pos,
                    nodes[s + 1].pos,
                    b.width,
                    0, 1,
                    b.color
                )
            end

            i = i + 1
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

    SpawnAttachDust(enemy:GetPos() + Vector(0, 0, 40))

    local loopSnd = CreateSound(gekko, TENTACLE_LOOP)
    if loopSnd then
        loopSnd:SetSoundLevel(75)
        loopSnd:Play()
    end

    local startOffset = Vector(0, 0, GEKKO_ORIGIN_Z)
    local endOffset   = Vector(0, 0, 40)
    local anchorA     = gekko:GetPos() + startOffset
    local anchorB     = enemy:GetPos() + endOffset

    table.insert(activeBeams, {
        gekko       = gekko,
        enemy       = enemy,
        startOffset = startOffset,
        endOffset   = endOffset,
        width       = math.max(width, 3),
        color       = Color(col_r, col_g, col_b, 255),
        removeAt    = CurTime() + snapDelay,
        loopSnd     = loopSnd,
        nodes       = RopeNodes_Create(anchorA, anchorB),
    })

    local ply = LocalPlayer()
    if IsValid(ply) then
        local d = ply:GetPos():Distance(enemy:GetPos())
        if d < 600 then
            util.ScreenShake(enemy:GetPos(), 8 * (1 - d / 600), 18, 0.2, 600)
        end
    end
end)

-- ============================================================
--  NET: CABLE BREAK
-- ============================================================
net.Receive("GekkoElasticBreak", function()
    local enemy    = net.ReadEntity()
    local breakPos = net.ReadVector()

    if not IsValid(enemy) then return end

    RemoveBeamsForEnemy(enemy)
    SpawnBreakEffects(breakPos, enemy)
    sound.Play(TENTACLE_STAB, breakPos, 85, 100)
end)
