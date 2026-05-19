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
--
--  PLAYER CABLE-BREAK:
--    While the local player is hooked (activeBeams contains an
--    entry where enemy == LocalPlayer()), every key-down or
--    mouse-click event is counted inside a rolling 1-second
--    timestamp buffer.  When the buffer reaches 7 events the
--    client sends "GekkoElasticPlayerBreak" to the server.
--    The server validates and replies with "GekkoElasticBreak"
--    which terminates the beam on all clients immediately.
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
--  CABLE-BREAK CONFIG
-- ============================================================
-- Number of button presses required within the window to break the cable.
local BREAK_THRESHOLD = 7
-- Rolling window length in seconds.
local BREAK_WINDOW    = 1.0

-- Timestamp ring-buffer for the local player's recent button presses.
-- Only populated while the player is actively hooked.
local breakPressTimes = {}
-- Guard: after the break request is sent, don't spam the net.
local breakRequestSent = false

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
--  HELPER: is the local player currently the hooked target?
-- ============================================================
local function LocalPlayerIsHooked()
    local ply = LocalPlayer()
    if not IsValid(ply) then return false end
    for _, b in ipairs(activeBeams) do
        if IsValid(b.enemy) and b.enemy == ply then
            return true
        end
    end
    return false
end

-- ============================================================
--  HELPER: remove beam entries for a specific enemy entity.
-- ============================================================
local function RemoveBeamsForEnemy(enemy)
    local i = 1
    while i <= #activeBeams do
        local b = activeBeams[i]
        if b.enemy == enemy then
            if b.loopSnd then
                b.loopSnd:Stop()
                b.loopSnd = nil
            end
            table.remove(activeBeams, i)
        else
            i = i + 1
        end
    end
end

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
--  PLAYER BUTTON-MASH DETECTION
--
--  PlayerButtonDown fires for every key-down and mouse-click
--  event on the client.  We only care when the local player is
--  the hooked target and the break hasn't been sent yet.
-- ============================================================
hook.Add("PlayerButtonDown", "GekkoElasticBreakMash", function(ply, button)
    -- Only track the local player.
    if ply ~= LocalPlayer() then return end
    -- Only count while hooked and break not yet requested.
    if breakRequestSent then return end
    if not LocalPlayerIsHooked() then return end

    local now = CurTime()
    -- Push the new timestamp.
    table.insert(breakPressTimes, now)

    -- Prune entries older than BREAK_WINDOW seconds.
    local windowStart = now - BREAK_WINDOW
    local j = 1
    while j <= #breakPressTimes do
        if breakPressTimes[j] < windowStart then
            table.remove(breakPressTimes, j)
        else
            j = j + 1
        end
    end

    -- If we hit the threshold, request a cable break from the server.
    if #breakPressTimes >= BREAK_THRESHOLD then
        breakRequestSent = true
        breakPressTimes  = {}
        net.Start("GekkoElasticPlayerBreak")
        net.SendToServer()
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
    local col_r     = net.ReadUInt(8)
    local col_g     = net.ReadUInt(8)
    local col_b     = net.ReadUInt(8)

    if not IsValid(gekko) or not IsValid(enemy) then return end

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
        color       = Color(col_r, col_g, col_b, 255),
        removeAt    = CurTime() + snapDelay,
        loopSnd     = loopSnd,
    }
    table.insert(activeBeams, entry)

    -- Reset break-mash state for any new incoming beam targeting local player.
    if IsValid(enemy) and enemy == LocalPlayer() then
        breakPressTimes  = {}
        breakRequestSent = false
    end

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

-- ============================================================
--  CABLE BREAK  (server confirmed early snap)
--
--  Immediately removes all beam entries targeting this enemy
--  and resets the mash-detection state.
-- ============================================================
net.Receive("GekkoElasticBreak", function()
    local enemy = net.ReadEntity()
    if not IsValid(enemy) then return end

    RemoveBeamsForEnemy(enemy)

    -- Reset mash state in case this is our own break confirmation.
    if enemy == LocalPlayer() then
        breakPressTimes  = {}
        breakRequestSent = false
    end
end)
