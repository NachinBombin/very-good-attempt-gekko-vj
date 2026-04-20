-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--
--  PROBLEM:
--  The ragdoll physics objects spawn displaced from the mesh
--  (legs 30+ units from pelvis). Calling phys:SetPos on already-
--  awake physics objects causes violent spinning.
--
--  CORRECT GMod API:
--  prop_ragdoll exposes a network message "BuildFromEntity" which
--  tells the ragdoll to re-read bone positions from a source
--  entity. We replicate the same thing in Lua by:
--    1. Freezing all physics objects immediately after spawn
--    2. Using entity:SetBoneAngles / SetBonePosition to push the
--       NPC's current bone pose onto the ragdoll entity
--    3. Calling RebuildBonePositions so the physics colliders
--       re-anchor to the (now correct) bone pose
--    4. Thawing physics so it falls normally
-- ============================================================

local FIND_RETRIES  = 60
local FIND_INTERVAL = 0.02

-- Freeze every physics object on the ragdoll
local function FreezeRagdoll(ragdoll)
    for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
        local phys = ragdoll:GetPhysicsObjectNum(i)
        if IsValid(phys) then phys:EnableMotion(false) end
    end
end

-- Thaw every physics object and wake them
local function ThawRagdoll(ragdoll)
    for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
        local phys = ragdoll:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            phys:EnableMotion(true)
            phys:EnableGravity(true)
            phys:EnableCollisions(true)
            phys:Wake()
        end
    end
end

-- Copy NPC bone pose onto the ragdoll then rebuild physics positions
local function PoseRagdollFromNPC(ragdoll, npc)
    -- Use the ragdoll's own bone count; both share the same skeleton
    local count = ragdoll:GetBoneCount()
    if not count then return end

    for i = 0, count - 1 do
        local m = npc:GetBoneMatrix(i)
        if m then
            ragdoll:SetBoneAngles(i, m:GetAngles())
            ragdoll:SetBonePosition(i, m:GetTranslation())
        end
    end

    -- RebuildBonePositions re-anchors physics colliders to the
    -- bone data we just wrote, while motion is still disabled
    if ragdoll.RebuildBonePositions then
        ragdoll:RebuildBonePositions()
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
            -- 1. Freeze so pose writes don't create impulses
            FreezeRagdoll(corpse)
            -- 2. Write NPC bone pose onto ragdoll
            PoseRagdollFromNPC(corpse, npcRef)
            -- 3. Thaw one frame later so engine settles first
            timer.Simple(0.05, function()
                if IsValid(corpse) then ThawRagdoll(corpse) end
            end)
            print("[GekkoDeath] Ragdoll posed from NPC bones (attempt " .. attempts .. ")")
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
