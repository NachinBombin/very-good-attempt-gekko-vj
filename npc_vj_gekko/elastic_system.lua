-- ============================================================
--  npc_vj_gekko / elastic_system.lua
--
--  Weapon 10: Elastic Tether
--  Triggered only when the enemy is within 0–900 units.
--  Spawns a GMod elastic constraint from an invisible anchor
--  prop (tracked to the Bushmaster muzzle each tick) to the
--  target entity.  The elastic pulls the target continuously;
--  it snaps after ELASTIC_DURATION seconds or when either end
--  becomes invalid.
-- ============================================================

-- ── Tuning ───────────────────────────────────────────────────
local ELASTIC_MAX_DIST     = 900      -- units; only fires within this range
local ELASTIC_DURATION     = 6.0      -- seconds before auto-snap
local ELASTIC_COOLDOWN_MIN = 12.0
local ELASTIC_COOLDOWN_MAX = 22.0
local ELASTIC_CONSTANT     = 800      -- spring stiffness (18 was imperceptible)
local ELASTIC_DAMPING      = 0.8
local ELASTIC_RDAMP        = 0
local ELASTIC_WIDTH        = 4        -- rope pixel width
local ELASTIC_MATERIAL     = "cable/cable"   -- thicker / more visible than rope
local ELASTIC_SNAP_SND     = "physics/metal/metal_box_impact_hard1.wav"
local ELASTIC_FIRE_SND     = "weapons/crossbow/bolt_fly1.wav"
local ELASTIC_FIRE_SND_LVL = 90
local ELASTIC_ATTACH_SND   = "physics/metal/metal_solid_impact_hard1.wav"

-- Z offset above the pelvis bone for the muzzle anchor origin
local ANCHOR_Z_OFFSET = 200

-- ── Helpers ──────────────────────────────────────────────────

local function GetMuzzlePos(ent)
    local bone = ent.GekkoPelvisBone
    if bone and bone >= 0 then
        local m = ent:GetBoneMatrix(bone)
        if m then
            return m:GetTranslation() + Vector(0, 0, ANCHOR_Z_OFFSET)
        end
    end
    return ent:GetPos() + Vector(0, 0, ANCHOR_Z_OFFSET)
end

local function DestroyTether(ent, reason)
    if IsValid(ent._elasticConstraint) then
        ent._elasticConstraint:Remove()
    end
    if IsValid(ent._elasticAnchorProp) then
        ent._elasticAnchorProp:Remove()
    end
    ent._elasticConstraint  = nil
    ent._elasticAnchorProp  = nil
    ent._elasticTarget      = nil
    ent._elasticActiveUntil = 0
    print("[GekkoElastic] Tether removed — " .. (reason or "unknown"))
end

-- ── ENT methods ──────────────────────────────────────────────

function ENT:GekkoElastic_Init()
    self._elasticConstraint  = nil
    self._elasticAnchorProp  = nil
    self._elasticTarget      = nil
    self._elasticActiveUntil = 0
    self._elasticNextShotT   = CurTime() + math.Rand(ELASTIC_COOLDOWN_MIN, ELASTIC_COOLDOWN_MAX)
    print("[GekkoElastic] Init complete")
end

function ENT:GekkoElastic_Think()
    if not IsValid(self._elasticConstraint) then return end

    local now = CurTime()

    if now >= self._elasticActiveUntil then
        DestroyTether(self, "expired")
        self:EmitSound(ELASTIC_SNAP_SND, 80, math.random(90, 110), 1)
        return
    end

    if not IsValid(self._elasticTarget) then
        DestroyTether(self, "target invalid")
        return
    end

    -- Track the anchor prop to the muzzle each tick.
    -- We keep EnableMotion(true) and just zero the velocity after
    -- teleporting, which is the only reliable way to move a physobj.
    if IsValid(self._elasticAnchorProp) then
        local newMuzzle = GetMuzzlePos(self)
        self._elasticAnchorProp:SetPos(newMuzzle)
        local phys = self._elasticAnchorProp:GetPhysicsObject()
        if IsValid(phys) then
            phys:SetPos(newMuzzle)
            phys:SetVelocity(Vector(0, 0, 0))
            phys:SetAngleVelocity(Vector(0, 0, 0))
        end
    end
