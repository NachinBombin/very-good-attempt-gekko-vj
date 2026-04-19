-- ============================================================
--  npc_vj_gekko / death_ragdoll_system.lua
--
--  Problem being solved
--  --------------------
--  The Gekko model has procedurally driven bones (hip pistons,
--  pelvis offset, etc.) that are animated every frame via
--  ManipulateBoneAngles / ManipulateBonePosition in cl_init.lua.
--  When VJ Base ragdolls the NPC at death it:
--    1. Stops all think hooks  -> bone manipulation stops
--    2. Creates a prop_ragdoll -> model reverts to rest-pose defaults
--  The hip pistons have extreme rest-pose offsets, so they fly
--  apart.  The ragdoll mass also defaults too low, causing the
--  body to bounce instead of crashing like a heavy robot.
--
--  Solution
--  --------
--  GekkoSpawnDeathRagdoll() is called from OnDeath (init.lua,
--  server side) the moment the death callback fires.  It:
--    1. Reads every bone's current world-space matrix from the
--       LIVE NPC (still fully posed at this point).
--    2. Spawns a prop_ragdoll at the NPC's position.
--    3. Copies those world matrices into the ragdoll before its
--       physics wake up, so each bone starts in exactly the pose
--       the player last saw.
--    4. Sets high mass on every physics bone so the body falls
--       with convincing robot weight.
--    5. Applies the NPC's death velocity as an impulse so the
--       body continues moving in the direction it was hit.
--    6. Hides / freezes the NPC entity so there is no overlap.
--
--  The client-side cl_init.lua Think hook has a matching guard
--  that captures the last manipulated bone state on the first
--  dead frame and re-applies it every subsequent frame until
--  the entity is removed, preventing any snapshot gap.
-- ============================================================

-- Total mass distributed across all physics bones.
-- 4800 ~= a plausible multi-tonne mech; gives satisfying thud.
local RAGDOLL_TOTAL_MASS   = 4800

-- Fraction of the NPC's current velocity applied as an initial
-- impulse to the ragdoll's root physics bone (0-1).
local DEATH_VELOCITY_SCALE = 0.6

-- Bone indices confirmed from in-game bone list (72 bones total).
-- Only valid (non-__INVALIDBONE__) bones are listed.
local VALID_BONE_INDICES = {
     0,  -- b_pedestal
     1,  -- b_pelvis
     2,  -- b_spine1
     3,  -- b_spine2
     4,  -- b_spine3
     5,  -- b_spine4
     6,  -- b_l_shoulder
     7,  -- b_l_upperarm
     8,  -- b_l_upperarm_piston2
     9,  -- b_l_forearm
    10,  -- b_l_wrist_twist
    11,  -- b_l_hand
    12,  -- b_l_gunrack
    18,  -- b_lowerhatch
    19,  -- b_r_shoulder
    20,  -- b_r_upperarm
    21,  -- b_r_upperarm_piston2
    22,  -- b_r_forearm
    23,  -- b_r_wrist_twist
    24,  -- b_r_hand
    25,  -- b_r_gunrack
    29,  -- b_upperhatch
    30,  -- b_frontcover
    32,  -- b_r_hippiston1   <- critical: flies apart without this
    33,  -- b_r_thigh
    34,  -- b_r_upperleg
    35,  -- b_r_calf
    40,  -- b_r_foot
    41,  -- b_r_pinky_toe1
    42,  -- b_r_toe
    52,  -- b_l_hippiston1   <- critical: flies apart without this
    53,  -- b_l_thigh
    54,  -- b_l_upperleg
    56,  -- b_l_calf
    61,  -- b_l_foot
    62,  -- b_l_toe
    67,  -- b_l_pinky_toe1
}

-- ============================================================
--  GekkoSpawnDeathRagdoll  (server-only)
-- ============================================================
function GekkoSpawnDeathRagdoll(npc, dmginfo)
    if not IsValid(npc) then return end

    -- 1. Snapshot world-space bone matrices from the live NPC.
    --    SetupBones() forces an up-to-date bone solve so we get the
    --    exact pose the player sees, including all procedural offsets.
    npc:SetupBones()

    local boneMatrices = {}
    for _, idx in ipairs(VALID_BONE_INDICES) do
        local m = npc:GetBoneMatrix(idx)
        if m then
            boneMatrices[idx] = m
        end
    end

    local npcPos = npc:GetPos()
    local npcAng = npc:GetAngles()
    local npcVel = npc:GetVelocity()

    -- 2. Spawn ragdoll.
    local ragdoll = ents.Create("prop_ragdoll")
    if not IsValid(ragdoll) then return end

    ragdoll:SetModel(npc:GetModel())
    ragdoll:SetPos(npcPos)
    ragdoll:SetAngles(npcAng)
    ragdoll:SetSkin(npc:GetSkin())
    ragdoll:Spawn()
    ragdoll:Activate()

    -- 3. Copy bone matrices into ragdoll physics objects before Wake().
    --    We match each physobj to the nearest snapshotted bone by
    --    world-position proximity (threshold 80 units).
    local physCount = ragdoll:GetPhysicsObjectCount()

    for i = 0, physCount - 1 do
        local physObj = ragdoll:GetPhysicsObjectNum(i)
        if IsValid(physObj) then
            local physPos  = physObj:GetPos()
            local bestIdx  = nil
            local bestDist = 6400  -- 80^2 units max match distance

            for _, boneIdx in ipairs(VALID_BONE_INDICES) do
                local m = boneMatrices[boneIdx]
                if m then
                    local d = physPos:DistToSqr(m:GetTranslation())
                    if d < bestDist then
                        bestDist = d
                        bestIdx  = boneIdx
                    end
                end
            end

            if bestIdx then
                local m = boneMatrices[bestIdx]
                physObj:SetPos(m:GetTranslation())
                physObj:SetAngles(m:GetAngles())
            end
        end
    end

    -- 4. Set heavy mass and apply death impulse.
    local massPerBone = RAGDOLL_TOTAL_MASS / math.max(physCount, 1)

    for i = 0, physCount - 1 do
        local physObj = ragdoll:GetPhysicsObjectNum(i)
        if IsValid(physObj) then
            physObj:SetMass(massPerBone)
            physObj:EnableGravity(true)
            physObj:EnableDrag(true)

            -- Apply velocity impulse only to root bone so the body
            -- moves as a unit rather than exploding outward.
            if i == 0 then
                local impulse = npcVel * DEATH_VELOCITY_SCALE * massPerBone
                if dmginfo then
                    local dmgForce = dmginfo:GetDamageForce()
                    if dmgForce:LengthSqr() > 1 then
                        impulse = impulse + dmgForce:GetNormalized() * (massPerBone * 80)
                    end
                end
                physObj:ApplyForceCenter(impulse)
            end

            physObj:Wake()
        end
    end

    -- 5. Hide the NPC to prevent Z-fighting until VJ removes it.
    npc:SetNoDraw(true)
    npc:SetNotSolid(true)

    -- Auto-remove ragdoll after 30 s to avoid prop accumulation.
    local ragRef = ragdoll
    timer.Simple(30, function()
        if IsValid(ragRef) then ragRef:Remove() end
    end)
end
