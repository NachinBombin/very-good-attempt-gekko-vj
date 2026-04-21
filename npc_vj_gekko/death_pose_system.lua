-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--
--  On death: spawn a prop_ragdoll using models/mgr/gekko.mdl
--  and ignite it so the colour difference is never noticed.
-- ============================================================

local RAGDOLL_MODEL = "models/mgr/gekko.mdl"
local FIRE_DURATION = 12
local FIRE_SCALE    = 1.2

-- Dark brown, ~40% opacity (102/255 = 0.4)
local RAGDOLL_TINT  = Color(101, 67, 33, 102)

if SERVER then
    util.PrecacheModel(RAGDOLL_MODEL)
end

function ENT:GekkoDeath_Init()
    -- no runtime init needed
end

function ENT:GekkoDeath_SpawnRagdoll()
    local pos = self:GetPos()
    local ang = self:GetAngles()
    local vel = self:GetVelocity()

    local rag = ents.Create("prop_ragdoll")
    if not IsValid(rag) then
        print("[GekkoDeath] ERROR: prop_ragdoll create failed")
        return nil
    end

    rag:SetModel(RAGDOLL_MODEL)
    rag:SetPos(pos)
    rag:SetAngles(ang)
    rag:Spawn()
    rag:Activate()

    rag:SetColor(RAGDOLL_TINT)

    for i = 0, rag:GetPhysicsObjectCount() - 1 do
        local phys = rag:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            phys:SetVelocity(vel)
            phys:Wake()
        end
    end

    rag:Ignite(FIRE_DURATION, FIRE_SCALE)
    print("[GekkoDeath] Ragdoll spawned + tinted + ignited at " .. tostring(pos))
    return rag
end
