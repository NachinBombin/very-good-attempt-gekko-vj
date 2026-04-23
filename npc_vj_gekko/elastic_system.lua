-- ============================================================
--  npc_vj_gekko / elastic_system.lua
--
--  ELASTIC GRAPPLE ATTACK
--  Fires from the Bushmaster pelvis muzzle position.
--  Creates a rope (PhysicsConstraint elastic) between the
--  Gekko and the target.  The target is yanked toward the
--  Gekko by a repeating force impulse every tick until:
--    a) the rope entity is removed / broken by damage
--    b) the target dies
--    c) the target escapes past ELASTIC_BREAK_DIST
--    d) ELASTIC_MAX_DURATION seconds elapse
--
--  Only one elastic can be active at a time per Gekko.
-- ============================================================

-- ────────────────────────────────────────────────────────────
--  Tuning
-- ────────────────────────────────────────────────────────────
local ELASTIC_MAX_DIST       = 900      -- max range to even attempt the shot
local ELASTIC_MIN_DIST       = 80       -- too close, don't bother
local ELASTIC_COOLDOWN       = 14.0     -- seconds between uses
local ELASTIC_MAX_DURATION   = 8.0      -- auto-break after this long
local ELASTIC_BREAK_DIST     = 1100     -- rope snaps if target runs this far
local ELASTIC_PULL_FORCE     = 420      -- units/s² impulse toward Gekko each tick
local ELASTIC_PULL_INTERVAL  = 0.05     -- seconds between pull impulse ticks
local ELASTIC_PULL_DAMAGE    = 4        -- small crush damage per pull tick
local ELASTIC_ROPE_WIDTH     = 3        -- visual rope width (px)
local ELASTIC_ROPE_MAT       = "cable/rope"
local ELASTIC_ROPE_COLOR     = Color(60, 180, 60, 220)  -- green-ish steel cable
local ELASTIC_SND_FIRE       = "physcannon/energy_sing_loop4.wav"
local ELASTIC_SND_SNAP       = "physcannon/superphys_launch3.wav"
local ELASTIC_SND_PULL       = "physcannon/holdloop.wav"
local ELASTIC_SND_LEVEL      = 90
local ELASTIC_MUZZLE_Z       = 200      -- Z offset from Gekko origin for muzzle src
-- Keyvalue passed to constraint.Elastic
local ELASTIC_CONSTANT       = 28000   -- spring stiffness
local ELASTIC_DAMPING        = 800
local ELASTIC_RDAMPING       = 800
local ELASTIC_NATURAL_LEN    = 0       -- rest length (0 = always pulling)

-- ────────────────────────────────────────────────────────────
--  GekkoElastic_Init  — called from ENT:Init()
-- ────────────────────────────────────────────────────────────
function ENT:GekkoElastic_Init()
    self._elasticCooldownT  = 0
    self._elasticActive     = false
    self._elasticRope       = nil   -- rope visual entity
    self._elasticConstraint = nil   -- constraint entity
    self._elasticTarget     = nil
    self._elasticStartT     = 0
    self._elasticPullNextT  = 0
    self._elasticAnchor     = nil   -- invisible anchor prop at Gekko muzzle
    print("[GekkoElastic] Init()")
end

-- ────────────────────────────────────────────────────────────
--  Internal: tear down everything
-- ────────────────────────────────────────────────────────────
local function ElasticCleanup(ent, reason)
    if IsValid(ent._elasticConstraint) then
        ent._elasticConstraint:Remove()
    end
    if IsValid(ent._elasticRope) then
        ent._elasticRope:Remove()
    end
    if IsValid(ent._elasticAnchor) then
        ent._elasticAnchor:Remove()
    end

    ent._elasticActive     = false
    ent._elasticRope       = nil
    ent._elasticConstraint = nil
    ent._elasticTarget     = nil
    ent._elasticAnchor     = nil

    if IsValid(ent) then
        ent:EmitSound(ELASTIC_SND_SNAP, ELASTIC_SND_LEVEL, math.random(95, 110), 1)
    end
    print("[GekkoElastic] Cleanup: " .. (reason or "unknown"))
