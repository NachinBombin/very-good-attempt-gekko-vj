-- mg_shell_system.lua  (CLIENT)
-- Spawns brass casings using the exact same architecture as the
-- CW 2.0 base (cw_shells.lua):
--   • ClientsideModel  — purely clientside, never networked
--   • PhysicsInitBox   — tiny AABB collider
--   • MOVETYPE_VPHYSICS + SOLID_VPHYSICS + COLLISION_GROUP_DEBRIS
--   • gmod_silent material  — mutes Source's built-in VPhysics impact sounds
--   • One-shot PhysicsCollide callback  — plays the clink sound on the
--     FIRST collision only, then removes itself (prevents multi-bounce spam)
--   • sound.Play via a registered sound-script name, directional ("<" prefix)
-- ============================================================

-- ============================================================
--  SOUND REGISTRATION  (mirrors CW's addRegularSound)
-- ============================================================

-- ── MG light casing ────────────────────────────────────────────────────────────
-- CHAN_AUTO, vol 1.0, level 65 (close-range quiet), pitch 92-112
local SHELL_SOUND_NAME = "GekkoMGShellClink"

do
    local tbl = {
        name       = SHELL_SOUND_NAME,
        channel    = CHAN_AUTO,
        volume     = 1.0,
        level      = 65,
        pitchstart = 92,
        pitchend   = 112,
        sound = {
            "<player/pl_shell1.wav",
            "<player/pl_shell2.wav",
            "<player/pl_shell3.wav",
        },
    }
    sound.Add(tbl)
    util.PrecacheSound("player/pl_shell1.wav")
    util.PrecacheSound("player/pl_shell2.wav")
    util.PrecacheSound("player/pl_shell3.wav")
end

-- ── Bushmaster 25mm autocannon casing ─────────────────────────────────────────
-- Same CW pattern, tuned louder and heavier than the MG:
--   level  78 vs 65  -> audible from ~2-3x further away
--   pitch  80-100    -> lower = heavier metallic clank
local BUSH_SOUND_NAME = "GekkoBushmasterShellClink"

do
    local tbl = {
        name       = BUSH_SOUND_NAME,
        channel    = CHAN_AUTO,
        volume     = 1.0,
        level      = 78,
        pitchstart = 80,
        pitchend   = 100,
        sound = {
            "<player/pl_shell1.wav",
            "<player/pl_shell2.wav",
            "<player/pl_shell3.wav",
        },
    }
    sound.Add(tbl)
    -- PrecacheSound is idempotent; safe to call twice for shared WAVs
    util.PrecacheSound("player/pl_shell1.wav")
    util.PrecacheSound("player/pl_shell2.wav")
    util.PrecacheSound("player/pl_shell3.wav")
end

-- ============================================================
--  PHYSICS DIMENSIONS
-- ============================================================
-- MG: compact collider
local SHELL_MINS = Vector(-0.5, -0.15, -0.5)
local SHELL_MAXS = Vector( 0.5,  0.15,  0.5)

-- Bushmaster: bigger case, bigger AABB
local BUSH_MINS = Vector(-0.7, -0.25, -0.7)
local BUSH_MAXS = Vector( 0.7,  0.25,  0.7)

-- ============================================================
--  ONE-SHOT COLLISION CALLBACKS  (CW collideCallback pattern)
--  Defined outside spawners so they are allocated once, not per-shell.
-- ============================================================
local function OnShellCollide(ent, collData)
    sound.Play(SHELL_SOUND_NAME, ent:GetPos())
    ent:RemoveCallback("PhysicsCollide", ent._shellCBID)
end

local function OnBushShellCollide(ent, collData)
    sound.Play(BUSH_SOUND_NAME, ent:GetPos())
    ent:RemoveCallback("PhysicsCollide", ent._shellCBID)
end

-- ============================================================
--  SHARED PHYSICS SETUP  (avoids duplication between spawners)
-- ============================================================
local function ApplyShellPhysics(ent, vel, mass, mins, maxs)
    ent:PhysicsInitBox(mins, maxs)
    ent:SetMoveType(MOVETYPE_VPHYSICS)
    ent:SetSolid(SOLID_VPHYSICS)
    ent:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

    local phys = ent:GetPhysicsObject()
    if not IsValid(phys) then ent:Remove() return false end

    phys:SetMaterial("gmod_silent")  -- suppress Source surface-impact sounds
    phys:SetMass(mass)
    phys:SetVelocity(vel)
    return true
end

-- ============================================================
--  PUBLIC SPAWNER: GekkoSpawnMGShell
--  Light MG casing.  Call once per MG bullet fired.
-- ============================================================
function GekkoSpawnMGShell(pos, ang, shellModel, shellScale)
    shellModel = shellModel or "models/weapons/rifleshell.mdl"
    shellScale = shellScale or 1

    local right = ang:Right()
    local up    = ang:Up()
    local vel   = right * math.Rand(60, 110)
              + up    * math.Rand(20,  55)
    vel.x = vel.x + math.Rand(-5, 5)
    vel.y = vel.y + math.Rand(-5, 5)
    vel.z = vel.z + math.Rand(-5, 5)

    local ent = ClientsideModel(shellModel, RENDERGROUP_BOTH)
    if not IsValid(ent) then return end

    ent:SetPos(pos)
    ent:SetAngles(ang)
    ent:SetModelScale(shellScale, 0)

    if not ApplyShellPhysics(ent, vel, 10, SHELL_MINS, SHELL_MAXS) then return end

    local phys = ent:GetPhysicsObject()
    phys:AddAngleVelocity(
        ang:Right() * 100 + Vector(
            math.random(-500, 500),
            math.random(-500, 500),
            math.random(-500, 500)
        )
    )

    ent._shellCBID = ent:AddCallback("PhysicsCollide", OnShellCollide)
    SafeRemoveEntityDelayed(ent, 5)
end

-- ============================================================
--  PUBLIC SPAWNER: GekkoSpawnBushmasterShell
--  Heavy 25mm autocannon casing.  Call once per Bushmaster shot.
--
--  Differences from GekkoSpawnMGShell:
--    model scale  1.6x  -> visually larger brass
--    velocity     90-160 / 30-80  -> punts out with more authority
--    mass         30 (vs 10)     -> heavier floor impact
--    AABB         bigger (BUSH_MINS/MAXS)
--    angular vel  +-700 (vs +-500) -> more violent tumble
--    sound        GekkoBushmasterShellClink (level 78, pitch 80-100)
-- ============================================================
function GekkoSpawnBushmasterShell(pos, ang, shellModel, shellScale)
    shellModel = shellModel or "models/weapons/rifleshell.mdl"
    shellScale = (shellScale or 1) * 1.6

    local right = ang:Right()
    local up    = ang:Up()
    local vel   = right * math.Rand(90, 160)
              + up    * math.Rand(30,  80)
    vel.x = vel.x + math.Rand(-8, 8)
    vel.y = vel.y + math.Rand(-8, 8)
    vel.z = vel.z + math.Rand(-8, 8)

    local ent = ClientsideModel(shellModel, RENDERGROUP_BOTH)
    if not IsValid(ent) then return end

    ent:SetPos(pos)
    ent:SetAngles(ang)
    ent:SetModelScale(shellScale, 0)

    if not ApplyShellPhysics(ent, vel, 30, BUSH_MINS, BUSH_MAXS) then return end

    local phys = ent:GetPhysicsObject()
    phys:AddAngleVelocity(
        ang:Right() * 200 + Vector(
            math.random(-700, 700),
            math.random(-700, 700),
            math.random(-700, 700)
        )
    )

    ent._shellCBID = ent:AddCallback("PhysicsCollide", OnBushShellCollide)
    SafeRemoveEntityDelayed(ent, 5)
end
