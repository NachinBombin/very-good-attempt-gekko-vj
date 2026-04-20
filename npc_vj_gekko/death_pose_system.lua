-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--
--  Suppresses VJ Base's default ragdoll entirely.
--  On death, spawns a prop_physics with the Gekko model,
--  copies over the NPC's current position/angle, and
--  freezes ALL physics objects immediately so it never moves.
-- ============================================================

-- How long to wait after death before spawning the frozen prop.
-- A tiny delay ensures the NPC's death animation pose has
-- had one frame to settle before we read its position/angle.
local SPAWN_DELAY = 0.05

-- ────────────────────────────────────────────────────────────
--  Internal helper: create and freeze the static death prop
-- ────────────────────────────────────────────────────────────
local function SpawnFrozenCorpse(npc)
    if not IsValid(npc) then return end

    local mdl = npc:GetModel()
    local pos = npc:GetPos()
    local ang = npc:GetAngles()

    local prop = ents.Create("prop_physics")
    if not IsValid(prop) then
        print("[GekkoDeath] ERROR: failed to create prop_physics")
        return
    end

    prop:SetModel(mdl)
    prop:SetPos(pos)
    prop:SetAngles(ang)
    prop:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    prop:Spawn()
    prop:Activate()

    -- Copy skin/bodygroups so the corpse matches the NPC
    prop:SetSkin(npc:GetSkin())
    for bg = 0, npc:GetNumBodyGroups() - 1 do
        prop:SetBodygroup(bg, npc:GetBodygroup(bg))
    end

    -- Freeze every physics bone immediately
    for i = 0, prop:GetPhysicsObjectCount() - 1 do
        local phys = prop:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            phys:SetVelocity(Vector(0, 0, 0))
            phys:SetAngleVelocity(Vector(0, 0, 0))
            phys:EnableMotion(false)  -- works on prop_physics (not ragdolls)
            phys:Sleep()
        end
    end

    -- Keep a reference on the NPC table for external systems
    npc.GekkoFrozenCorpse = prop

    print("[GekkoDeath] Frozen prop_physics corpse spawned.")
end

-- ────────────────────────────────────────────────────────────
--  Public API called from init.lua
-- ────────────────────────────────────────────────────────────

function ENT:GekkoDeath_Init()
    self._deathPoseActive = false

    -- Tell VJ Base NOT to spawn its own ragdoll/corpse.
    -- This is the documented way to suppress corpse creation.
    self.HasDeathCorpse = false
end

function ENT:GekkoDeath_Trigger()
    if self._deathPoseActive then return end
    self._deathPoseActive = true

    local selfRef = self
    timer.Simple(SPAWN_DELAY, function()
        SpawnFrozenCorpse(selfRef)
    end)
end

function ENT:GekkoDeath_Think()
    -- Nothing needed; prop_physics holds itself frozen.
end
