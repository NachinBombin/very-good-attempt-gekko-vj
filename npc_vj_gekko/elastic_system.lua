-- ============================================================
--  npc_vj_gekko / elastic_system.lua
--
--  Weapon 10: Elastic Tether
--  Triggered only when the enemy is within 0–900 units.
--  Spawns a GMod elastic constraint from the Bushmaster
--  muzzle position to the target entity.  The elastic pulls
--  the target continuously; it snaps (removes itself) after
--  ELASTIC_DURATION seconds or when either end becomes invalid.
--
--  Integration in init.lua:
--    include("elastic_system.lua")        -- top, with the others
--    self:GekkoElastic_Init()             -- inside ENT:Init()
--    self:GekkoElastic_Think()            -- inside ENT:OnThink()
--    FireElastic(self, enemy)             -- inside OnRangeAttackExecute
-- ============================================================

-- ── Tuning ───────────────────────────────────────────────────
local ELASTIC_MAX_DIST      = 900      -- units; attack only fires within this range
local ELASTIC_DURATION      = 6.0     -- seconds before the tether auto-snaps
local ELASTIC_COOLDOWN_MIN  = 12.0    -- minimum seconds between tether shots
local ELASTIC_COOLDOWN_MAX  = 22.0    -- maximum seconds between tether shots
local ELASTIC_CONSTANT      = 18      -- spring stiffness (higher = stronger pull)
local ELASTIC_DAMPING       = 0.8     -- oscillation damping
local ELASTIC_RDAMP         = 0       -- rotational damping
local ELASTIC_WIDTH         = 3       -- visual cable width (pixels)
local ELASTIC_MATERIAL      = "cable/rope"
local ELASTIC_COLOR         = Color(40, 220, 80, 230)   -- bright green tether
local ELASTIC_SNAP_SND      = "physics/metal/metal_box_impact_hard1.wav"
local ELASTIC_FIRE_SND      = "weapons/crossbow/bolt_fly1.wav"
local ELASTIC_FIRE_SND_LVL  = 90
local ELASTIC_ATTACH_SND    = "physics/metal/metal_solid_impact_hard1.wav"

-- Anchor bone offset on the Gekko (world-space Z lift from pelvis bone origin).
-- The Bushmaster muzzle lives near the pelvis attachment.
local ANCHOR_Z_OFFSET       = 200

-- ── Helpers ──────────────────────────────────────────────────

-- Returns the Bushmaster muzzle world position.
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

-- Destroys the active tether cleanly.
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

-- Called every tick from ENT:OnThink().
-- Watches for tether expiry or invalid ends.
function ENT:GekkoElastic_Think()
    if not IsValid(self._elasticConstraint) then
        -- nothing active
        return
    end

    local now = CurTime()

    -- Expired?
    if now >= self._elasticActiveUntil then
        DestroyTether(self, "expired")
        self:EmitSound(ELASTIC_SNAP_SND, 80, math.random(90, 110), 1)
        return
    end

    -- Target gone?
    if not IsValid(self._elasticTarget) then
        DestroyTether(self, "target invalid")
        return
    end

    -- Move the invisible anchor prop to follow the muzzle every tick
    -- so the elastic origin tracks the Gekko as it moves.
    if IsValid(self._elasticAnchorProp) then
        local newMuzzle = GetMuzzlePos(self)
        self._elasticAnchorProp:SetPos(newMuzzle)
        local phys = self._elasticAnchorProp:GetPhysicsObject()
        if IsValid(phys) then
            phys:SetPos(newMuzzle)
            phys:SetVelocity(Vector(0,0,0))
        end
    end
end

-- ── FireElastic ──────────────────────────────────────────────
-- Called from init.lua's FireElastic() local function.
function ENT:GekkoElastic_Fire(enemy)
    -- Already have a live tether — don't stack.
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

    -- ── Invisible anchor prop (physbox at muzzle) ────────────
    -- The elastic constraint needs two physics objects.
    -- We create a tiny weightless prop at the muzzle and freeze it;
    -- GekkoElastic_Think() teleports it every frame to track the Gekko.
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
    anchor:SetColor(Color(0,0,0,0))
    anchor:SetRenderMode(RENDERMODE_TRANSALPHA)

    local anchorPhys = anchor:GetPhysicsObject()
    if IsValid(anchorPhys) then
        anchorPhys:SetMass(1)
        anchorPhys:EnableGravity(false)
        anchorPhys:EnableMotion(false)   -- frozen; we teleport it manually
    end

    -- ── Elastic constraint ───────────────────────────────────
    -- constraint.Elastic( Ent1, Ent2, Bone1, Bone2,
    --   constant, damping, rdamping,
    --   material, width, stretchonly )
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

    -- Tint the rope entity if accessible
    if IsValid(tether) and tether.SetColor then
        tether:SetColor(ELASTIC_COLOR)
    end

    self._elasticConstraint  = tether
    self._elasticAnchorProp  = anchor
    self._elasticTarget      = enemy
    self._elasticActiveUntil = CurTime() + ELASTIC_DURATION

    -- Reset cooldown
    self._elasticNextShotT = CurTime() + math.Rand(ELASTIC_COOLDOWN_MIN, ELASTIC_COOLDOWN_MAX)

    -- SFX
    self:EmitSound(ELASTIC_FIRE_SND, ELASTIC_FIRE_SND_LVL, math.random(90, 110), 1)
    timer.Simple(0.12, function()
        if IsValid(enemy) then
            enemy:EmitSound(ELASTIC_ATTACH_SND, 80, math.random(85, 105), 1)
        end
    end)

    print(string.format(
        "[GekkoElastic] Tether FIRED | dist=%.0f  duration=%.1fs  expires=%.2f",
        dist, ELASTIC_DURATION, self._elasticActiveUntil
    ))
    return true
end

-- ── Cleanup on Gekko death / remove ──────────────────────────
function ENT:GekkoElastic_OnRemove()
    DestroyTether(self, "gekko removed")
end
