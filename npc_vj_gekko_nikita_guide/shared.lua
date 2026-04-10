AddCSLuaFile()

-- ============================================================
--  npc_vj_gekko_nikita_guide / shared.lua
--  Invisible aerial SNPC used as a path guide for the Nikita missile.
--  It relies on VJ Base's aerial movement + nodegraph, while the
--  missile itself keeps its own steering and avoidance logic.
-- ============================================================

ENT.Base                  = "npc_vj_creature_base"
ENT.Type                  = "ai"
ENT.PrintName             = "Gekko Nikita Guide"
ENT.Author                = "BombinBase"
ENT.Category              = "VJ Base"
ENT.Spawnable             = false
ENT.AdminSpawnable        = false
ENT.AutomaticFrameAdvance = false
ENT.IsVJBaseSNPC          = true

-- Use a tiny, unobtrusive model. It can be made effectively invisible
-- in practice via materials if desired, but keeping a real model makes
-- debugging much easier.
ENT.Model = {"models/mortarsynth.mdl"}

ENT.VJ_NPC_Class = {"CLASS_COMBINE"}
ENT.HullType     = HULL_TINY
ENT.StartHealth  = 10

ENT.MovementType = VJ_MOVETYPE_AERIAL

ENT.StopMovingWhileAttacking = false
ENT.DisableWandering         = true
ENT.IdleAlwaysWander         = false

ENT.WalkSpeed = 260
ENT.RunSpeed  = 260

ENT.VJ_RunToEnemy         = true
ENT.VJ_RunToEnemyDistance = 0

ENT.TurningSpeed  = 30
ENT.SightDistance = 48000
ENT.EnemyTimeout  = 20

ENT.VJ_NPC_UseGestures = false

ENT.ConstantlyFaceEnemy             = true
ENT.ConstantlyFaceEnemy_IfVisible   = true
ENT.ConstantlyFaceEnemy_IfAttacking = true
ENT.ConstantlyFaceEnemy_Postures    = "Both"
ENT.ConstantlyFaceEnemy_MinDistance = 1

ENT.HasMeleeAttack = false

ENT.HasRangeAttack                        = false
ENT.RangeAttackProjectiles                = false
ENT.RangeAttackMinDistance                = 0
ENT.RangeAttackMaxDistance                = 0
ENT.TimeUntilRangeAttackProjectileRelease = 0.0
ENT.NextRangeAttackTime                   = 0.0
ENT.NextAnyAttackTime_Range               = 0.0

ENT.HasDeathCorpse        = false
ENT.DisablePhysicsOnDamage = true

ENT.HasSounds     = false
ENT.NoIdleChatter = true

ENT.Bleeds     = false
ENT.BloodColor = BLOOD_COLOR_RED
