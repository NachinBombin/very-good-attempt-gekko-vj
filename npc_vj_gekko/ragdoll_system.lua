-- ============================================================
--  npc_vj_gekko / ragdoll_system.lua
--
--  Replaces the stiff death pose with a physically-simulated
--  heavy ragdoll.  Goals:
--
--    1. NO frozen pose / NO hip-piston gap.
--       All ManipulateBone* calls are wiped before the ragdoll
--       is created so every bone starts from the animation rest.
--
--    2. Heavy weight.  The whole body is dense metal so it
--       falls fast and thuds into geometry rather than floating.
--
--    3. Head collides with the world and gets oriented by it.
--       b_spine4 (the head/neck chain root) is given a strong
--       forward impulse so it whips down and settles against
--       whatever surface it contacts.
--
--    4. Legs stay connected to the pelvis.  The piston bones
--       (b_l_hippiston1 / b_r_hippiston1, indices 52 / 32)
--       are the joint roots for both legs.  We apply a small
--       outward impulse to each leg cluster so they splay
--       naturally rather than snapping to rest.
--
--    5. Death-velocity inheritance.  The NPC's velocity at the
--       moment of death is transferred to every ragdoll bone so
--       the body "carries" the hit momentum.
--
--  API
--    ENT:GekkoRagdoll_OnDeath(dmginfo)   -- call from OnDeath
-- ============================================================

-- ─────────────────────────────────────────────────────────────
--  Tuning
-- ─────────────────────────────────────────────────────────────
local RAGDOLL_FADE_TIME   = 30      -- seconds until the ragdoll fades
local RAGDOLL_FADE_START  = 26      -- seconds until fade animation begins

-- Per-bone mass overrides (kg).  Everything not listed falls
-- back to BASE_MASS.  Heavier = more inertia, slower tumble.
local BASE_MASS           = 180

local BONE_MASS = {
    -- torso stack
    b_pedestal  = 380,
    b_pelvis    = 320,
    b_spine1    = 220,
    b_spine2    = 200,
    b_spine3    = 180,
    b_spine4    = 160,   -- head/neck root
    -- legs (piston + thigh carry most weight)
    b_l_hippiston1      = 260,
    b_r_hippiston1      = 260,
    b_l_thigh           = 200,
    b_r_thigh           = 200,
    b_l_upperleg        = 160,
    b_r_upperleg        = 160,
    b_l_calf            = 120,
    b_r_calf            = 120,
    b_l_foot            = 80,
    b_r_foot            = 80,
    b_l_toe             = 30,
    b_r_toe             = 30,
    b_l_pinky_toe1      = 20,
    b_r_pinky_toe1      = 20,
    -- arms
    b_l_shoulder        = 100,
    b_r_shoulder        = 100,
    b_l_upperarm        = 90,
    b_r_upperarm        = 90,
    b_l_forearm         = 70,
    b_r_forearm         = 70,
    b_l_hand            = 40,
    b_r_hand            = 40,
}

-- Impulse applied to the head bone cluster (forward + down)
-- to make it whip into the ground on death.
local HEAD_BONE           = "b_spine4"
local HEAD_FORWARD_FORCE  = 28000   -- units/s  forward
local HEAD_DOWN_FORCE     = 18000   -- units/s  downward

-- Hip-piston bones — small outward splay so legs don't
-- collapse inward and create the gap artifact.
local HIP_L_BONE          = "b_l_hippiston1"
local HIP_R_BONE          = "b_r_hippiston1"
local HIP_SPLAY_FORCE     = 9000    -- lateral outward
local HIP_DOWN_FORCE      = 4000    -- slight downward

-- Overall death impulse scale applied to the whole body
-- from the damage force direction.
local DEATH_IMPULSE_SCALE = 1.4

-- Damping: ragdoll bones are made slightly sluggish so the
-- body doesn't bounce around like a balloon.
local ANGULAR_DAMPING     = 2.8
local LINEAR_DAMPING      = 0.6

