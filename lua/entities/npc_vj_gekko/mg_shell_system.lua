-- mg_shell_system.lua  (CLIENT)
-- Spawns 25mm MG brass casings using the exact same architecture as the
-- CW 2.0 base (cw_shells.lua):
--   • ClientsideModel  — purely clientside, never networked
--   • PhysicsInitBox   — tiny AABB collider
--   • MOVETYPE_VPHYSICS + SOLID_VPHYSICS + COLLISION_GROUP_DEBRIS
--   • gmod_silent material  — mutes Source's built-in VPhysics impact sounds
--   • One-shot PhysicsCollide callback  — plays the clink sound on the
--     FIRST collision only, then removes itself (prevents multi-bounce spam)
--   • sound.Play via a registered sound-script name, directional ("<" prefix)
-- ============================================================

-- ─── Sound registration (mirrors CW's addRegularSound) ───────────────────────
-- Register once.  CHAN_AUTO, vol 1.0, sound level 65 (close-range quiet),
-- pitch 92–112 random, directional "<" prefix.
local SHELL_SOUND_NAME = "GekkoMGShellClink"

do
    local tbl = {
        name       = SHELL_SOUND_NAME,
        channel    = CHAN_AUTO,
        volume     = 1.0,
        level      = 65,
        pitchstart = 92,
        pitchend   = 112,
        -- "<" makes Source attenuate the sound with distance (directional)
        sound = {
            "<player/pl_shell1.wav",
            "<player/pl_shell2.wav",
            "<player/pl_shell3.wav",
        },
    }
    sound.Add(tbl)
    -- Precache every variant so there is no stutter on first play
    util.PrecacheSound("player/pl_shell1.wav")
    util.PrecacheSound("player/pl_shell2.wav")
    util.PrecacheSound("player/pl_shell3.wav")
end

-- ─── Physics dims (same as CW mainshell) ─────────────────────────────────────
local SHELL_MINS = Vector(-0.5, -0.15, -0.5)
local SHELL_MAXS = Vector( 0.5,  0.15,  0.5)

-- ─── One-shot collision callback (identical logic to CW collideCallback) ─────
-- Stored outside the spawner so it is allocated once, not per-shell.
local function OnShellCollide(ent, collData)
    -- Play the sound at the shell's current world position
    sound.Play(SHELL_SOUND_NAME, ent:GetPos())
    -- Remove the callback so the sound fires ONCE only, not on every bounce
    ent:RemoveCallback("PhysicsCollide", ent._shellCBID)
end

-- ─── Public spawner ──────────────────────────────────────────────────────────
-- Call this every time you want to eject a casing.
--
--   pos        : world position of the ejection port (Vector)
--   ang        : world angles of the weapon at fire time (Angle)
--   shellModel : (optional) model path string; defaults to rifleshell
--   shellScale : (optional) model scale multiplier; defaults to 1
--
function GekkoSpawnMGShell(pos, ang, shellModel, shellScale)
    shellModel = shellModel or "models/weapons/rifleshell.mdl"
    shellScale = shellScale or 1

    -- Initial velocity: eject rightward + slight upward kick, CW-style jitter
    local right = ang:Right()
    local up    = ang:Up()
    local vel   = right * math.Rand(60, 110)
              + up    * math.Rand(20,  55)
    vel.x = vel.x + math.Rand(-5, 5)
    vel.y = vel.y + math.Rand(-5, 5)
    vel.z = vel.z + math.Rand(-5, 5)

    -- Spawn a purely clientside model (never networked — same as CW)
    local ent = ClientsideModel(shellModel, RENDERGROUP_BOTH)
    if not IsValid(ent) then return end

    ent:SetPos(pos)
    ent:SetAngles(ang)
    ent:SetModelScale(shellScale, 0)
    ent:PhysicsInitBox(SHELL_MINS, SHELL_MAXS)
    ent:SetMoveType(MOVETYPE_VPHYSICS)
    ent:SetSolid(SOLID_VPHYSICS)
    ent:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

    local phys = ent:GetPhysicsObject()
    if not IsValid(phys) then ent:Remove() return end

    -- "gmod_silent" suppresses Source's own surface-impact sounds so that
    -- we (like CW) can play exactly ONE custom clink via the callback below.
    phys:SetMaterial("gmod_silent")
    phys:SetMass(10)
    phys:SetVelocity(vel)

    -- Tumble: random angular velocity on all axes (mirrors CW finishMaking)
    local avel = ang:Right() * 100 + Vector(
        math.random(-500, 500),
        math.random(-500, 500),
        math.random(-500, 500)
    )
    phys:AddAngleVelocity(avel)

    -- Register the ONE-SHOT collision sound callback (CW pattern)
    ent._shellCBID = ent:AddCallback("PhysicsCollide", OnShellCollide)

    -- Auto-remove after 5 s (same default as CW)
    SafeRemoveEntityDelayed(ent, 5)
end