end

-- ────────────────────────────────────────────────────────────
--  GekkoElastic_Fire  — call from FireElastic()
-- ────────────────────────────────────────────────────────────
function ENT:GekkoElastic_Fire(enemy)
    if self._elasticActive then
        print("[GekkoElastic] Already active — skipping")
        return false
    end

    local dist = self:GetPos():Distance(enemy:GetPos())
    if dist > ELASTIC_MAX_DIST or dist < ELASTIC_MIN_DIST then
        print(string.format("[GekkoElastic] Range check failed dist=%.0f", dist))
        return false
    end

    -- ── Muzzle source position ───────────────────────────────
    local src = self:GetPos() + Vector(0, 0, ELASTIC_MUZZLE_Z)
    local pelBone = self.GekkoPelvisBone
    if pelBone and pelBone >= 0 then
        local m = self:GetBoneMatrix(pelBone)
        if m then
            src = m:GetTranslation() + Vector(0, 0, ELASTIC_MUZZLE_Z)
        end
    end

    -- ── Spawn a tiny invisible anchor prop at muzzle ─────────
    -- The elastic constraint needs a physics object on the Gekko
    -- side; NPCs are not physics objects themselves.
    local anchor = ents.Create("prop_physics")
    if not IsValid(anchor) then
        print("[GekkoElastic] ERROR: anchor create failed")
        return false
    end
    anchor:SetModel("models/hunter/misc/shell2x2.mdl")
    anchor:SetPos(src)
    anchor:SetAngles(self:GetAngles())
    anchor:SetNoDraw(true)
    anchor:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    anchor:Spawn()
    anchor:Activate()
    anchor:SetModelScale(0.01, 0)
    local ancPhys = anchor:GetPhysicsObject()
    if IsValid(ancPhys) then
        ancPhys:EnableGravity(false)
        ancPhys:EnableMotion(false)   -- it stays glued to the Gekko via think
        ancPhys:SetMass(99999)
    end

    -- ── Get or create a physics object on the target ─────────
    -- Players and most NPCs are already physical. For props: wake phys.
    local targetPhys = enemy:GetPhysicsObject()
    if not IsValid(targetPhys) then
        print("[GekkoElastic] Target has no phys object — aborting")
        anchor:Remove()
        return false
    end

    -- ── Create the elastic constraint ────────────────────────
    local cst = constraint.Elastic(
        anchor, enemy,
        0, 0,               -- bone indices (0 = root)
        Vector(0,0,0),      -- local offset on anchor
        Vector(0,0,0),      -- local offset on target
        ELASTIC_CONSTANT,
        ELASTIC_DAMPING,
        ELASTIC_RDAMPING,
        ELASTIC_NATURAL_LEN,
        ELASTIC_NATURAL_LEN,
        false               -- no width (we draw our own rope)
    )
    if not IsValid(cst) then
        print("[GekkoElastic] ERROR: constraint.Elastic() failed")
        anchor:Remove()
        return false
    end

    -- ── Visual rope ───────────────────────────────────────────
    local rope = ents.Create("keyframe_rope")
    if IsValid(rope) then
        rope:SetKeyValue("RopeMaterial",  ELASTIC_ROPE_MAT)
        rope:SetKeyValue("Slack",         "0")
        rope:SetKeyValue("Type",          "1")
        rope:SetKeyValue("Width",         tostring(ELASTIC_ROPE_WIDTH))
        rope:SetKeyValue("TextureScale",  "1")
        rope:SetPos(src)
        rope:SetParent(anchor)
        rope:Spawn()
        rope:SetColor(ELASTIC_ROPE_COLOR)
        rope:SetKeyValue("NextKey", tostring(enemy:EntIndex()))
        -- connect endpoints via SetParent trick
        rope:Fire("SetEndPoint", tostring(enemy:EntIndex()), 0)
    end

    self._elasticActive     = true
    self._elasticTarget     = enemy
    self._elasticConstraint = cst
    self._elasticRope       = rope
    self._elasticAnchor     = anchor
    self._elasticStartT     = CurTime()
    self._elasticPullNextT  = CurTime() + ELASTIC_PULL_INTERVAL

    self:EmitSound(ELASTIC_SND_FIRE, ELASTIC_SND_LEVEL, 100, 1)

    print(string.format(
        "[GekkoElastic] Fired | dist=%.0f  target=%s",
        dist, tostring(enemy)
    ))
    return true
