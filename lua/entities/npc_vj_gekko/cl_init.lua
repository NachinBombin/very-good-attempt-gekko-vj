-- ============================================================
--  npc_vj_gekko / cl_init.lua
--
--  FIX: This file previously contained only include() calls
--  with NO ENT:Think() or ENT:Draw() overrides. That meant:
--    - HitReact_Think()        was NEVER called
--    - BushmasterRecoil_Think() was NEVER called
--    - GekkoApplyGroundedPose() did NOT EXIST at all
--
--  The grounded system in leg_disable_system.lua sets
--  NW bool "GekkoLegsDisabled" = true and calls SnapToFloor
--  server-side, but bone manipulation is CLIENT-SIDE ONLY in
--  GMod. Without this Think loop the model floated in the air
--  regardless of pedestal bone offset values.
--
--  Root causes fixed here:
--    1. ENT:Think() now calls all per-frame client systems.
--    2. GekkoApplyGroundedPose() is implemented: it forces the
--       b_pedestal bone DOWN so the mesh rests on the floor,
--       then sets broken-leg angles on thigh/calf bones.
--    3. The pose is re-applied every single frame while the NW
--       bool is true, overriding any animation that would
--       otherwise lift the model.
-- ============================================================
include("shared.lua")
include("elastic_cl.lua")
include("muzzleflash_system.lua")
include("bullet_impact_system.lua")
include("hit_react_cl.lua")
include("cl_aps.lua")
include("mg_shell_system.lua")

-- ============================================================
--  GROUNDED POSE CONSTANTS
--
--  b_pedestal is the root "lift" bone that raises the Gekko's
--  body above the ground. By pushing it DOWN (large negative Z)
--  the entire mesh collapses to floor level.
--
--  The exact value depends on the model's rest height.
--  -260 puts the hull base at Z=0 for the standard Gekko model.
--  Adjust if a variant model has a different rest height.
-- ============================================================
local GP_PEDESTAL_BONE   = "b_pedestal"
local GP_L_THIGH_BONE    = "b_l_thigh"
local GP_R_THIGH_BONE    = "b_r_thigh"
local GP_L_CALF_BONE     = "b_l_calf1"
local GP_R_CALF_BONE     = "b_r_calf1"

-- How far (in model-local units) to shove the pedestal bone
-- downward. Negative = down in the model's local Z axis.
-- This is what makes the body hit the floor instead of floating.
local GP_PEDESTAL_Z      = -260

-- Broken-leg bone angles (left and right mirror each other)
-- These make the legs splay outward in a collapsed posture.
local GP_L_THIGH_ANG     = Angle(0,   0,  -50)
local GP_R_THIGH_ANG     = Angle(100, -80,  0)
local GP_L_CALF_ANG      = Angle(0,   45,   0)
local GP_R_CALF_ANG      = Angle(0,  -45,   0)

-- ============================================================
--  BONE INDEX CACHE  (lazy, per entity)
--  Bone lookups are expensive; cache on first grounded frame.
-- ============================================================
local function GP_CacheBones(self)
    if self._gp_bonesReady then return true end

    self._gp_pedestalIdx = self:LookupBone(GP_PEDESTAL_BONE)
    self._gp_lThighIdx   = self:LookupBone(GP_L_THIGH_BONE)
    self._gp_rThighIdx   = self:LookupBone(GP_R_THIGH_BONE)
    self._gp_lCalfIdx    = self:LookupBone(GP_L_CALF_BONE)
    self._gp_rCalfIdx    = self:LookupBone(GP_R_CALF_BONE)

    -- Fallback: if b_pedestal is missing try b_pelvis / b_pelvis1
    if not self._gp_pedestalIdx or self._gp_pedestalIdx < 0 then
        self._gp_pedestalIdx = self:LookupBone("b_pelvis") or -1
        if self._gp_pedestalIdx < 0 then
            self._gp_pedestalIdx = self:LookupBone("b_pelvis1") or -1
        end
    end

    -- Fallback: thigh variants
    if not self._gp_lThighIdx or self._gp_lThighIdx < 0 then
        self._gp_lThighIdx = self:LookupBone("b_l_thigh1") or -1
    end
    if not self._gp_rThighIdx or self._gp_rThighIdx < 0 then
        self._gp_rThighIdx = self:LookupBone("b_r_thigh1") or -1
    end

    self._gp_bonesReady = true

    print(string.format(
        "[GekkoGrounded] CacheBones | pedestal=%s(%d) lThigh=%s(%d) rThigh=%s(%d) lCalf=%s(%d) rCalf=%s(%d)",
        GP_PEDESTAL_BONE, self._gp_pedestalIdx or -1,
        GP_L_THIGH_BONE,  self._gp_lThighIdx   or -1,
        GP_R_THIGH_BONE,  self._gp_rThighIdx   or -1,
        GP_L_CALF_BONE,   self._gp_lCalfIdx    or -1,
        GP_R_CALF_BONE,   self._gp_rCalfIdx    or -1
    ))

    return true
