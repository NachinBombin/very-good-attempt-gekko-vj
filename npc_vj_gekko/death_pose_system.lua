-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--
--  Root cause: leg_disable_system.lua calls ManipulateBonePosition
--  and ManipulateBoneAngles every tick while legs are disabled.
--  VJ's ragdoll corpse inherits the NPC's current bone pose at
--  the moment of death, so those manipulations bake into the
--  ragdoll — legs appear disconnected from the body.
--
--  Fix: in GekkoDeath_Trigger, zero out ALL bone manipulations
--  on the NPC before the corpse entity is spawned by VJ.
--  We also set DeathCorpseCollisionType = COLLISION_GROUP_NONE
--  so the ragdoll collides with the world.
-- ============================================================

local BONE_MASS     = 50000
local FIND_RETRIES  = 40
local FIND_INTERVAL = 0.05

local ZERO_VEC = Vector(0, 0, 0)
local ZERO_ANG = Angle(0, 0, 0)

-- Zero every bone manipulation on the entity so the ragdoll
-- inherits a clean, unmodified skeleton.
local function ResetAllBoneManipulations(ent)
    local count = ent:GetBoneCount()
    if not count then return end
    for i = 0, count - 1 do
        ent:ManipulateBonePosition(i, ZERO_VEC)
        ent:ManipulateBoneAngles(i, ZERO_ANG)
        ent:ManipulateBoneScale(i, Vector(1, 1, 1))
    end
end

local function MakeHeavy(corpse)
    if not IsValid(corpse) then return end
    for i = 0, corpse:GetPhysicsObjectCount() - 1 do
        local phys = corpse:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            phys:SetMass(BONE_MASS)
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

    -- Stop leg_disable_system from re-applying manipulations
    self._gekkoLegsDisabled = false

    -- Clear all bone manipulations NOW, before VJ spawns the corpse
    -- (VJ spawns the corpse synchronously in the same death callback)
    ResetAllBoneManipulations(self)

    -- Poll for the corpse in case VJ spawns it slightly deferred
    local selfRef  = self
    local attempts = 0
    local function TryMakeHeavy()
        attempts = attempts + 1
        local corpse = selfRef.Corpse
        if IsValid(corpse) then
            MakeHeavy(corpse)
            return
        end
        if attempts < FIND_RETRIES then
            timer.Simple(FIND_INTERVAL, TryMakeHeavy)
        end
    end
    timer.Simple(0, TryMakeHeavy)
end

function ENT:GekkoDeath_Think()
end
