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

ENT.StopMovingWhileAttacking        = false


ENT.VJ_NPC_UsesCustomMoveAnimation = true

ENT.MovementType             = VJ_MOVETYPE_GROUND
ENT.UsePoseParameterMovement = true
ENT.DisableWandering         = false
ENT.IdleAlwaysWander         = true

-- Real-world nav speeds.
-- The engine caps ground NPC movement at ~280 u/s regardless of this value.
-- Walk and run visually differ only through animation — not actual movement speed.
ENT.WalkSpeed = 184
ENT.RunSpeed  = 184

-- VJ Base run-to-enemy: disabled.
-- Speed and animation are fully controlled in init.lua.
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

-- Walk/Run animation is handled entirely by TranslateActivity in init.lua.
-- Do NOT define AnimTbl_Walk or AnimTbl_Run here — causes "temptable is nil" spam.

ENT.HasMeleeAttack = false

ENT.HasRangeAttack                        = true
ENT.RangeAttackProjectiles                = false
ENT.RangeAttackMinDistance                = 0
ENT.RangeAttackMaxDistance                = 16000
ENT.TimeUntilRangeAttackProjectileRelease = 0.1
ENT.NextRangeAttackTime                   = 4
ENT.NextAnyAttackTime_Range               = 2

ENT.DisablePhysicsOnDamage = true

ENT.HasSounds     = true
ENT.NoIdleChatter = true
ENT.SoundTbl_Death = {
    "mechassault_2/mechs/mech_explode1.ogg",
    "mechassault_2/mechs/mech_explode2.ogg",
}
ENT.SoundTbl_Alert = {"mgs4/gekko/se_stage_mg_shadowmoses_gek_alert.wav"}

ENT.Bleeds     = true
ENT.BloodColor = BLOOD_COLOR_RED