-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--
--  Instead of suppressing VJ Base's corpse (which causes the
--  NPC to instantly disappear), we let VJ spawn it normally
--  but configure it to use prop_physics instead of prop_ragdoll.
--
--  VJ Base reads these vars at death time:
--    self.HasDeathCorpse          = true   (keep VJ's flow intact)
--    self.DeathCorpseEntityClass  = "prop_physics" (not a ragdoll)
--    self.DeathCorpseSetBoneAngles = false  (no bone angle copy)
--    self.DeathCorpseApplyForce   = false   (don't throw it)
--
--  Then in GekkoDeath_Trigger we find self.Corpse (which VJ
--  already spawned as a prop_physics) and freeze it.
-- ============================================================

local FIND_RETRIES  = 40
local FIND_INTERVAL = 0.05

-- Freeze every physics bone on a prop_physics (works reliably,
-- unlike prop_ragdoll where EnableMotion(false) is ignored).
local function FreezeCorpse(corpse)
    if not IsValid(corpse) then return end
    for i = 0, corpse:GetPhysicsObjectCount() - 1 do
        local phys = corpse:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            phys:SetVelocity(Vector(0, 0, 0))
            phys:SetAngleVelocity(Vector(0, 0, 0))
            phys:EnableMotion(false)  -- works on prop_physics
            phys:Sleep()
        end
    end
    print("[GekkoDeath] prop_physics corpse frozen.")
end

-- ============================================================
--  Public API
-- ============================================================

function ENT:GekkoDeath_Init()
    self._deathPoseActive = false

    -- Tell VJ Base to spawn a prop_physics corpse instead of
    -- a prop_ragdoll. VJ will still handle timing, blood pools,
    -- etc. -- we just freeze it immediately after it appears.
    self.HasDeathCorpse         = true          -- keep VJ's corpse flow
    self.DeathCorpseEntityClass = "prop_physics" -- spawn as static prop
    self.DeathCorpseSetBoneAngles = false        -- no ragdoll bone copy
    self.DeathCorpseApplyForce  = false          -- don't throw the prop
end

function ENT:GekkoDeath_Trigger()
    if self._deathPoseActive then return end
    self._deathPoseActive = true

    local selfRef  = self
    local attempts = 0

    local function TryFreeze()
        attempts = attempts + 1
        local corpse = selfRef.Corpse
        if IsValid(corpse) then
            FreezeCorpse(corpse)
            return
        end
        if attempts < FIND_RETRIES then
            timer.Simple(FIND_INTERVAL, TryFreeze)
        else
            print("[GekkoDeath] WARNING: gave up finding Corpse after "
                .. attempts .. " attempts")
        end
    end

    timer.Simple(0, TryFreeze)
end

function ENT:GekkoDeath_Think()
    -- Nothing needed; prop_physics holds itself once frozen.
end
