-- ============================================================
--  npc_vj_gekko / death_pose_system.lua  -- DIAGNOSTIC BUILD
--  Check console output after death to see:
--    - How many physics objects the ragdoll has
--    - Each ragdoll bone name and whether it matched an NPC bone
--    - Whether each physics object was asleep when we reached it
--    - Whether SetPos actually moved it (compare before/after)
-- ============================================================

local FIND_RETRIES  = 60
local FIND_INTERVAL = 0.02

local function DiagnosePoseRagdoll(ragdoll, npc)
    print("[GekkoDeath DIAG] === RAGDOLL BONE DIAGNOSTIC ===")
    print("[GekkoDeath DIAG] ragdoll:GetPhysicsObjectCount() = " .. tostring(ragdoll:GetPhysicsObjectCount()))
    print("[GekkoDeath DIAG] ragdoll:GetBoneCount()          = " .. tostring(ragdoll:GetBoneCount()))
    print("[GekkoDeath DIAG] npc:GetBoneCount()              = " .. tostring(npc:GetBoneCount()))
    print("[GekkoDeath DIAG] ---")

    -- Build NPC bone name -> world matrix
    local npcBones = {}
    for i = 0, npc:GetBoneCount() - 1 do
        local name = npc:GetBoneName(i)
        local m    = npc:GetBoneMatrix(i)
        if name and m then
            npcBones[name] = { pos = m:GetTranslation(), ang = m:GetAngles() }
        end
    end

    -- Dump every ragdoll physics bone
    local count = ragdoll:GetPhysicsObjectCount()
    for i = 0, count - 1 do
        local phys     = ragdoll:GetPhysicsObjectNum(i)
        local boneName = ragdoll:GetBoneName(i)
        local matched  = boneName and npcBones[boneName] and "YES" or "NO MATCH"
        local asleep   = IsValid(phys) and (not phys:IsMoving()) and "asleep" or "AWAKE/invalid"
        local posBefore = IsValid(phys) and tostring(phys:GetPos()) or "N/A"

        if IsValid(phys) and npcBones[boneName] then
            phys:SetPos(npcBones[boneName].pos)
            phys:SetAngles(npcBones[boneName].ang)
        end

        local posAfter = IsValid(phys) and tostring(phys:GetPos()) or "N/A"

        print(string.format(
            "[GekkoDeath DIAG] physObj[%d] bone='%s' match=%s state=%s posBefore=%s posAfter=%s",
            i, tostring(boneName), matched, asleep, posBefore, posAfter
        ))
    end

    -- Wake after all positions set
    for i = 0, count - 1 do
        local phys = ragdoll:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            phys:EnableGravity(true)
            phys:EnableCollisions(true)
            phys:Wake()
        end
    end

    print("[GekkoDeath DIAG] === END DIAGNOSTIC ===")
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
