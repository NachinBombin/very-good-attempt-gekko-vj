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
-- Match original vehicle walk speed exactly (GetSpeeds() -> walk=200)
ENT.WalkSpeed                = 200
ENT.RunSpeed                 = 200   -- capped to walk only; run anim triggers above 300 u/s

ENT.TurningSpeed = 1000

ENT.SightDistance = 18000
ENT.EnemyTimeout  = 60

-- Re-enabled so the chase scheduler completes orientation steps
-- and doesn't stall mid-schedule when the player moves away.
ENT.ConstantlyFaceEnemy             = true
ENT.ConstantlyFaceEnemy_IfVisible   = true
ENT.ConstantlyFaceEnemy_IfAttacking = true
ENT.ConstantlyFaceEnemy_Postures    = "Both"
ENT.ConstantlyFaceEnemy_MinDistance = 0

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
-- Raised min distance so Gekko keeps chasing instead of
-- planting and waiting for the 9s attack cooldown.
ENT.RangeAttackMinDistance                = 900
ENT.RangeAttackMaxDistance                = 6000
ENT.TimeUntilRangeAttackProjectileRelease = 0.1
ENT.NextRangeAttackTime                   = 4
ENT.NextAnyAttackTime_Range               = 1.5

-- Prevents Source engine applying bullet/explosion force
-- impulses to the NPC physics body (no more jumping on hit).
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
