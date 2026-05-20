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
--    tentaclepull_1 : looped via CreateSound for the beam's full lifetime
--    tentacle_stab  : played at the target's position on cable break
--
--  Effects:
--    Dust emitter  : spawned at the target connection point on attach
--    gekko_bloodstream : spawned at break point on cable snap
--
--  SERVER SIDE IS COMPLETELY UNCHANGED.
-- ============================================================

-- ============================================================
--  CONFIG
-- ============================================================
local ROPE_NODES       = 12      -- number of simulation nodes (inc. endpoints)
local ROPE_GRAVITY     = Vector(0, 0, -380)  -- gravity applied to inner nodes
local ROPE_DAMPING     = 0.88    -- velocity retention per frame (0-1); lower = more drag
local ROPE_CONSTRAINT  = 6       -- distance-constraint iterations per frame
local ROPE_SLACK       = 1.08    -- rest length = (dist / segments) * SLACK; > 1 = sag

-- ============================================================
--  ACTIVE BEAM TABLE
--  Each entry: { gekko, enemy, startOffset, endOffset,
--               width, color, removeAt, loopSnd,
--               nodes, prevNodes }       <- new simulation fields
-- ============================================================
local activeBeams = {}

-- Must match elastic_system.lua
local GEKKO_ORIGIN_Z = 380

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
--  ROPE SIMULATION HELPERS
-- ============================================================

-- Build a fresh node chain between two world positions.
-- Each node: { pos = Vector, prev = Vector }
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

-- Simulate one frame of verlet physics on the node chain.
-- Endpoint nodes (1 and N) are pinned to anchorA / anchorB.
local function RopeNodes_Simulate(nodes, anchorA, anchorB, dt)
    local n       = #nodes
    local dtSq    = dt * dt
    local gravity = ROPE_GRAVITY
    local damp    = ROPE_DAMPING

    -- 1. Verlet integrate inner nodes
    for i = 2, n - 1 do
        local nd   = nodes[i]
        local cur  = nd.pos
        local prev = nd.prev
        -- velocity = (cur - prev), damped
        local vx = (cur.x - prev.x) * damp
        local vy = (cur.y - prev.y) * damp
        local vz = (cur.z - prev.z) * damp
        -- new position
        local nx = cur.x + vx + gravity.x * dtSq
        local ny = cur.y + vy + gravity.y * dtSq
        local nz = cur.z + vz + gravity.z * dtSq
        nd.prev  = Vector(cur.x, cur.y, cur.z)
        nd.pos   = Vector(nx, ny, nz)
    end

    -- 2. Pin endpoints
    nodes[1].pos  = Vector(anchorA.x, anchorA.y, anchorA.z)
    nodes[1].prev = Vector(anchorA.x, anchorA.y, anchorA.z)
    nodes[n].pos  = Vector(anchorB.x, anchorB.y, anchorB.z)
    nodes[n].prev = Vector(anchorB.x, anchorB.y, anchorB.z)

    -- 3. Distance constraints (multiple iterations = stiffer)
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
            local diff = (d - restLen) / d * 0.5
            local cx   = dx * diff
            local cy   = dy * diff
            local cz   = dz * diff
            -- endpoint nodes are pinned; only move inner nodes
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
        -- re-pin endpoints after each constraint pass
        nodes[1].pos  = Vector(anchorA.x, anchorA.y, anchorA.z)
        nodes[n].pos  = Vector(anchorB.x, anchorB.y, anchorB.z)
    end
end

-- ============================================================
--  DUST EFFECT
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
--  BLOOD EFFECT
-- ============================================================
local function SpawnBreakBlood(pos, enemy)
    local ed = EffectData()
    ed:SetOrigin(pos)
    ed:SetNormal(Vector(0, 0, 1))
    if IsValid(enemy) then ed:SetEntity(enemy) end
    util.Effect("gekko_bloodstream", ed, true, true)
end

-- ============================================================
--  REMOVE ALL BEAMS FOR A GIVEN ENEMY
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
--  DRAW HOOK  –  simulated rope
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
            local anchorB = b.enemy:GetPos() + b.endOffset

            -- Simulate the rope nodes this frame
            RopeNodes_Simulate(b.nodes, anchorA, anchorB, dt)

            -- Draw segment-by-segment
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
--  NET: BEAM ATTACH  (runs after pre-fire delay)
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

    local attachPos = enemy:GetPos() + Vector(0, 0, 40)
    SpawnAttachDust(attachPos)

    local loopSnd = CreateSound(gekko, TENTACLE_LOOP)
    if loopSnd then
        loopSnd:SetSoundLevel(75)
        loopSnd:Play()
    end

    local startOffset = Vector(0, 0, GEKKO_ORIGIN_Z)
    local endOffset   = Vector(0, 0, 40)
    local anchorA     = gekko:GetPos() + startOffset
    local anchorB     = enemy:GetPos() + endOffset

    -- Build initial straight-line node chain; physics will droop it immediately
    local nodes = RopeNodes_Create(anchorA, anchorB)

    local entry = {
        gekko       = gekko,
        enemy       = enemy,
        startOffset = startOffset,
        endOffset   = endOffset,
        width       = math.max(width, 3),   -- min width so rope is visible
        color       = Color(col_r, col_g, col_b, 255),
        removeAt    = CurTime() + snapDelay,
        loopSnd     = loopSnd,
        nodes       = nodes,
    }
    table.insert(activeBeams, entry)

    -- Screen shake
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
    SpawnBreakBlood(breakPos, enemy)
    sound.Play(TENTACLE_STAB, breakPos, 85, 100)
end)
