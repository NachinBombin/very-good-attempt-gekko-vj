-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--
--  VJ calls ent:SetCollisionGroup(self.DeathCorpseCollisionType)
--  on every corpse it spawns (core.lua CreateExtraDeathCorpse).
--  The default value causes the ragdoll to phase through ground.
--
--  Fix: set DeathCorpseCollisionType = COLLISION_GROUP_NONE
--  before death so VJ's own corpse spawner uses full collision.
--  Then in GekkoDeath_Trigger we also crank up mass on every
--  bone so the ragdoll sinks and isn't thrown by explosions.
-- ============================================================

local BONE_MASS     = 50000
local FIND_RETRIES  = 40
local FIND_INTERVAL = 0.05

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
    print("[GekkoDeath] ragdoll mass set, bone_mass=" .. BONE_MASS)
end

-- ============================================================
--  Public API
-- ============================================================

function ENT:GekkoDeath_Init()
    self._deathPoseActive = false
    self.HasDeathCorpse   = true  -- let VJ spawn the ragdoll
    -- This is the variable VJ reads when setting collision on
    -- the corpse entity (see core.lua:CreateExtraDeathCorpse)
    self.DeathCorpseCollisionType = COLLISION_GROUP_NONE
end

function ENT:GekkoDeath_Trigger()
    if self._deathPoseActive then return end
    self._deathPoseActive = true

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
        else
            print("[GekkoDeath] WARNING: corpse not found after " .. attempts .. " attempts")
        end
    end

    timer.Simple(0, TryMakeHeavy)
end

function ENT:GekkoDeath_Think()
end
