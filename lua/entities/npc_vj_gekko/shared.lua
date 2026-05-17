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
ENT.HasDeathCorpse = false

ENT.VJ_NPC_Class = {"CLASS_COMBINE"}
ENT.HullType     = HULL_LARGE
ENT.StartHealth  = 3300

ENT.StopMovingWhileAttacking = false

-- CRITICAL: This tells VJBase "we own sequence control".
-- Without it, VJBase calls ResetSequence every Think tick and
-- overwrites our SetPlaybackRate back to 1.0, making the run
-- animation and speed tuning completely ineffective.
ENT.VJ_NPC_UsesCustomMoveAnimation = true

ENT.MovementType             = VJ_MOVETYPE_GROUND
ENT.UsePoseParameterMovement = true
ENT.DisableWandering         = false
ENT.IdleAlwaysWander         = true

-- Walk and Run speed are intentionally the same here.
-- VJBase nav speed is kept flat; the distinction between
-- walking and running is handled entirely by GekkoUpdateAnimation
-- via the _gekkoRunning flag and playback-rate math
-- (arate = vel / ANIM_RUN_SPEED or ANIM_WALK_SPEED).
ENT.WalkSpeed = 184
ENT.RunSpeed  = 184

-- Disable VJBase's built-in chase-run task.
-- It fights GekkoUpdateAnimation for sequence ownership and
-- issues conflicting TASK_RUN_PATH commands.
ENT.VJ_RunToEnemy         = false
ENT.VJ_RunToEnemyDistance = 0

ENT.TurningSpeed  = 15
ENT.SightDistance = 900000
ENT.EnemyTimeout  = 560

ENT.VJ_NPC_UseGestures = false

ENT.ConstantlyFaceEnemy             = true
ENT.ConstantlyFaceEnemy_IfVisible   = true
ENT.ConstantlyFaceEnemy_IfAttacking = true
ENT.ConstantlyFaceEnemy_Postures    = "Both"
ENT.ConstantlyFaceEnemy_MinDistance = 1

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
--
--  IMPORTANT: BloodColor must be the VJ string constant
--  (VJ.BLOOD_COLOR_RED = "Red"), NOT the GMod native integer
--  (BLOOD_COLOR_RED = 0). VJ's SetupBloodColor() does:
--      bloodNames[blColor]  -- keys are strings like "Red"
--  Passing the integer 0 returns nil -> BloodParticle /
--  BloodDecal / BloodPool stay as empty tables -> PICK({}) = nil
--  -> SpawnBloodParticles and SpawnBloodDecals silently bail.
-- ============================================================
ENT.Bleeds     = true
ENT.BloodColor = VJ.BLOOD_COLOR_RED   -- "Red" (VJ string, NOT GMod BLOOD_COLOR_RED int)

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
