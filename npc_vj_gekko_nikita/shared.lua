ENT.Base          = "npc_vj_creature_base"
ENT.Type          = "ai"
ENT.PrintName     = "Gekko Nikita"
ENT.Author        = "NachinBombin"
ENT.Contact       = ""
ENT.Purpose       = "Fast, self-steering cruise missile for Gekko"
ENT.Instructions  = ""
ENT.Category      = "Gekko"

ENT.Spawnable     = false
ENT.AdminOnly     = false

-- Core VJ settings
ENT.StartHealth           = 40
ENT.HasDeathAnimation     = false
ENT.HasDeathRagdoll       = false
ENT.HasGibOnDeath         = false
ENT.Bleeds                = false
ENT.HasMeleeAttack        = false
ENT.HasRangeAttack        = false
ENT.DisableFootStepSound  = true
ENT.HasHull               = false

-- VJ_MOVETYPE_AERIAL keeps the NPC aerial (no ground nav, correct hull).
-- Speeds are set to 0 so VJ's scheduler never issues its own movement
-- commands. All velocity is driven manually in CustomOnThink_AIEnabled.
ENT.MovementType                 = VJ_MOVETYPE_AERIAL
ENT.Aerial_FlyingSpeed_Calm      = 0
ENT.Aerial_FlyingSpeed_Alerted   = 0
ENT.Aerial_AdvanceSpeed          = 0
ENT.Aerial_AnimTbl_Calm          = {"Fly"}
ENT.Aerial_AnimTbl_Alerted       = {"Fly"}
ENT.Aerial_AllowPitchChanges     = true
ENT.Aerial_AllowPitchWhenMoving  = true
ENT.Aerial_NextMoveTime          = 0

ENT.Behavior          = VJ_BEHAVIOR_AGGRESSIVE
ENT.CallForHelp       = false
ENT.HasSoundTrack     = false
ENT.HasIdleSounds     = false
ENT.HasAlertSounds    = false
ENT.HasBeforeMeleeAttackSound = false
ENT.HasMeleeAttackSound       = false
ENT.HasPainSounds      = false
ENT.HasDeathSounds     = false

-- Explosion parameters (used server-side)
ENT.Nikita_Damage      = 120
ENT.Nikita_Radius      = 700
ENT.Nikita_ProxRadius  = 220
ENT.Nikita_LifeTime    = 45
