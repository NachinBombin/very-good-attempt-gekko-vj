-- ============================================================
--  ELASTIC SLING SYSTEM  (client-side)
--  Receives GekkoElasticRope, draws a rope between Gekko and
--  the target using Garry's Mod's built-in  CreateRope()  API
--  (the same backend the Rope tool / Winch tool use).
--
--  The rope is elastic-styled: short natural length forces it
--  to appear taut and vibrate.  It is removed after snapDelay.
-- ============================================================

-- ============================================================
--  HELPERS
-- ============================================================
local activeRopes = {}   -- { rope, removeAt }

local function RemoveExpiredRopes()
    local now = CurTime()
    local i   = 1
    while i <= #activeRopes do
        local entry = activeRopes[i]
        if now >= entry.removeAt then
            if IsValid(entry.rope) then entry.rope:Remove() end
            table.remove(activeRopes, i)
        else
            i = i + 1
        end
    end
end

hook.Add("Think", "GekkoElasticRopeCleanup", RemoveExpiredRopes)

-- ============================================================
--  SOUND FX  (elastic twang)
-- ============================================================
local SNAP_SOUNDS = {
    "physics/metal/metal_box_impact_hard1.wav",
    "physics/metal/metal_box_impact_hard2.wav",
}

-- ============================================================
--  NET RECEIVER
-- ============================================================
net.Receive("GekkoElasticRope", function()
    local gekko      = net.ReadEntity()
    local enemy      = net.ReadEntity()
    local snapDelay  = net.ReadFloat()
    local ropeWidth  = net.ReadUInt(8)
    local ropeR      = net.ReadUInt(8)
    local ropeG      = net.ReadUInt(8)
    local ropeB      = net.ReadUInt(8)

    if not IsValid(gekko) or not IsValid(enemy) then return end

    -- ---- create rope ----
    --  constraint.ElasticAttachments uses phys_spring internally;
    --  for pure visuals we use  CreateRope()  which is the same
    --  function the Rope and Winch tools call.
    --
    --  Signature:
    --    CreateRope(pos, ent1, ent2, bone1, bone2,
    --               keyValues, material, width, color)
    --
    --  We attach to the world at the Gekko centre and to the
    --  enemy entity.  A near-zero natural length makes it look
    --  snapped taut.

    local startPos = gekko:GetPos() + Vector(0, 0, 80)

    -- Rope keyvalues: elastic / cable material, tight natural length
    local kv = {
        ["MoveSpeed"]      = 0,
        ["RopeLength"]     = math.floor(gekko:GetPos():Distance(enemy:GetPos())),
        ["Slack"]          = 0,
        ["Type"]           = 2,   -- TYPE_ELASTIC
        ["Dangling"]       = 0,
    }

    local rope = constraint.CreateRope(
        startPos,
        gekko,
        enemy,
        0,       -- bone1 (root)
        0,       -- bone2 (root)
        math.floor(gekko:GetPos():Distance(enemy:GetPos())),  -- natural length
        0,       -- slack
        ropeWidth,
        false,   -- rigid
        "cable/cable2"
    )

    if IsValid(rope) then
        rope:SetColor(Color(ropeR, ropeG, ropeB, 255))

        table.insert(activeRopes, {
            rope     = rope,
            removeAt = CurTime() + snapDelay,
        })
    end

    -- ---- twang sound at enemy position ----
    sound.Play(
        SNAP_SOUNDS[math.random(#SNAP_SOUNDS)],
        enemy:GetPos(), 85, math.random(55, 75)
    )

    -- ---- small screen shake for local player if nearby ----
    local ply = LocalPlayer()
    if IsValid(ply) then
        local d = ply:GetPos():Distance(enemy:GetPos())
        if d < 600 then
            local alpha = 1 - (d / 600)
            util.ScreenShake(enemy:GetPos(), 8 * alpha, 18, 0.2, 600)
        end
    end
end)
