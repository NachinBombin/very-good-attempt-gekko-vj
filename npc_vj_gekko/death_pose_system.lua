-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--
--  KEY FINDING FROM DIAGNOSTIC:
--  The ragdoll has 72 bones but only 8 physics objects.
--  GetBoneName(physIndex) was returning bone[0..7] names,
--  NOT the bones those physics objects actually control.
--
--  CORRECT MAPPING:
--  ragdoll:TranslatePhysBoneToBone(physIndex)
--  returns the actual bone index that physIndex controls.
--  Use that bone index to look up the NPC's world matrix.
-- ============================================================

local FIND_RETRIES  = 60
local FIND_INTERVAL = 0.02

local function PoseRagdollFromNPC(ragdoll, npc)
    -- Build bone index -> world matrix from NPC
    local npcMatrix = {}
    for i = 0, npc:GetBoneCount() - 1 do
        local m = npc:GetBoneMatrix(i)
        if m then
            npcMatrix[i] = { pos = m:GetTranslation(), ang = m:GetAngles() }
        end
    end

    local count = ragdoll:GetPhysicsObjectCount()
    for i = 0, count - 1 do
        local phys = ragdoll:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            -- Translate physics object index to the actual bone it controls
            local boneIdx = ragdoll:TranslatePhysBoneToBone(i)
            local data    = boneIdx and npcMatrix[boneIdx]
            if data then
                phys:SetPos(data.pos)
                phys:SetAngles(data.ang)
                print(string.format("[GekkoDeath] phys[%d] -> bone[%d]='%s' snapped",
                    i, boneIdx, tostring(ragdoll:GetBoneName(boneIdx))))
            else
                print(string.format("[GekkoDeath] phys[%d] -> bone[%s] NO DATA",
                    i, tostring(boneIdx)))
            end
        end
    end

    -- Wake after all positions are set
    for i = 0, count - 1 do
        local phys = ragdoll:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            phys:EnableGravity(true)
            phys:EnableCollisions(true)
            phys:Wake()
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