end

-- ============================================================
--  GekkoApplyGroundedPose
--
--  Called EVERY FRAME while GekkoLegsDisabled == true.
--  ManipulateBonePosition: moves bone origin in MODEL-LOCAL space.
--  ManipulateBoneAngles:   rotates bone in model-local space.
--
--  The pedestal position push is what actually drops the mesh
--  to floor level. Bone angle changes on legs are cosmetic
--  (broken-leg splay). Both use additive=false so they are
--  absolute overwrites, not accumulations.
-- ============================================================
local GP_PEDESTAL_OFFSET = Vector(0, 0, GP_PEDESTAL_Z)
local ZERO_ANG           = Angle(0, 0, 0)

local function GekkoApplyGroundedPose(self)
    GP_CacheBones(self)

    -- ── 1. Slam body to floor via pedestal bone position ─────
    local pedIdx = self._gp_pedestalIdx
    if pedIdx and pedIdx >= 0 then
        self:ManipulateBonePosition(pedIdx, GP_PEDESTAL_OFFSET, false)
    end

    -- ── 2. Broken-leg angles on thighs ───────────────────────
    local lThigh = self._gp_lThighIdx
    if lThigh and lThigh >= 0 then
        self:ManipulateBoneAngles(lThigh, GP_L_THIGH_ANG, false)
    end

    local rThigh = self._gp_rThighIdx
    if rThigh and rThigh >= 0 then
        self:ManipulateBoneAngles(rThigh, GP_R_THIGH_ANG, false)
    end

    -- ── 3. Broken-leg angles on calves ───────────────────────
    local lCalf = self._gp_lCalfIdx
    if lCalf and lCalf >= 0 then
        self:ManipulateBoneAngles(lCalf, GP_L_CALF_ANG, false)
    end

    local rCalf = self._gp_rCalfIdx
    if rCalf and rCalf >= 0 then
        self:ManipulateBoneAngles(rCalf, GP_R_CALF_ANG, false)
    end
end

-- ============================================================
--  ClearGroundedPose
--  Restores all bones to neutral when the grounded state ends.
--  (Gekko can't currently un-ground, but this is correct
--   defensive cleanup if that ever changes.)
-- ============================================================
local function ClearGroundedPose(self)
    if not self._gp_bonesReady then return end

    local pedIdx = self._gp_pedestalIdx
    if pedIdx and pedIdx >= 0 then
        self:ManipulateBonePosition(pedIdx, vector_origin, false)
    end

    for _, idx in ipairs({
        self._gp_lThighIdx, self._gp_rThighIdx,
        self._gp_lCalfIdx,  self._gp_rCalfIdx,
    }) do
        if idx and idx >= 0 then
            self:ManipulateBoneAngles(idx, ZERO_ANG, false)
        end
    end

    self._gp_bonesReady = false   -- force re-cache if re-entered
end

-- ============================================================
--  ENT:Think  (CLIENT)
--
--  This is the missing piece. GMod's cl_init is the client
--  entity file. Without ENT:Think defined here, none of the
--  per-frame visual systems run at all.
--
--  Order matters:
--    1. Grounded pose (highest priority — must override anim)
--    2. Hit-react bone flinch
--    3. Bushmaster recoil bone flinch
-- ============================================================
function ENT:Think()
    -- ── Grounded state: apply floor pose every frame ─────────
    local grounded = self:GetNWBool("GekkoLegsDisabled", false)
    if grounded then
        GekkoApplyGroundedPose(self)
        -- Track last-known state so we can clear on transition
        self._gp_wasGrounded = true
    elseif self._gp_wasGrounded then
        -- Transitioned OUT of grounded (defensive)
        ClearGroundedPose(self)
        self._gp_wasGrounded = false
    end

    -- ── Hit-react bone flinch ─────────────────────────────────
    self:HitReact_Think()

    -- ── Bushmaster muzzle-recoil bone flinch ─────────────────
    BushmasterRecoil_Think(self)
end
