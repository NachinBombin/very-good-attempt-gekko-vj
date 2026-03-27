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
ENT.StartHealth  = 3100

ENT.MovementType             = VJ_MOVETYPE_GROUND
ENT.UsePoseParameterMovement = true
ENT.DisableWandering         = false
ENT.IdleAlwaysWander         = true
ENT.WalkSpeed                = 80
ENT.RunSpeed                 = 80   -- keep walking always

ENT.TurningSpeed = 500

ENT.SightDistance = 18000
ENT.EnemyTimeout  = 60

-- FIX 2: Re-enable facing so the chase scheduler can properly
-- complete orientation steps and not stall mid-schedule.
ENT.ConstantlyFaceEnemy             = true
ENT.ConstantlyFaceEnemy_IfVisible   = true
ENT.ConstantlyFaceEnemy_IfAttacking = true
ENT.ConstantlyFaceEnemy_Postures    = "Both"
ENT.ConstantlyFaceEnemy_MinDistance = 0   -- always face, no distance gate

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
ENT.RangeAttackProjectiles                = false
-- FIX 1: Push min distance up so the Gekko keeps chasing
-- instead of planting itself and waiting for the attack timer.
ENT.RangeAttackMinDistance                = 900
ENT.RangeAttackMaxDistance                = 6000
ENT.TimeUntilRangeAttackProjectileRelease = 0.1
-- FIX 1: Shorten attack cooldowns so it never idles waiting.
ENT.NextRangeAttackTime                   = 4
ENT.NextAnyAttackTime_Range               = 1.5

-- FIX: prevents Source engine from applying bullet/explosion
-- force impulses to the NPC's physics body on hit.
ENT.DisablePhysicsOnDamage = true

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