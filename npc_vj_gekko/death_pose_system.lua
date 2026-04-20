-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--
--  VJ Base spawns a prop_physics corpse automatically.
--  We just wait for it to appear and set its mass very high
--  so it sinks/settles naturally without getting knocked around.
--  No freezing, no motion disable -- full physics, just heavy.
-- ============================================================

local CORPSE_MASS   = 50000   -- kg, heavy enough to resist explosions
local FIND_RETRIES  = 40
local FIND_INTERVAL = 0.05

local function MakeHeavy(corpse)
    if not IsValid(corpse) then return end
    for i = 0, corpse:GetPhysicsObjectCount() - 1 do
        local phys = corpse:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            phys:SetMass(CORPSE_MASS)
            phys:EnableGravity(true)
            phys:Wake()
        end
    end
    print("[GekkoDeath] corpse mass set to " .. CORPSE_MASS)
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
            print("[GekkoDeath] WARNING: gave up finding Corpse after "
                .. attempts .. " attempts")
        end
    end

    timer.Simple(0, TryMakeHeavy)
end

function ENT:GekkoDeath_Think()
end
