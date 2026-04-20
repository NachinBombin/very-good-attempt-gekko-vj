-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--
--  Correct GMod API for ragdoll posing:
--    ragdoll:SetRagdollPos(boneIndex, worldPos)
--    ragdoll:SetRagdollAngles(boneIndex, worldAng)
--  These write directly into the ragdoll bone table that
--  the physics system reads on the NEXT tick, so calling them
--  in timer.Simple(0) -- one frame after spawn -- repositions
--  the colliders without creating impulses or freezing.
-- ============================================================

local FIND_RETRIES  = 60
local FIND_INTERVAL = 0.02

local function PoseRagdollFromNPC(ragdoll, npc)
    local count = ragdoll:GetPhysicsObjectCount()
    for i = 0, count - 1 do
        local phys = ragdoll:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            -- GetPhysicsObjectNum(i) maps to bone i on prop_ragdoll
            local m = npc:GetBoneMatrix(i)
            if m then
                ragdoll:SetRagdollPos(i, m:GetTranslation())
                ragdoll:SetRagdollAngles(i, m:GetAngles())
            end
        end
    end
end

-- ============================================================
--  Public API
-- ============================================================

function ENT:GekkoDeath_Init()
    self._deathPoseActive = false
    self.HasDeathCorpse   = true
    self.DeathCorpseCollisionType = COLLISION_GROUP_NONE
end

function ENT:GekkoDeath_Trigger()
    if self._deathPoseActive then return end
    self._deathPoseActive = true

    local npcRef   = self
    local attempts = 0

    local function TryPose()
        attempts = attempts + 1
        local corpse = npcRef.Corpse
        if IsValid(corpse) then
            PoseRagdollFromNPC(corpse, npcRef)
            print("[GekkoDeath] Ragdoll posed via SetRagdollPos/Angles (attempt " .. attempts .. ")")
            return
        end
        if attempts < FIND_RETRIES then
            timer.Simple(FIND_INTERVAL, TryPose)
        else
            print("[GekkoDeath] WARNING: corpse never found")
        end
    end

    timer.Simple(0, TryPose)
end

function ENT:GekkoDeath_Think()
end
