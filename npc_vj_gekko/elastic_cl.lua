-- ============================================================
--  ELASTIC SLING SYSTEM  (client-side)
--
--  Receives net "GekkoElasticRope" from elastic_system.lua.
--  Draws a taut cable between Gekko torso and the target using
--  the client-only  CreateClientsideRope()  API — the same
--  function the Rope Tool uses on the client.
--
--  The rope is removed after snapDelay seconds.
-- ============================================================

-- ============================================================
--  ROPE POOL
-- ============================================================
local activeRopes = {}

hook.Add("Think", "GekkoElasticRopeCleanup", function()
    local now = CurTime()
    local i   = 1
    while i <= #activeRopes do
        local e = activeRopes[i]
        if now >= e.removeAt then
            if IsValid(e.rope) then e.rope:Remove() end
            table.remove(activeRopes, i)
        else
            i = i + 1
        end
    end
end)

-- ============================================================
--  SOUNDS
-- ============================================================
local SNAP_SOUNDS = {
    "physics/metal/metal_box_impact_hard1.wav",
    "physics/metal/metal_box_impact_hard2.wav",
}

-- ============================================================
--  NET RECEIVER
-- ============================================================
net.Receive("GekkoElasticRope", function()
    local gekko     = net.ReadEntity()
    local enemy     = net.ReadEntity()
    local snapDelay = net.ReadFloat()
    local width     = net.ReadUInt(8)
    local r         = net.ReadUInt(8)
    local g         = net.ReadUInt(8)
    local b         = net.ReadUInt(8)

    if not IsValid(gekko) or not IsValid(enemy) then return end

    local ropeLen = math.max(1, math.floor(
        gekko:GetPos():Distance(enemy:GetPos())))

    -- CreateClientsideRope is the client-only rope API.
    -- Signature:
    --   CreateClientsideRope(startPos, startEnt, endEnt,
    --                        startBone, endBone,
    --                        startOffset, endOffset,
    --                        ropeLen, slack, width,
    --                        rigid, material)
    local rope = CreateClientsideRope(
        gekko:GetPos() + Vector(0, 0, 80),  -- startPos (initial)
        gekko,                              -- startEnt
        enemy,                              -- endEnt
        0,                                  -- startBone (root)
        0,                                  -- endBone   (root)
        Vector(0, 0, 80),                   -- startOffset (torso height)
        Vector(0, 0, 40),                   -- endOffset   (centre mass)
        ropeLen,                            -- rope length
        0,                                  -- slack = 0 → taut
        width,                              -- pixel width
        false,                              -- rigid
        "cable/cable2"                      -- material
    )

    if IsValid(rope) then
        rope:SetColor(Color(r, g, b, 255))
        table.insert(activeRopes, {
            rope     = rope,
            removeAt = CurTime() + snapDelay,
        })
    end

    -- twang sound
    sound.Play(
        SNAP_SOUNDS[math.random(#SNAP_SOUNDS)],
        enemy:GetPos(), 85, math.random(55, 75)
    )

    -- screen shake for nearby local player
    local ply = LocalPlayer()
    if IsValid(ply) then
        local d = ply:GetPos():Distance(enemy:GetPos())
        if d < 600 then
            util.ScreenShake(enemy:GetPos(),
                8 * (1 - d / 600), 18, 0.2, 600)
        end
    end
end)