-- ─────────────────────────────────────────────────────────────
--  Internal helpers
-- ─────────────────────────────────────────────────────────────

-- Strip every bone manipulation on the NPC before we hand the
-- pose to CreateRagdoll().  Without this the ragdoll inherits
-- whatever ManipulateBoneAngles / ManipulateBonePosition offsets
-- were active (e.g. the grounded-pose pelvis drop of -125 units)
-- which is exactly what causes the hip-piston gap.
-- NOTE: InvalidateBoneCache() is a clientside-only method and
-- must NOT be called on a serverside NPC.  WipeAllBoneManips
-- alone is sufficient; the engine re-evaluates bone transforms
-- when CreateRagdoll reads the pose on the next frame.
local function WipeAllBoneManips(ent)
    local count = ent:GetBoneCount()
    if not count then return end
    for i = 0, count - 1 do
        ent:ManipulateBoneAngles(i,   Angle(0,0,0),    false)
        ent:ManipulateBonePosition(i, Vector(0,0,0),   false)
        ent:ManipulateBoneScale(i,    Vector(1,1,1),   false)
    end
end

-- Apply per-bone mass and damping to every physics object inside
-- the ragdoll entity.
local function ConfigureRagdollPhysics(ragdoll)
    local boneCount = ragdoll:GetPhysicsObjectCount()
    for i = 0, boneCount - 1 do
        local phys = ragdoll:GetPhysicsObjectNum(i)
        if not IsValid(phys) then continue end

        -- Resolve bone name for this physics index
        local boneName = ragdoll:GetBoneName(i) or ""
        local mass     = BONE_MASS[boneName] or BASE_MASS

        phys:SetMass(mass)
        phys:SetDamping(LINEAR_DAMPING, ANGULAR_DAMPING)
        phys:EnableGravity(true)
        phys:EnableDrag(false)   -- no air resistance; we want a heavy thud
        phys:Wake()
    end
end

-- Translate a bone name to its physics object index inside a
-- ragdoll.  Ragdoll physics objects are numbered 0..N-1 and
-- their order matches the bone index sequence but only for
-- bones that have a $collisionmodel entry -- we search by name.
local function FindRagdollPhysByBone(ragdoll, boneName)
    local count = ragdoll:GetPhysicsObjectCount()
    for i = 0, count - 1 do
        if (ragdoll:GetBoneName(i) or "") == boneName then
            return ragdoll:GetPhysicsObjectNum(i)
        end
    end
    return nil
end

-- Apply an impulse to a named bone's physics object.
-- impulseVec is in world-space kg*units/s.
local function ApplyBoneImpulse(ragdoll, boneName, impulseVec)
    local phys = FindRagdollPhysByBone(ragdoll, boneName)
    if IsValid(phys) then
        phys:ApplyForceCenter(impulseVec)
    end
end

