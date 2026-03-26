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

ENT.SightDistance = 18000
ENT.EnemyTimeout  = 60

-- ====== Animation Tables ======
-- VJ Base uses these to pick sequences for each state.
-- Use sequence NAME strings; VJ resolves them via LookupSequence internally.
-- false = let VJ fall back to its default ACT lookup (safe).
ENT.AnimTbl_Idle         = {"idle"}
ENT.AnimTbl_Walk         = {"walk"}
ENT.AnimTbl_Run          = {"run"}
ENT.AnimTbl_MeleeAttack  = {"idle"}   -- Gekko has no dedicated melee anim; idle stance during stomp
ENT.AnimTbl_RangeAttack  = {"idle"}   -- Same: fire from idle pose, no separate fire anim
ENT.AnimTbl_Flinch       = false       -- No flinch sequence on this model
ENT.AnimTbl_Death        = false       -- No death sequence; we handle it in OnDeath

-- ====== Melee (Stomp) ======
ENT.HasMeleeAttack                      = true
ENT.MeleeAttackDistance                 = 100
ENT.MeleeAttackDamageDistance           = 160
ENT.MeleeAttackAngleRadius              = 120
ENT.NextMeleeAttackTime                 = VJ.SET(5, 7)
ENT.NextAnyAttackTime_Melee             = 6
ENT.TimeUntilMeleeAttackDamage          = 0.1
ENT.DisableDefaultMeleeAttackDamageCode = true

-- ====== Range ======
ENT.HasRangeAttack                        = true
ENT.RangeAttackProjectiles                = "obj_vj_rocket"
ENT.RangeAttackMinDistance                = 250
ENT.RangeAttackMaxDistance                = 6000
ENT.TimeUntilRangeAttackProjectileRelease = 0.1
ENT.NextRangeAttackTime                   = 9
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

-- ====== Blood ======
ENT.Bleeds     = true
ENT.BloodColor = BLOOD_COLOR_RED