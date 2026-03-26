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
-- Drastically reduced movement speeds.
-- Original: Walk=80, Run=110.
-- These values drive the nav system; the animation playback rate
-- in init.lua is tuned separately to match the new speeds.
ENT.WalkSpeed                = 28
ENT.RunSpeed                 = 45

ENT.SightDistance = 8000
ENT.EnemyTimeout  = 60

-- ====== Animation Tables ======
ENT.AnimTbl_Idle         = {"idle"}
ENT.AnimTbl_Walk         = {"walk"}
ENT.AnimTbl_Run          = {"run"}
ENT.AnimTbl_MeleeAttack  = {"idle"}
ENT.AnimTbl_RangeAttack  = {"idle"}
ENT.AnimTbl_Flinch       = false
ENT.AnimTbl_Death        = false

-- ====== Melee (Stomp) ======
ENT.HasMeleeAttack                      = true
ENT.MeleeAttackDistance                 = 100
ENT.MeleeAttackDamageDistance           = 160
ENT.MeleeAttackAngleRadius              = 120
ENT.NextMeleeAttackTime                 = VJ.SET(6, 9)
ENT.NextAnyAttackTime_Melee             = 7
ENT.TimeUntilMeleeAttackDamage          = 0.1
ENT.DisableDefaultMeleeAttackDamageCode = true

-- ====== Range ======
ENT.HasRangeAttack                        = true
-- IMPORTANT: false — rockets are spawned manually in init.lua
-- to control which attachment (L or R) fires each time.
ENT.RangeAttackProjectiles                = false
ENT.RangeAttackMinDistance                = 250
ENT.RangeAttackMaxDistance                = 6000
ENT.TimeUntilRangeAttackProjectileRelease = 0.1
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

-- ====== Blood ======
ENT.Bleeds     = true
ENT.BloodColor = BLOOD_COLOR_RED
