-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--
--  VJ Base spawns a prop_physics corpse automatically.
--  We fix its collision (VJ leaves it as DEBRIS/SOLID_NONE)
--  and set a high mass so it settles without being knocked away.
-- ============================================================

local CORPSE_MASS   = 50000
local FIND_RETRIES  = 40
local FIND_INTERVAL = 0.05

local function SetupCorpse(corpse)
    if not IsValid(corpse) then return end

    -- Restore full world + player collision
    corpse:SetCollisionGroup(COLLISION_GROUP_NONE)
    corpse:SetSolid(SOLID_VPHYSICS)
    corpse:PhysicsInit(SOLID_VPHYSICS)
    corpse:SetMoveType(MOVETYPE_VPHYSICS)

    for i = 0, corpse:GetPhysicsObjectCount() - 1 do
        local phys = corpse:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            phys:SetMass(CORPSE_MASS)
            phys:EnableGravity(true)
            phys:EnableCollisions(true)
            phys:Wake()
        end
    end

    print("[GekkoDeath] corpse collision restored, mass=" .. CORPSE_MASS)
end

-- ============================================================
--  Public API
-- ============================================================

function ENT:GekkoDeath_Init()
    self._deathPoseActive = false
    self.HasDeathCorpse           = true
    self.DeathCorpseEntityClass   = "prop_physics"
    self.DeathCorpseSetBoneAngles = false
    self.DeathCorpseApplyForce    = false
end

function ENT:GekkoDeath_Trigger()
    if self._deathPoseActive then return end
    self._deathPoseActive = true

    local selfRef  = self
    local attempts = 0

    local function TrySetup()
        attempts = attempts + 1
        local corpse = selfRef.Corpse
        if IsValid(corpse) then
            SetupCorpse(corpse)
            return
        end
        if attempts < FIND_RETRIES then
            timer.Simple(FIND_INTERVAL, TrySetup)
        else
            print("[GekkoDeath] WARNING: gave up finding Corpse after "
                .. attempts .. " attempts")
        end
    end

    timer.Simple(0, TrySetup)
end

function ENT:GekkoDeath_Think()
end
