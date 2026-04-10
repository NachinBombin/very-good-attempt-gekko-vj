AddCSLuaFile()

-- ============================================================
--  npc_vj_gekko_nikita_guide / shared.lua
--  Ray-cast steered aerial guide for the Nikita missile.
--  Does NOT use VJ aerial AI or nodegraph - navigates purely
--  by looking around with traces, identical to the missile.
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

ENT.Model = {"models/mortarsynth.mdl"}

ENT.VJ_NPC_Class = {"CLASS_COMBINE"}
ENT.HullType     = HULL_TINY
ENT.StartHealth  = 10

-- We override movement entirely with MOVETYPE_NOCLIP in Init.
-- Setting AERIAL here just satisfies VJ Base spawn checks.
ENT.MovementType = VJ_MOVETYPE_AERIAL

ENT.StopMovingWhileAttacking = false
ENT.DisableWandering         = true
ENT.IdleAlwaysWander         = false

ENT.WalkSpeed = 0
ENT.RunSpeed  = 0

ENT.TurningSpeed  = 30
ENT.SightDistance = 48000
ENT.EnemyTimeout  = 20

ENT.VJ_NPC_UseGestures = false

ENT.HasMeleeAttack = false
ENT.HasRangeAttack = false
ENT.HasDeathCorpse = false

ENT.HasSounds      = false
ENT.NoIdleChatter  = true
ENT.Bleeds         = false
