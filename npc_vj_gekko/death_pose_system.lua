-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--
--  VJ Base's own ragdoll spawning is the only thing that
--  correctly sets bone poses. We must not suppress it.
--
--  All we do: wait for self.Corpse to appear (VJ sets it),
--  then crank up the mass on every bone so the ragdoll
--  sinks to the ground and resists explosions.
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
    print("[GekkoDeath] VJ ragdoll mass set to " .. BONE_MASS .. " per bone")
end

-- ============================================================
--  Public API
-- ============================================================

function ENT:GekkoDeath_Init()
    self._deathPoseActive = false
    -- Let VJ spawn its own ragdoll corpse normally
    self.HasDeathCorpse = true
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
