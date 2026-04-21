-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--
--  On death: hide the NPC instantly, spawn a prop_ragdoll using
--  models/mgr/gekko.mdl (bipedal Valve skeleton, physics work),
--  ignite it so the colour difference is never noticed.
-- ============================================================

local RAGDOLL_MODEL   = "models/mgr/gekko.mdl"
local FIRE_DURATION   = 12   -- seconds the ragdoll burns
local FIRE_SCALE      = 1.2  -- flame scale passed to Ignite()

if SERVER then
    util.PrecacheModel(RAGDOLL_MODEL)
end

-- ============================================================
--  Public API  (called from OnDeath in init.lua)
-- ============================================================

function ENT:GekkoDeath_Init()
    -- nothing to initialise anymore
    self.HasDeathCorpse = false   -- stop VJ spawning its own ragdoll
end

function ENT:GekkoDeath_Trigger(attacker, dmginfo)
    local pos = self:GetPos()
    local ang = self:GetAngles()
    local vel = self:GetVelocity()

    -- Hide the real NPC body immediately so it can die cleanly
    self:SetNoDraw(true)
    self:SetNotSolid(true)

    -- Spawn ragdoll with the working model
    local rag = ents.Create("prop_ragdoll")
    if not IsValid(rag) then
        print("[GekkoDeath] ERROR: prop_ragdoll create failed")
        return
    end
    rag:SetModel(RAGDOLL_MODEL)
    rag:SetPos(pos)
    rag:SetAngles(ang)
    rag:Spawn()
    rag:Activate()

    -- Give it the NPC's momentum so it doesn't just drop straight down
    for i = 0, rag:GetPhysicsObjectCount() - 1 do
        local phys = rag:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            phys:SetVelocity(vel)
            phys:Wake()
        end
    end

    -- Ignite — covers the green tint entirely
    rag:Ignite(FIRE_DURATION, FIRE_SCALE)

    print("[GekkoDeath] Ragdoll spawned + ignited at " .. tostring(pos))
end
