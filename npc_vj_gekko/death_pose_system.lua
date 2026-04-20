-- ============================================================
--  death_pose_system.lua
--  Freezes the Gekko ragdoll corpse in place the moment it spawns.
--  Called from init.lua OnDeath("Finish").
-- ============================================================

-- How long (seconds) before the frozen corpse is removed.
local CORPSE_LIFETIME = 30

-- How many times to retry finding self.Corpse (VJ Base spawns it async)
local FIND_RETRIES    = 10
local FIND_INTERVAL   = 0.05

local function FreezeCorpse( corpse )
    if not IsValid(corpse) then return end

    -- Freeze every physics bone so the ragdoll can't move at all.
    for i = 0, corpse:GetPhysicsObjectCount() - 1 do
        local phys = corpse:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            phys:EnableMotion(false)
            phys:Sleep()
        end
    end

    print("[GekkoDeath] Corpse frozen: " .. tostring(corpse))

    -- Clean up after CORPSE_LIFETIME seconds.
    timer.Simple(CORPSE_LIFETIME, function()
        if IsValid(corpse) then
            corpse:Remove()
        end
    end)
end

function ENT:GekkoDeath_FreezeCorpse()
    local self_ref = self
    local attempts = 0

    local function TryFreeze()
        attempts = attempts + 1

        local corpse = self_ref.Corpse
        if IsValid(corpse) then
            FreezeCorpse(corpse)
            return
        end

        if attempts < FIND_RETRIES then
            timer.Simple(FIND_INTERVAL, TryFreeze)
        else
            print("[GekkoDeath] WARNING: could not find corpse after " .. attempts .. " attempts")
        end
    end

    -- First attempt immediately (next tick)
    timer.Simple(0, TryFreeze)
end
