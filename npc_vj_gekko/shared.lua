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

ENT.Model    = {"models/metal_gear_solid_4/enemies/gekko.mdl"}

ENT.VJ_NPC_Class = {"CLASS_COMBINE"}
ENT.HullType     = HULL_LARGE
ENT.StartHealth  = 3000

ENT.MovementType             = VJ_MOVETYPE_GROUND
ENT.UsePoseParameterMovement = true
ENT.DisableWandering         = false
ENT.IdleAlwaysWander         = true
ENT.WalkSpeed                = 80
ENT.RunSpeed                 = 110

-- High turning speed so nav steering snaps quickly and doesn't drag
-- the head bone tracker across multiple frames during rotation.
ENT.TurningSpeed = 1000

ENT.SightDistance = 18000
ENT.EnemyTimeout  = 60

-- ====== Facing: fully disabled ======
-- VJ's SCHED_CHASE_ENEMY calls SetIdealYaw toward the enemy every think
-- even with melee off. This slams bodyYaw each frame, making the bone
-- head tracker's relYaw = (toEnemy.y - bodyYaw) never stable.
-- Disabling all face-enemy automation lets the nav system steer the
-- body naturally while our bone driver handles the head independently.
ENT.ConstantlyFaceEnemy             = false
ENT.ConstantlyFaceEnemy_IfVisible   = false
ENT.ConstantlyFaceEnemy_IfAttacking = false
ENT.ConstantlyFaceEnemy_Postures    = "Both"
ENT.ConstantlyFaceEnemy_MinDistance = 99999

-- ====== Animation Tables ======
ENT.AnimTbl_Idle         = {"idle"}
ENT.AnimTbl_Walk         = {"walk"}
ENT.AnimTbl_Run          = {"run"}
ENT.AnimTbl_RangeAttack  = {"idle"}
ENT.AnimTbl_Flinch       = false
ENT.AnimTbl_Death        = false

-- ====== Melee: DISABLED ======
ENT.HasMeleeAttack = false

-- ====== Range ======
ENT.HasRangeAttack                        = true
-- false = VJ will NOT auto-fire a projectile; OnRangeAttackExecute handles everything
ENT.RangeAttackProjectiles                = false
ENT.RangeAttackMinDistance                = 250
ENT.RangeAttackMaxDistance                = 6000
ENT.TimeUntilRangeAttackProjectileRelease = 0.1
ENT.NextRangeAttackTime                   = 9
ENT.NextAnyAttackTime_Range               = 3

-- ====== Sounds ======
ENT.HasSounds        = true
ENT.NoIdleChatter    = true
ENT.SoundTbl_Death   = {
    "mechassault_2/mechs/mech_explode1.ogg",
    "mechassault_2/mechs/mech_explode2.ogg",
}
ENT.SoundTbl_Alert   = {"mgs4/gekko/se_stage_mg_shadowmoses_gek_alert.wav"}

-- ====== Blood ======
ENT.Bleeds     = true
ENT.BloodColor = BLOOD_COLOR_RED
