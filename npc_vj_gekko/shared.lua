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
ENT.WalkSpeed                = 100
ENT.RunSpeed                 = 150

ENT.SightDistance = 8000
ENT.EnemyTimeout  = 60

-- ====== Melee (Stomp) ======
ENT.HasMeleeAttack                      = true
ENT.MeleeAttackDistance                 = 140
ENT.MeleeAttackDamageDistance           = 160
ENT.MeleeAttackAngleRadius              = 120
ENT.NextMeleeAttackTime                 = VJ.SET(5, 7)
ENT.NextAnyAttackTime_Melee             = 6
ENT.AnimTbl_MeleeAttack                 = false
ENT.TimeUntilMeleeAttackDamage          = 0.1   -- small explicit value, NOT false
ENT.DisableDefaultMeleeAttackDamageCode = true

-- ====== Range (Bullet burst) ======
ENT.HasRangeAttack                        = true
ENT.RangeAttackProjectiles                = "obj_vj_rocket"
ENT.RangeAttackMinDistance                = 250
ENT.RangeAttackMaxDistance                = 2000
ENT.AnimTbl_RangeAttack                   = false
ENT.TimeUntilRangeAttackProjectileRelease = 0.1  -- small explicit value, NOT false
ENT.NextRangeAttackTime                   = VJ.SET(2, 4)
ENT.NextAnyAttackTime_Range               = 3

-- ====== Facing ======
ENT.ConstantlyFaceEnemy             = false
ENT.ConstantlyFaceEnemy_IfVisible   = false
ENT.ConstantlyFaceEnemy_IfAttacking = false
ENT.ConstantlyFaceEnemy_Postures    = "Both"
ENT.ConstantlyFaceEnemy_MinDistance = 8000

-- ====== Sounds ======
ENT.HasSounds      = true
ENT.SoundTbl_Death = {
    "mechassault_2/mechs/mech_explode1.ogg",
    "mechassault_2/mechs/mech_explode2.ogg",
}
ENT.SoundTbl_Alert = {"mgs4/gekko/se_stage_mg_shadowmoses_gek_alert.wav"}
-- SoundTbl_Idle intentionally omitted (nil = no idle sounds, false causes temptable spam)

-- ====== Blood ======
ENT.Bleeds     = true
ENT.BloodColor = BLOOD_COLOR_RED