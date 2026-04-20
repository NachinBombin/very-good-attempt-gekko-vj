-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--  Freezes the Gekko ragdoll corpse in place the moment
--  VJ Base creates it after death.
--
--  Approach: EnableMotion(false) + Sleep() on every physics
--  bone of self.Corpse, locking it in the death pose.
-- ============================================================

local FIND_RETRIES  = 20
local FIND_INTERVAL = 0.05

local function FreezeCorpse(corpse)
    if not IsValid(corpse) then return end
    for i = 0, corpse:GetPhysicsObjectCount() - 1 do
        local phys = corpse:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            phys:EnableMotion(false)
            phys:Sleep()
        end
    end
    print("[GekkoDeath] Corpse frozen: " .. tostring(corpse))
end

function ENT:GekkoDeath_Init()
    self._deathPoseActive = false
end

function ENT:GekkoDeath_Trigger()
    if self._deathPoseActive then return end
    self._deathPoseActive = true

    local selfRef  = self
    local attempts = 0

    local function TryFind()
        attempts = attempts + 1
        local corpse = selfRef.Corpse
        if IsValid(corpse) then
            FreezeCorpse(corpse)
            return
        end
        if attempts < FIND_RETRIES then
            timer.Simple(FIND_INTERVAL, TryFind)
        else
            print("[GekkoDeath] WARNING: gave up finding Corpse after "
                .. attempts .. " attempts")
        end
    end

    timer.Simple(0, TryFind)
end

function ENT:GekkoDeath_Think()
end
