-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--
--  THE ACTUAL PROBLEM:
--  The ragdoll is a separate entity from the NPC. Its physics
--  objects spawn at positions defined by the .phy file, which
--  do NOT match the rendered mesh for this model -- legs end up
--  30+ units away from the pelvis.
--
--  THE FIX:
--  1. Before death: snapshot every bone's world pos+ang from
--     the live NPC (this is the correct rendered pose).
--  2. After the ragdoll spawns: for each ragdoll physics object,
--     find the matching bone by name, then call
--     phys:SetPos / phys:SetAngles to snap it to the snapshot.
--     This physically relocates the bone collider to where the
--     mesh already visually is.
-- ============================================================

local FIND_RETRIES  = 60
local FIND_INTERVAL = 0.05

-- ============================================================
--  Snapshot NPC bone world transforms
-- ============================================================
local function SnapshotBones(npc)
    local snapshot = {}
    local count = npc:GetBoneCount()
    if not count then return snapshot end
    for i = 0, count - 1 do
        local m = npc:GetBoneMatrix(i)
        if m then
            snapshot[i] = {
                pos = m:GetTranslation(),
                ang = m:GetAngles(),
                name = npc:GetBoneName(i),
            }
        end
    end
    return snapshot
end

-- ============================================================
--  Snap ragdoll physics objects to snapshot
-- ============================================================
local function SnapRagdollToSnapshot(ragdoll, snapshot)
    -- Build a name->data lookup from the snapshot
    local byName = {}
    for _, data in pairs(snapshot) do
        if data.name then
            byName[data.name] = data
        end
    end

    local count = ragdoll:GetPhysicsObjectCount()
    for i = 0, count - 1 do
        local phys = ragdoll:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            -- GetPhysicsObjectNum maps 1:1 with bone index on prop_ragdoll
            local boneName = ragdoll:GetBoneName(i)
            local data = boneName and byName[boneName]
            if data then
                phys:SetPos(data.pos)
                phys:SetAngles(data.ang)
            end
            -- Always make sure it collides and falls
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
    self._deathPoseActive  = false
    self._deathBoneSnapshot = nil
    self.HasDeathCorpse    = true
    self.DeathCorpseCollisionType = COLLISION_GROUP_NONE
end

function ENT:GekkoDeath_Trigger()
    if self._deathPoseActive then return end
    self._deathPoseActive = true

    -- Snapshot bones NOW while the NPC is still alive and posed
    self._deathBoneSnapshot = SnapshotBones(self)

    local selfRef  = self
    local snapshot = self._deathBoneSnapshot
    local attempts = 0

    local function TrySnap()
        attempts = attempts + 1
        local corpse = selfRef.Corpse
        if IsValid(corpse) then
            SnapRagdollToSnapshot(corpse, snapshot)
            print("[GekkoDeath] Ragdoll snapped to NPC bone snapshot (attempt " .. attempts .. ")")
            return
        end
        if attempts < FIND_RETRIES then
            timer.Simple(FIND_INTERVAL, TrySnap)
        else
            print("[GekkoDeath] WARNING: corpse never found, giving up")
        end
    end

    timer.Simple(0, TrySnap)
end

function ENT:GekkoDeath_Think()
end
