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
ENT.StartHealth  = 3000

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

ENT.TurningSpeed  = 100
ENT.SightDistance = 48000
ENT.EnemyTimeout  = 160

ENT.VJ_NPC_UseGestures = false

ENT.ConstantlyFaceEnemy             = true
ENT.ConstantlyFaceEnemy_IfVisible   = true
ENT.ConstantlyFaceEnemy_IfAttacking = true
ENT.ConstantlyFaceEnemy_Postures    = "Both"
ENT.ConstantlyFaceEnemy_MinDistance = 1

-- ============================================================
--  NetworkVars
--
--  DO NOT call self.BaseClass.SetupDataTables(self) here.
--  The VJ base does not expose SetupDataTables as an inheritable
--  method — the engine calls each entity's SetupDataTables
--  independently. Chaining it causes a nil-call crash.
--
--  Index rules for npc_vj_creature_base (as of current VJ release):
--    Int   slots used by base: 0, 1, 2, 3, 4  → we use 5
--    Float slots used by base: 0, 1, 2         → we use 3
--  If you get "NetworkVar index out of range" bump these up by 1.
-- ============================================================
function ENT:SetupDataTables()
    self:NetworkVar("Int",   5, "GekkoJumpState")  -- 0=none 1=rising 2=falling 3=landing
    self:NetworkVar("Float", 3, "GekkoJumpTimer")  -- land-lockout countdown
end

-- ============================================================
--  Attack config
-- ============================================================
ENT.HasMeleeAttack = false

ENT.HasRangeAttack                        = true
ENT.RangeAttackProjectiles                = false
ENT.RangeAttackMinDistance                = 0
ENT.RangeAttackMaxDistance                = 16000
ENT.TimeUntilRangeAttackProjectileRelease = 0.1
ENT.NextRangeAttackTime                   = 4
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

-- VJ_AnimationTable must exist as a table; VJBase MaintainIdleAnimation
-- reads it every tick and prints 'temptable is nil' when it is absent.
ENT.AnimationTranslations = {}
ENT.VJ_AnimationTable     = {}

-- ============================================================
--  Blood / gore
-- ============================================================
ENT.Bleeds     = true
ENT.BloodColor = BLOOD_COLOR_RED
