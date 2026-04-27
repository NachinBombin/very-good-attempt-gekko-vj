-- ============================================================
--  ELASTIC SLING SYSTEM  (client-side)
--
--  Beam drawn manually each frame via render.DrawBeam inside
--  PostDrawOpaqueRenderables.
--
--  Sounds:
--    shoot_1..5     : played immediately on GekkoElasticShootSound
--                     (0.9s before beam/pull exists)
--    tentaclepull_1 : looped via CreateSound for the beam's full lifetime
-- ============================================================

-- ============================================================
--  ACTIVE BEAM TABLE
--  Each entry: { gekko, enemy, startOffset, endOffset,
--               width, color, removeAt, loopSnd }
-- ============================================================
local activeBeams = {}

-- Must match elastic_system.lua GEKKO_ORIGIN_Z
local GEKKO_ORIGIN_Z = 180

-- ============================================================
--  SOUNDS
--  GMod sound.Play / CreateSound paths are relative to
--  the game's sound/ folder, so NO "sound/" prefix.
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
            -- stop and destroy the loop sound
            if b.loopSnd then
                b.loopSnd:Stop()
                b.loopSnd = nil
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
    local pos   = IsValid(gekko) and gekko:GetPos() or Vector(0, 0, 0)
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
    local b_col     = net.ReadUInt(8)

    if not IsValid(gekko) or not IsValid(enemy) then return end

    -- CreateSound attaches a looping sound to an entity.
    -- The sound file must have a looping cue point, OR we rely on
    -- the "loop" flag already baked into the .wav.
    -- CreateSound is client-only and perfectly valid here.
    local loopSnd = CreateSound(gekko, TENTACLE_LOOP)
    if loopSnd then
        loopSnd:SetSoundLevel(75)
        loopSnd:Play()
    end

    local entry = {
        gekko       = gekko,
        enemy       = enemy,
        startOffset = Vector(0, 0, GEKKO_ORIGIN_Z),
        endOffset   = Vector(0, 0, 40),
        width       = width,
        color       = Color(r, g_col, b_col, 255),
        removeAt    = CurTime() + snapDelay,
        loopSnd     = loopSnd,
    }
    table.insert(activeBeams, entry)

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
