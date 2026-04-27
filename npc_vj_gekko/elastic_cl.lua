-- ============================================================
--  ELASTIC SLING SYSTEM  (client-side)
--
--  There is no client-side rope entity API in GMod.
--  We draw the cable manually each frame using render.DrawBeam
--  inside PostDrawOpaqueRenderables, which is the correct hook
--  for world-space 3D lines.
--
--  The beam is removed after snapDelay seconds.
-- ============================================================

-- ============================================================
--  ACTIVE BEAM TABLE
--  Each entry: { gekko, enemy, startOffset, endOffset,
--               width, color, removeAt }
-- ============================================================
local activeBeams = {}

-- ============================================================
--  DRAW HOOK
-- ============================================================
hook.Add("PostDrawOpaqueRenderables", "GekkoElasticBeamDraw", function()
    if #activeBeams == 0 then return end

    local now    = CurTime()
    local mat    = Material("cable/cable2")
    local i      = 1

    while i <= #activeBeams do
        local b = activeBeams[i]

        if now >= b.removeAt
        or not IsValid(b.gekko)
        or not IsValid(b.enemy) then
            table.remove(activeBeams, i)
        else
            local startPos = b.gekko:GetPos() + b.startOffset
            local endPos   = b.enemy:GetPos() + b.endOffset

            render.SetMaterial(mat)
            render.DrawBeam(
                startPos,
                endPos,
                b.width,   -- width in world units
                0, 1,      -- texture start / end
                b.color
            )
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

    table.insert(activeBeams, {
        gekko       = gekko,
        enemy       = enemy,
        startOffset = Vector(0, 0, 80),
        endOffset   = Vector(0, 0, 40),
        width       = width,
        color       = Color(r, g, b, 255),
        removeAt    = CurTime() + snapDelay,
    })

    -- twang sound
    sound.Play(
        SNAP_SOUNDS[math.random(#SNAP_SOUNDS)],
        enemy:GetPos(), 85, math.random(55, 75)
    )

    -- screen shake
    local ply = LocalPlayer()
    if IsValid(ply) then
        local d = ply:GetPos():Distance(enemy:GetPos())
        if d < 600 then
            util.ScreenShake(enemy:GetPos(),
                8 * (1 - d / 600), 18, 0.2, 600)
        end
    end
end)