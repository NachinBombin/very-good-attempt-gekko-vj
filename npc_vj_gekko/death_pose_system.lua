-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--
--  prop_physics only gets one convex hull -- legs/head have no
--  collision. prop_ragdoll uses the full compound .phy mesh.
--
--  We spawn a prop_ragdoll manually (so we control everything),
--  copy every bone matrix from the live NPC so limbs stay
--  connected, then set very high mass on every bone so the
--  ragdoll sinks naturally and resists being thrown.
-- ============================================================

local BONE_MASS = 50000  -- per bone; ragdoll sinks fast, won't fly from explosions

local function SpawnCorpse(npc)
    if not IsValid(npc) then return end

    local corpse = ents.Create("prop_ragdoll")
    if not IsValid(corpse) then return end

    corpse:SetModel(npc:GetModel())
    corpse:SetPos(npc:GetPos())
    corpse:SetAngles(npc:GetAngles())
    corpse:SetSkin(npc:GetSkin())
    corpse:Spawn()
    corpse:Activate()

    -- Copy every bone matrix from the live NPC so limbs are
    -- in the right pose and not flying apart
    for i = 0, npc:GetBoneCount() - 1 do
        local matrix = npc:GetBoneMatrix(i)
        if matrix then
            corpse:SetBoneMatrix(i, matrix)
        end
    end

    -- Full world collision
    corpse:SetCollisionGroup(COLLISION_GROUP_NONE)

    -- High mass on every ragdoll bone
    for i = 0, corpse:GetPhysicsObjectCount() - 1 do
        local phys = corpse:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            phys:SetMass(BONE_MASS)
            phys:EnableGravity(true)
            phys:EnableCollisions(true)
            phys:Wake()
        end
    end

    npc.Corpse = corpse
    print("[GekkoDeath] prop_ragdoll spawned, bone_mass=" .. BONE_MASS)
    return corpse
end

-- ============================================================
--  Public API
-- ============================================================

function ENT:GekkoDeath_Init()
    self._deathPoseActive = false
    self.HasDeathCorpse   = false  -- we handle it
end

function ENT:GekkoDeath_Trigger()
    if self._deathPoseActive then return end
    self._deathPoseActive = true
    SpawnCorpse(self)
end

function ENT:GekkoDeath_Think()
end