-- ─────────────────────────────────────────────────────────────
--  ENT:GekkoRagdoll_OnDeath
-- ─────────────────────────────────────────────────────────────
function ENT:GekkoRagdoll_OnDeath(dmginfo)

    -- ── 1. Capture live state before we touch anything ────────
    local deathPos = self:GetPos()
    local deathAng = self:GetAngles()
    local deathVel = self:GetVelocity()

    -- Damage force direction (used for the whole-body push)
    local dmgForce   = dmginfo and dmginfo:GetDamageForce() or Vector(0,0,0)
    local dmgForceN  = (dmgForce:Length() > 1) and dmgForce:GetNormalized() or Vector(0,0,1)

    -- Forward direction of the NPC at death
    local fwd        = deathAng:Forward()
    local right      = deathAng:Right()

    -- ── 2. Wipe all bone overrides ────────────────────────────
    -- This is the critical fix for the hip-piston gap.  Any
    -- ManipulateBone* state (pelvis Z offset, piston angles from
    -- attacks, grounded pose) must be zeroed BEFORE CreateRagdoll
    -- so the ragdoll spawns from the model's neutral bind pose.
    WipeAllBoneManips(self)

    -- NOTE: Do NOT call self:InvalidateBoneCache() here.
    -- That method only exists on clientside entities.  The bone
    -- wipe above is sufficient; the engine re-reads poses when
    -- prop_ragdoll initialises on the next frame (timer 0).

    local selfRef    = self
    local deathPosCp = deathPos
    local deathAngCp = deathAng
    local deathVelCp = deathVel
    local dmgForceNCp= dmgForceN
    local fwdCp      = fwd
    local rightCp    = right

    timer.Simple(0, function()
        if not IsValid(selfRef) then return end

        -- ── 3. Create the ragdoll ─────────────────────────────
        local ragdoll = ents.Create("prop_ragdoll")
        if not IsValid(ragdoll) then
            print("[GekkoRagdoll] ERROR: prop_ragdoll create failed")
            return
        end

        ragdoll:SetModel(selfRef:GetModel())
        ragdoll:SetPos(deathPosCp)
        ragdoll:SetAngles(deathAngCp)
        ragdoll:SetSkin(selfRef:GetSkin())

        -- Copy bodygroups
        for bg = 0, selfRef:GetNumBodyGroups() - 1 do
            ragdoll:SetBodygroup(bg, selfRef:GetBodygroup(bg))
        end

        ragdoll:Spawn()
        ragdoll:Activate()

        -- ── 4. Configure physics ─────────────────────────────
        ConfigureRagdollPhysics(ragdoll)

        -- ── 5. Inherit NPC velocity on every bone ────────────
        local physCount  = ragdoll:GetPhysicsObjectCount()
        for i = 0, physCount - 1 do
            local phys = ragdoll:GetPhysicsObjectNum(i)
            if IsValid(phys) then
                phys:SetVelocity(deathVelCp)
                phys:ApplyForceCenter(
                    dmgForceNCp * (BASE_MASS * 12000 * DEATH_IMPULSE_SCALE)
                )
            end
        end

        -- ── 6. Head whip impulse ──────────────────────────────
        ApplyBoneImpulse(ragdoll, HEAD_BONE,
            fwdCp  * HEAD_FORWARD_FORCE * BASE_MASS
          + Vector(0, 0, -1) * HEAD_DOWN_FORCE * BASE_MASS
        )

        -- ── 7. Hip splay impulse ──────────────────────────────
        ApplyBoneImpulse(ragdoll, HIP_L_BONE,
             rightCp * HIP_SPLAY_FORCE * BASE_MASS
           + Vector(0, 0, -1) * HIP_DOWN_FORCE * BASE_MASS
        )
        ApplyBoneImpulse(ragdoll, HIP_R_BONE,
            -rightCp * HIP_SPLAY_FORCE * BASE_MASS
           + Vector(0, 0, -1) * HIP_DOWN_FORCE * BASE_MASS
        )

        -- ── 8. Fade & cleanup ────────────────────────────────
        timer.Simple(RAGDOLL_FADE_START, function()
            if not IsValid(ragdoll) then return end
            local fadeLen = RAGDOLL_FADE_TIME - RAGDOLL_FADE_START
            local startT  = CurTime()
            local hookKey = "GekkoRagdollFade_" .. ragdoll:EntIndex()
            hook.Add("Think", hookKey, function()
                if not IsValid(ragdoll) then
                    hook.Remove("Think", hookKey)
                    return
                end
                local t = math.Clamp((CurTime() - startT) / fadeLen, 0, 1)
                local a = math.floor(255 * (1 - t))
                ragdoll:SetColor(Color(255, 255, 255, a))
                ragdoll:SetRenderMode(RENDERMODE_TRANSALPHA)
                if t >= 1 then
                    ragdoll:Remove()
                    hook.Remove("Think", hookKey)
                end
            end)
        end)

        timer.Simple(RAGDOLL_FADE_TIME, function()
            if IsValid(ragdoll) then ragdoll:Remove() end
        end)

        print(string.format(
            "[GekkoRagdoll] Spawned | physBones=%d vel=%.1f",
            physCount, deathVelCp:Length()
        ))
    end)
end
