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
--    tentacle_stab  : played at the target's position on cable break
--
--  Effects:
--    Dust emitter  : spawned at the target's connection point when the
--                    beam first attaches (GekkoElasticRope).
--    gekko_bloodstream : spawned at the target's connection point when
--                    the player snaps the cable (GekkoElasticBreak).
--
--  Cable-break detection is handled entirely server-side.
--  This file only receives GekkoElasticBreak to kill the beam
--  visually, play stab sound, and spawn blood effect.
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
-- ============================================================
local SHOOT_SOUNDS = {
    "gekko/elastic/shoot_1.wav",
    "gekko/elastic/shoot_2.wav",
    "gekko/elastic/shoot_3.wav",
    "gekko/elastic/shoot_4.wav",
    "gekko/elastic/shoot_5.wav",
}
local TENTACLE_LOOP  = "gekko/elastic/tentaclepull_1.wav"
local TENTACLE_STAB  = "gekko/elastic/tentacle_stab.wav"

-- ============================================================
--  DUST EFFECT  (played at attach point when beam lands)
-- ============================================================
local function SpawnAttachDust(pos)
    local emitter = ParticleEmitter(pos, false)
    if not emitter then return end

    for _ = 1, 18 do
        local p = emitter:Add("particle/smokesprites_000" .. math.random(1, 9), pos)
        if not p then continue end

        local dir = VectorRand()
        dir.z     = math.abs(dir.z)  -- bias upward so dust rises

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
--  BLOOD EFFECT  (played at break point when cable is snapped)
--  Uses the existing gekko_bloodstream effect.
-- ============================================================
local function SpawnBreakBlood(pos, enemy)
    -- gekko_bloodstream reads Entity and Origin from EffectData.
    -- Normal is set away from the Gekko (upward burst is fine as fallback).
    local ed = EffectData()
    ed:SetOrigin(pos)
    ed:SetNormal(Vector(0, 0, 1))
    if IsValid(enemy) then
        ed:SetEntity(enemy)
    end
    util.Effect("gekko_bloodstream", ed, true, true)
end

-- ============================================================
--  HELPER: stop and remove all beam entries for a given enemy.
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
--  Also spawns dust at the target's connection point.
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

    -- Dust at the exact attachment point on the target.
    local attachPos = enemy:GetPos() + Vector(0, 0, 40)
    SpawnAttachDust(attachPos)

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
--  CABLE BREAK  (server broadcast on early player snap)
--
--  1. Immediately removes all beam entries for the freed player.
--  2. Spawns gekko_bloodstream at the break position.
--  3. Plays tentacle_stab.wav at the break position.
-- ============================================================
net.Receive("GekkoElasticBreak", function()
    local enemy    = net.ReadEntity()
    local breakPos = net.ReadVector()

    if not IsValid(enemy) then return end

    -- Kill the beam and loop sound.
    RemoveBeamsForEnemy(enemy)

    -- Blood effect at the exact connection point.
    SpawnBreakBlood(breakPos, enemy)

    -- Stab sound at the exact connection point.
    -- sound.Play strips the leading "sound/" automatically.
    sound.Play(TENTACLE_STAB, breakPos, 85, 100)
end)
