-- ============================================================
--  ELASTIC SLING SYSTEM  (client-side)
--
--  Receives net "GekkoElasticRope" from elastic_system.lua.
--  Draws a rope between Gekko torso and the target using
--  Garry's Mod's  ents.Create("keyframe_rope")  — the same
--  entity the Rope Tool and Winch Tool create.
--
--  The rope is removed after snapDelay seconds.
-- ============================================================

-- ============================================================
--  ROPE POOL  — track active ropes and auto-remove them
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

    -- ---- rope ----
    -- keyframe_rope is the entity both the Rope Tool and Winch Tool
    -- spawn.  We create it client-side only (no physics constraint),
    -- purely as a visual cable between Gekko and the target.
    local rope = ents.Create("keyframe_rope")
    if not IsValid(rope) then return end

    local ropeLen = math.max(1, math.floor(
        gekko:GetPos():Distance(enemy:GetPos())))

    rope:SetKeyValue("RopeLength",  tostring(ropeLen))
    rope:SetKeyValue("Slack",       "0")
    rope:SetKeyValue("Width",       tostring(width))
    rope:SetKeyValue("TextureScale","1")
    rope:SetKeyValue("NextKey",     "")
    rope:SetKeyValue("Type",        "2")   -- TYPE_PLASTIC (taut)
    rope:SetKeyValue("CollideWith", "0")
    rope:SetKeyValue("Dangling",    "0")
    rope:SetKeyValue("material",    "cable/cable2")

    rope:Spawn()
    rope:Activate()

    -- attach endpoints
    rope:SetEntity("StartEntity",  gekko)
    rope:SetEntity("EndEntity",    enemy)
    rope:SetPos(gekko:GetPos() + Vector(0, 0, 80))
    rope:SetColor(Color(r, g, b, 255))

    -- fire the rope inputs so the endpoints lock in
    rope:Fire("SetStartEntity",   tostring(gekko:EntIndex()),  0)
    rope:Fire("SetEndEntity",     tostring(enemy:EntIndex()),  0)

    table.insert(activeRopes, { rope = rope, removeAt = CurTime() + snapDelay })

    -- ---- twang sound ----
    sound.Play(
        SNAP_SOUNDS[math.random(#SNAP_SOUNDS)],
        enemy:GetPos(), 85, math.random(55, 75)
    )

    -- ---- screen shake for nearby local player ----
    local ply = LocalPlayer()
    if IsValid(ply) then
        local d = ply:GetPos():Distance(enemy:GetPos())
        if d < 600 then
            util.ScreenShake(enemy:GetPos(),
                8 * (1 - d / 600), 18, 0.2, 600)
        end
    end
end)
