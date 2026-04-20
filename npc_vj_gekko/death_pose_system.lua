-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--
--  VJ Base's DeathCorpseEntityClass is only honoured by the
--  human/creature bases -- the NPC base ignores it and always
--  spawns a prop_ragdoll with no collision.
--
--  Solution: suppress VJ's corpse entirely (HasDeathCorpse=false)
--  and spawn our own prop_physics manually inside OnDeath so we
--  control every physics parameter from the start.
-- ============================================================

local CORPSE_MASS = 50000

local function SpawnCorpse(npc)
    if not IsValid(npc) then return end

    local corpse = ents.Create("prop_physics")
    if not IsValid(corpse) then return end

    corpse:SetModel(npc:GetModel())
    corpse:SetPos(npc:GetPos())
    corpse:SetAngles(npc:GetAngles())
    corpse:SetSkin(npc:GetSkin())
    corpse:Spawn()
    corpse:Activate()

    -- Full world collision from birth
    corpse:SetCollisionGroup(COLLISION_GROUP_NONE)
    corpse:SetSolid(SOLID_VPHYSICS)
    corpse:SetMoveType(MOVETYPE_VPHYSICS)

    local phys = corpse:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetMass(CORPSE_MASS)
        phys:EnableGravity(true)
        phys:EnableCollisions(true)
        phys:Wake()
    end

    -- Store reference so other systems can find it
    npc.Corpse = corpse

    print("[GekkoDeath] manual prop_physics corpse spawned, mass=" .. CORPSE_MASS)
    return corpse
end

-- ============================================================
--  Public API
-- ============================================================

function ENT:GekkoDeath_Init()
    self._deathPoseActive = false
    -- Tell VJ NOT to spawn its own corpse; we handle it
    self.HasDeathCorpse = false
end

function ENT:GekkoDeath_Trigger()
    if self._deathPoseActive then return end
    self._deathPoseActive = true
    SpawnCorpse(self)
end

function ENT:GekkoDeath_Think()
end
