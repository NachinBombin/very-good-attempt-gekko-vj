-- ============================================================
--  npc_vj_gekko / shared.lua
-- ============================================================
AddCSLuaFile()

ENT.Base                  = "npc_vj_creature_base"
ENT.Type                  = "ai"
ENT.PrintName             = "Gekko"
ENT.Author                = "BombinBase"
ENT.Category              = "VJ Base"
ENT.Spawnable             = true
ENT.AdminSpawnable        = true
ENT.AutomaticFrameAdvance = true
ENT.IsVJBaseSNPC          = true

ENT.Model = {"models/metal_gear_solid_4/enemies/gekko.mdl"}

ENT.VJ_NPC_Class = {"CLASS_COMBINE"}
ENT.HullType     = HULL_LARGE
ENT.StartHealth  = 3100

ENT.StopMovingWhileAttacking = false

ENT.VJ_NPC_UsesCustomMoveAnimation = true

ENT.MovementType             = VJ_MOVETYPE_GROUND
ENT.UsePoseParameterMovement = true
ENT.DisableWandering         = false
ENT.IdleAlwaysWander         = true

ENT.WalkSpeed = 184
ENT.RunSpeed  = 184

ENT.VJ_RunToEnemy         = false
ENT.VJ_RunToEnemyDistance = 0

ENT.TurningSpeed  = 6
ENT.SightDistance = 900000
ENT.EnemyTimeout  = 260

-- ============================================================
--  Sight / detection -- the root cause of the Z-stare bug
--
--  EnemyXRayDetection = true
--    VJ Base init.lua line 1096 shows that when this flag is
--    true, self:Visible() bypasses the engine LOS trace and
--    returns true unconditionally.  The range attack gate on
--    line 2266 opens: "eneIsVisible" is always true regardless
--    of how steeply above the player is standing.
--
--  SightAngle = 360
--    IsInViewCone() uses GetFOV() which mirrors SightAngle.
--    At 360 deg the view cone check always passes, so
--    eneData.VisibleTime is written every single tick and
--    EnemyTimeout can never fire while a player is alive.
--
--  ConstantlyFaceEnemy_IfVisible = false
--    Previously true: the Gekko only rotated toward the enemy
--    when Visible() returned true.  With xray detection the
--    body now always turns toward the player at any elevation
--    so ranged weapons point correctly when they fire.
-- ============================================================
ENT.SightAngle               = 360
ENT.EnemyXRayDetection       = true

ENT.ConstantlyFaceEnemy             = true
ENT.ConstantlyFaceEnemy_IfVisible   = false   -- face at ALL times, not just when LOS is clear
ENT.ConstantlyFaceEnemy_IfAttacking = true
ENT.ConstantlyFaceEnemy_Postures    = "Both"
ENT.ConstantlyFaceEnemy_MinDistance = 1

-- ============================================================
--  Attack config
-- ============================================================
ENT.HasMeleeAttack = false

ENT.HasRangeAttack                        = true
ENT.RangeAttackProjectiles                = false
ENT.RangeAttackMinDistance                = 0
ENT.RangeAttackMaxDistance                = 900000
ENT.TimeUntilRangeAttackProjectileRelease = 0.1
ENT.NextRangeAttackTime                   = 6
ENT.NextAnyAttackTime_Range               = 2

-- Widen angle gate to near-omnidirectional.
-- cos(rad(180)) = -1 so the dot product check always passes.
-- Combined with EnemyXRayDetection this permanently defeats
-- every geometric check inside the range attack gate.
ENT.RangeAttackAngleRadius = 180

-- ============================================================
--  NetworkVars
-- ============================================================
function ENT:SetupDataTables()
    self:NetworkVar("Int",   5, "GekkoJumpState")
    self:NetworkVar("Float", 3, "GekkoJumpTimer")
end

-- ============================================================
--  FK360 shared timing constant
-- ============================================================
ENT.FK360_DURATION = 0.9

-- ============================================================
--  Physics / damage
-- ============================================================
ENT.DisablePhysicsOnDamage = true

-- ============================================================
--  Sounds
-- ============================================================
ENT.HasSounds     = true
ENT.NoIdleChatter = true

ENT.SoundTbl_Death = {
    "mechassault_2/mechs/mech_explode1.ogg",
    "mechassault_2/mechs/mech_explode2.ogg",
}
ENT.SoundTbl_Alert = {"mgs4/gekko/se_stage_mg_shadowmoses_gek_alert.wav"}

ENT.AnimationTranslations = {}

-- ============================================================
--  Blood / gore
-- ============================================================
ENT.Bleeds     = true
ENT.BloodColor = BLOOD_COLOR_RED

-- ============================================================
--  Sound precache
--  sound.Add registers custom sound paths with the engine so
--  EmitSound can find and play them. Must run on both client
--  and server (shared.lua), before any weapon fires.
-- ============================================================
local function GekkoAddSound( name, path )
    sound.Add({
        name        = name,
        channel     = CHAN_WEAPON,
        volume      = 1.0,
        soundlevel  = 85,
        pitchstart  = 100,
        pitchend    = 100,
        sound       = path,
    })
end

-- Common rocket / salvo
GekkoAddSound("Gekko.RocketFire1", "gekko/wp0040_se_gun_fire_01.wav")
GekkoAddSound("Gekko.RocketFire2", "gekko/wp0040_se_gun_fire_02.wav")
GekkoAddSound("Gekko.RocketFire3", "gekko/wp0040_se_gun_fire_03.wav")

-- Top-attack / track missile
GekkoAddSound("Gekko.MissileFire1", "gekko/wp10e0_se_stinger_pass_1.wav")
GekkoAddSound("Gekko.MissileFire2", "gekko/wp0302_se_missile_fire_1.wav")
GekkoAddSound("Gekko.MissileFire3", "gekko/wp0302_se_missile_pass_2.wav")
