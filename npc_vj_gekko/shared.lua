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
ENT.StartHealth  = 1250


ENT.MovementType             = VJ_MOVETYPE_GROUND
ENT.UsePoseParameterMovement = true
ENT.DisableWandering         = false
ENT.IdleAlwaysWander         = true
ENT.WalkSpeed                = 120
ENT.RunSpeed                 = 200

ENT.SightDistance  = 8000   -- see farther
ENT.EnemyTimeout   = 60     -- don't forget enemy for 60s
ENT.HasMeleeAttack        = true
ENT.MeleeAttackDistance   = 100
ENT.NextMeleeAttackTime   = 6
ENT.AnimTbl_MeleeAttack   = false
ENT.HasRangeAttack                        = true
ENT.RangeAttackProjectiles                = "obj_vj_rocket"
ENT.RangeAttackMinDistance                = 200
ENT.RangeAttackMaxDistance                = 2000
ENT.AnimTbl_RangeAttack                   = false
ENT.TimeUntilRangeAttackProjectileRelease = 0
ENT.NextRangeAttackTime                   = 2

ENT.ConstantlyFaceEnemy             = true
ENT.ConstantlyFaceEnemy_IfVisible   = true
ENT.ConstantlyFaceEnemy_IfAttacking = true
ENT.ConstantlyFaceEnemy_Postures    = "Both"
ENT.ConstantlyFaceEnemy_MinDistance = 8000

ENT.HasSounds      = true
ENT.SoundTbl_Death = {
    "mechassault_2/mechs/mech_explode1.ogg",
    "mechassault_2/mechs/mech_explode2.ogg",
}
ENT.SoundTbl_Alert = {"mgs4/gekko/se_stage_mg_shadowmoses_gek_alert.wav"}
ENT.SoundTbl_Idle  = false   -- FIXED: empty table caused temptable spam

ENT.Bleeds     = true
ENT.BloodColor = BLOOD_COLOR_RED