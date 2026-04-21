-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--
--  FINDING: TranslatePhysBoneToBone works, all 8 bones snap.
--  REMAINING PROBLEM: VJ wakes physics before or right after
--  our timer.Simple(0) fires, so SetPos hits awake objects.
--
--  FIX: Once we find the corpse, disable motion, snap all bones,
--  then re-enable motion. DisableMotion before SetPos = pure
--  teleport with zero velocity carry-over.
-- ============================================================

local FIND_RETRIES  = 60
local FIND_INTERVAL = 0.02

local function SnapBones(ragdoll, npcMatrix)
    local count = ragdoll:GetPhysicsObjectCount()

    -- Disable motion on all physics objects first
    for i = 0, count - 1 do
        local phys = ragdoll:GetPhysicsObjectNum(i)
        if IsValid(phys) then phys:EnableMotion(false) end
    end

    -- Teleport each to NPC bone world position (no impulse while frozen)
    for i = 0, count - 1 do
        local phys    = ragdoll:GetPhysicsObjectNum(i)
        local boneIdx = ragdoll:TranslatePhysBoneToBone(i)
        local data    = boneIdx and npcMatrix[boneIdx]
        if IsValid(phys) and data then
            phys:SetPos(data.pos)
            phys:SetAngles(data.ang)
        end
    end

    -- Re-enable motion so ragdoll falls normally
    for i = 0, count - 1 do
        local phys = ragdoll:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            phys:EnableMotion(true)
            phys:EnableGravity(true)
            phys:EnableCollisions(true)
            phys:Wake()
        end
    end
end

local function BuildNPCMatrix(npc)
    local npcMatrix = {}
    for i = 0, npc:GetBoneCount() - 1 do
        local m = npc:GetBoneMatrix(i)
        if m then
            npcMatrix[i] = { pos = m:GetTranslation(), ang = m:GetAngles() }
        end
    end
    return npcMatrix
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

    -- Snapshot NPC bones NOW before the NPC is removed
    local npcMatrix = BuildNPCMatrix(self)
    local attempts  = 0

    local function TrySnap()
        attempts = attempts + 1
        local corpse = self.Corpse
        if IsValid(corpse) then
            SnapBones(corpse, npcMatrix)
            print("[GekkoDeath] snapped (attempt=" .. attempts .. ")")
            return
        end
        if attempts < FIND_RETRIES then
            timer.Simple(FIND_INTERVAL, TrySnap)
        else
            print("[GekkoDeath] WARNING: corpse never found")
        end
    end

    timer.Simple(0, TrySnap)
end

function ENT:GekkoDeath_Think()
end
