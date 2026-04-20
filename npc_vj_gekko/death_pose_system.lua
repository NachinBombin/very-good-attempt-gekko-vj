-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--
--  CORRECT APPROACH:
--  prop_ragdoll physics objects spawn ASLEEP. Calling
--  phys:SetPos / phys:SetAngles while they are asleep moves
--  the collider with zero impulse -- no spinning.
--  We must call them BEFORE phys:Wake().
--
--  Mapping: GetPhysicsObjectNum(i) on a prop_ragdoll corresponds
--  to bone index i. We match NPC bone -> ragdoll bone by name.
-- ============================================================

local FIND_RETRIES  = 60
local FIND_INTERVAL = 0.02

local function PoseRagdollFromNPC(ragdoll, npc)
    -- Build name -> world matrix lookup from the NPC
    local npcBones = {}
    for i = 0, npc:GetBoneCount() - 1 do
        local name = npc:GetBoneName(i)
        local m    = npc:GetBoneMatrix(i)
        if name and m then
            npcBones[name] = { pos = m:GetTranslation(), ang = m:GetAngles() }
        end
    end

    -- For each ragdoll physics object (asleep at this point),
    -- find its matching bone name and teleport it there
    local count = ragdoll:GetPhysicsObjectCount()
    for i = 0, count - 1 do
        local phys = ragdoll:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            local boneName = ragdoll:GetBoneName(i)
            local data     = boneName and npcBones[boneName]
            if data then
                -- Asleep = no impulse, pure teleport
                phys:SetPos(data.pos)
                phys:SetAngles(data.ang)
            end
        end
    end

    -- NOW wake everything so it falls naturally
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
            print("[GekkoDeath] posed ragdoll from NPC bones, attempt=" .. attempts)
            return
        end
        if attempts < FIND_RETRIES then
            timer.Simple(FIND_INTERVAL, TryPose)
        else
            print("[GekkoDeath] WARNING: corpse never found")
        end
    end

    -- timer.Simple(0) = end of this frame, ragdoll just spawned, physics still asleep
    timer.Simple(0, TryPose)
end

function ENT:GekkoDeath_Think()
end