end

-- ────────────────────────────────────────────────────────────
--  GekkoElastic_Think  — called every tick from ENT:OnThink()
-- ────────────────────────────────────────────────────────────
function ENT:GekkoElastic_Think()
    if not self._elasticActive then return end

    local now    = CurTime()
    local target = self._elasticTarget
    local anchor = self._elasticAnchor

    -- ── Validity / death / duration checks ───────────────────
    if not IsValid(target) or not target:Alive() then
        ElasticCleanup(self, "target dead/removed")
        return
    end
    if not IsValid(anchor) then
        ElasticCleanup(self, "anchor removed")
        return
    end
    if not IsValid(self._elasticConstraint) then
        ElasticCleanup(self, "constraint removed externally")
        return
    end
    if now - self._elasticStartT > ELASTIC_MAX_DURATION then
        ElasticCleanup(self, "max duration")
        return
    end

    local dist = self:GetPos():Distance(target:GetPos())
    if dist > ELASTIC_BREAK_DIST then
        ElasticCleanup(self, "target escaped")
        return
    end

    -- ── Pin anchor to Gekko muzzle every tick ────────────────
    local src = self:GetPos() + Vector(0, 0, ELASTIC_MUZZLE_Z)
    local pelBone = self.GekkoPelvisBone
    if pelBone and pelBone >= 0 then
        local m = self:GetBoneMatrix(pelBone)
        if m then src = m:GetTranslation() + Vector(0, 0, ELASTIC_MUZZLE_Z) end
    end
    anchor:SetPos(src)
    local ancPhys = anchor:GetPhysicsObject()
    if IsValid(ancPhys) then
        ancPhys:SetPos(src)
    end

    -- ── Supplemental pull impulse + tick damage ───────────────
    -- The elastic constraint already pulls via spring force, but
    -- NPCs have no physics on themselves.  We add an explicit
    -- velocity nudge toward the Gekko so players/NPCs both feel it.
    if now >= self._elasticPullNextT then
        self._elasticPullNextT = now + ELASTIC_PULL_INTERVAL

        local toGekko = (self:GetPos() - target:GetPos())
        local d       = toGekko:Length()
        if d > 1 then
            toGekko = toGekko / d   -- normalize
        end

        -- For players: SetVelocity nudge
        if target:IsPlayer() then
            local curVel = target:GetVelocity()
            target:SetVelocity(toGekko * ELASTIC_PULL_FORCE)
        end

        -- For physics-based targets (props, ragdolls): ApplyForceCenter
        local tPhys = target:GetPhysicsObject()
        if IsValid(tPhys) then
            tPhys:ApplyForceCenter(toGekko * ELASTIC_PULL_FORCE * tPhys:GetMass() * ELASTIC_PULL_INTERVAL)
        end

        -- Tick damage so the grab actually hurts
        local dmg = DamageInfo()
        dmg:SetDamage(ELASTIC_PULL_DAMAGE)
        dmg:SetAttacker(self)
        dmg:SetInflictor(self)
        dmg:SetDamageType(DMG_CRUSH)
        dmg:SetDamagePosition(target:GetPos())
        target:TakeDamageInfo(dmg)

        -- Pull sound on a longer cycle so it isn't spammy
        if math.random(1, 8) == 1 then
            self:EmitSound(ELASTIC_SND_PULL, ELASTIC_SND_LEVEL - 20, 110, 0.6)
        end
    end
end
