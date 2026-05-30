-- ============================================================
-- npc_vj_gekko / init.lua
-- INTEGRATED WITH: Juicy Bleeding Effect (Hemo-fluid-stream)
-- NEW BLEEDING TYPE: gekko_juicy_bleeding (NPC-owned only)
-- INTEGRATED WITH: pedestal_dodge_system.lua (random strafe + reactive dodge)
-- INTEGRATED WITH: crouch_system.lua (obstacle + ceiling + random + dodge crouch)
-- ============================================================

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")
include("crouch_system.lua")
include("pedestal_dodge_system.lua")

-- ============================================================
-- Initialization
-- ============================================================

function ENT:Initialize()
    self:SetModel("models/gekko/gekko.mdl")
    self:VJ_Initialize()

    self:SetHullType(HULL_HUMAN)
    self:SetHullSizeNormal()
    self:CapabilitiesAdd(CAP_MOVE_GROUND)
    self:CapabilitiesAdd(CAP_OPEN_DOORS)
    self:SetMaxYawSpeed(360)
    self:SetMovementActivity(ACT_RUN)

    -- Crouch system init
    self:GeckoCrouch_Init()

    -- Pedestal dodge init
    self:PedestalDodge_Init()

    -- Invuln window (written by PedestalDodge_OnHit / BeginSlide)
    self._gekkoInvulnUntil = 0
end

-- ============================================================
-- Think
-- ============================================================

function ENT:OnThink()
    self:GekkoUpdateAnimation()
    self:PedestalDodge_ThinkStrafe()
end

-- ============================================================
-- Animation gating + crouch update
-- ============================================================

function ENT:GekkoUpdateAnimation()
    -- FIX: Suppress VJ Flinching for the entire dodge-crouch lock window, not
    -- just the invuln window. _gekkoInvulnUntil covers 2.8 s; _gekkoDodgeCrouchUntil
    -- covers 2.5 s. Both windows overlap but are checked independently so neither
    -- has a gap. Without this, bullets landing after invuln expires but before the
    -- crouch lock ends set Flinching=true and gate out GeckoCrouch_Update, causing
    -- the NPC to snap to standing and back repeatedly (the post-dodge up-down flicker).
    local now = CurTime()
    if now < (self._gekkoInvulnUntil or 0)
    or (self._gekkoDodgeCrouch and now < (self._gekkoDodgeCrouchUntil or 0)) then
        self.Flinching = false
    end

    if self.Flinching then return end

    self:GeckoCrouch_Update()
end

-- ============================================================
-- Damage handling
-- ============================================================

function ENT:TraceAttack(dmginfo, dir, trace)
    if CurTime() < (self._gekkoInvulnUntil or 0) then
        -- Suppress all hit effects during dodge invuln window
        return
    end
    self:VJ_TraceAttack(dmginfo, dir, trace)
end

function ENT:OnTakeDamage(dmginfo)
    -- Invuln window: swallow the hit silently
    if CurTime() < (self._gekkoInvulnUntil or 0) then
        dmginfo:SetDamage(0)
        dmginfo:SetDamageForce(Vector(0, 0, 0))
        return
    end

    -- Reactive dodge: fires BEFORE BaseClass so the invuln window is set
    -- before VJ Base processes the damage and potentially sets Flinching.
    local dodged = self:PedestalDodge_OnHit(dmginfo)
    if dodged then
        -- Dodge consumed this hit: zero out damage so VJ Base doesn't
        -- apply health loss, then let BaseClass run for sound/effects.
        dmginfo:SetDamage(0)
        dmginfo:SetDamageForce(Vector(0, 0, 0))
        self.Flinching = false
    end

    self:BaseClass.OnTakeDamage(dmginfo)

    -- Re-suppress flinch if we just dodged (BaseClass may have set it)
    if dodged then
        self.Flinching = false
    end

    -- PedestalDodge_OnHit sets _gekkoInvulnUntil so follow-up hits in
    -- the same frame (e.g. blast splash) are already blocked above.
    -- Extra safety for any hits that slip through before next TraceAttack.
    if CurTime() < (self._gekkoInvulnUntil or 0) then
        self.Flinching = false
    end
end
