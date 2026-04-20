-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--  Lets the ragdoll corpse settle under gravity, then freezes
--  it in place so it doesn't slide or despawn awkwardly.
-- ============================================================

local FIND_RETRIES   = 20
local FIND_INTERVAL  = 0.05
local SETTLE_TIME    = 1.8   -- seconds to let the ragdoll fall and land

local function FreezeCorpse(corpse)
    if not IsValid(corpse) then return end
    for i = 0, corpse:GetPhysicsObjectCount() - 1 do
        local phys = corpse:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            phys:EnableMotion(false)
            phys:Sleep()
        end
    end
    print("[GekkoDeath] Corpse frozen after settle.")
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
            -- Let it fall and settle first, then freeze
            timer.Simple(SETTLE_TIME, function()
                FreezeCorpse(corpse)
            end)
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
