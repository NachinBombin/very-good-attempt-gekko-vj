-- ============================================================
--  ELASTIC SLING SYSTEM  (client-side)
--
--  Beam drawn manually each frame via render.DrawBeam inside
--  PostDrawOpaqueRenderables.
--
--  Sounds:
--    shoot_1..5  : played immediately on GekkoElasticShootSound
--                  (0.9s before beam/pull exists)
--    tentaclepull_1 : looped for the beam's full lifetime
-- ============================================================

-- ============================================================
--  ACTIVE BEAM TABLE
--  Each entry: { gekko, enemy, startOffset, endOffset,
--               width, color, removeAt, loopChannel }
-- ============================================================
local activeBeams = {}

-- The Gekko-side origin Z — must match elastic_system.lua GEKKO_ORIGIN_Z
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

-- ============================================================
--  DRAW HOOK
-- ============================================================
hook.Add("PostDrawOpaqueRenderables", "GekkoElasticBeamDraw", function()
    if #activeBeams == 0 then return end

    local now = CurTime()
    local mat = Material("cable/cable2")
    local i   = 1

    while i <= #activeBeams do
        local b = activeBeams[i]

        if now >= b.removeAt
        or not IsValid(b.gekko)
        or not IsValid(b.enemy) then
            -- stop the loop sound
            if b.loopChannel and IsValid(b.loopChannel) then
                b.loopChannel:Stop()
            end
            table.remove(activeBeams, i)
        else
            local startPos = b.gekko:GetPos() + b.startOffset
            local endPos   = b.enemy:GetPos() + b.endOffset

            render.SetMaterial(mat)
            render.DrawBeam(
                startPos,
                endPos,
                b.width,
                0, 1,
                b.color
            )
            i = i + 1
        end
    end
end)

-- ============================================================
--  PRE-FIRE SHOOT SOUND  (arrives 0.9s before beam)
-- ============================================================
net.Receive("GekkoElasticShootSound", function()
    local gekko = net.ReadEntity()
    local snd   = SHOOT_SOUNDS[math.random(#SHOOT_SOUNDS)]
    local pos   = IsValid(gekko) and gekko:GetPos() or Vector(0,0,0)
    sound.Play(snd, pos, 90, 100)
end)

-- ============================================================
--  BEAM + TENTACLE LOOP  (arrives after pre-fire delay)
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

    -- start looping tentaclepull_1 for the beam's lifetime
    local loopChan = nil
    sound.PlayURL(
        "sound/" .. TENTACLE_LOOP,
        "3d loop",
        function(chan)
            if not chan then return end
            loopChan = chan
            chan:SetPos(gekko:GetPos())
            chan:Play()
        end
    )

    -- register beam (loopChannel set after async callback, wrapped via closure)
    local entry = {
        gekko       = gekko,
        enemy       = enemy,
        startOffset = Vector(0, 0, GEKKO_ORIGIN_Z),
        endOffset   = Vector(0, 0, 40),
        width       = width,
        color       = Color(r, g, b, 255),
        removeAt    = CurTime() + snapDelay,
        loopChannel = nil,
    }
    table.insert(activeBeams, entry)

    -- wire channel into entry once async resolves
    timer.Simple(0, function()
        if loopChan then
            entry.loopChannel = loopChan
        end
    end)

    -- screen shake on beam arrival
    local ply = LocalPlayer()
    if IsValid(ply) then
        local d = ply:GetPos():Distance(enemy:GetPos())
        if d < 600 then
            util.ScreenShake(enemy:GetPos(),
                8 * (1 - d / 600), 18, 0.2, 600)
        end
    end
end)
