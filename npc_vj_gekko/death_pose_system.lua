-- DIAGNOSTIC BUILD - read console after killing Gekko

local FIND_RETRIES  = 60
local FIND_INTERVAL = 0.02

local function DiagnosePoseRagdoll(ragdoll, npc)
    print("[GekkoDeath DIAG] physCount=" .. tostring(ragdoll:GetPhysicsObjectCount())
        .. " ragdollBones=" .. tostring(ragdoll:GetBoneCount())
        .. " npcBones=" .. tostring(npc:GetBoneCount()))

    -- Dump all NPC bone names
    print("[GekkoDeath DIAG] --- NPC BONES ---")
    for i = 0, npc:GetBoneCount() - 1 do
        print(string.format("  npc[%d] = '%s'", i, tostring(npc:GetBoneName(i))))
    end

    -- Dump all ragdoll bone names
    print("[GekkoDeath DIAG] --- RAGDOLL BONES ---")
    for i = 0, ragdoll:GetBoneCount() - 1 do
        print(string.format("  rag[%d] = '%s'", i, tostring(ragdoll:GetBoneName(i))))
    end

    -- Dump ragdoll physics objects and their positions
    print("[GekkoDeath DIAG] --- RAGDOLL PHYSICS OBJECTS ---")
    for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
        local phys = ragdoll:GetPhysicsObjectNum(i)
        local valid = IsValid(phys) and "valid" or "INVALID"
        local pos   = IsValid(phys) and tostring(phys:GetPos()) or "N/A"
        print(string.format("  phys[%d] bone='%s' valid=%s pos=%s",
            i, tostring(ragdoll:GetBoneName(i)), valid, pos))
    end

    print("[GekkoDeath DIAG] === END ===")
end

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
            DiagnosePoseRagdoll(corpse, npcRef)
            return
        end
        if attempts < FIND_RETRIES then
            timer.Simple(FIND_INTERVAL, TryPose)
        else
            print("[GekkoDeath] WARNING: corpse never found after " .. attempts .. " attempts")
        end
    end

    timer.Simple(0, TryPose)
end

function ENT:GekkoDeath_Think()
end