end

function ENT:GekkoElastic_Fire(enemy)
    if IsValid(self._elasticConstraint) then
        print("[GekkoElastic] Tether already active, skipping")
        return false
    end

    local dist = self:GetPos():Distance(enemy:GetPos())
    if dist > ELASTIC_MAX_DIST then
        print(string.format("[GekkoElastic] Target too far (%.0f > %d), skipping", dist, ELASTIC_MAX_DIST))
        return false
    end

    local muzzlePos = GetMuzzlePos(self)

    -- ── Invisible anchor prop ────────────────────────────────
    local anchor = ents.Create("prop_physics")
    if not IsValid(anchor) then
        print("[GekkoElastic] ERROR: anchor prop create failed")
        return false
    end
    anchor:SetModel("models/props_junk/PopCan01a.mdl")
    anchor:SetPos(muzzlePos)
    anchor:SetAngles(angle_zero)
    anchor:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    anchor:DrawShadow(false)
    anchor:Spawn()
    anchor:Activate()
    -- Fully transparent — only the rope is visible
    anchor:SetColor(Color(0, 0, 0, 0))
    anchor:SetRenderMode(RENDERMODE_TRANSALPHA)

    local anchorPhys = anchor:GetPhysicsObject()
    if IsValid(anchorPhys) then
        anchorPhys:SetMass(1)
        anchorPhys:EnableGravity(false)
        -- Keep motion ENABLED so SetPos/phys:SetPos actually move it each tick.
        -- We zero velocity after every teleport in _Think instead of freezing.
        anchorPhys:EnableMotion(true)
        anchorPhys:SetVelocity(Vector(0, 0, 0))
    end

    -- ── Elastic constraint ───────────────────────────────────
    local tether = constraint.Elastic(
        anchor, enemy,
        0, 0,
        ELASTIC_CONSTANT,
        ELASTIC_DAMPING,
        ELASTIC_RDAMP,
        ELASTIC_MATERIAL,
        ELASTIC_WIDTH,
        false
    )

    if not IsValid(tether) then
        print("[GekkoElastic] ERROR: constraint.Elastic failed")
        anchor:Remove()
        return false
    end

    -- Color the rope.  The rope entity stores its color as a networked
    -- Color NW var rather than responding to SetColor on the constraint.
    -- Walk the constraint's rope entity if it exists.
    if tether.RopeEntity and IsValid(tether.RopeEntity) then
        tether.RopeEntity:SetColor(Color(40, 220, 80, 230))
    end
    -- Also try directly — harmless if it fails
    pcall(function() tether:SetColor(Color(40, 220, 80, 230)) end)

    self._elasticConstraint  = tether
    self._elasticAnchorProp  = anchor
    self._elasticTarget      = enemy
    self._elasticActiveUntil = CurTime() + ELASTIC_DURATION
    self._elasticNextShotT   = CurTime() + math.Rand(ELASTIC_COOLDOWN_MIN, ELASTIC_COOLDOWN_MAX)

    -- SFX
    self:EmitSound(ELASTIC_FIRE_SND, ELASTIC_FIRE_SND_LVL, math.random(90, 110), 1)
    timer.Simple(0.12, function()
        if IsValid(enemy) then
            enemy:EmitSound(ELASTIC_ATTACH_SND, 80, math.random(85, 105), 1)
        end
    end)

    print(string.format(
        "[GekkoElastic] Tether FIRED | dist=%.0f  duration=%.1fs  expires=%.2f  constant=%d",
        dist, ELASTIC_DURATION, self._elasticActiveUntil, ELASTIC_CONSTANT
    ))
    return true
end

-- ── Cleanup ──────────────────────────────────────────────────
function ENT:GekkoElastic_OnRemove()
    DestroyTether(self, "gekko removed")
end
