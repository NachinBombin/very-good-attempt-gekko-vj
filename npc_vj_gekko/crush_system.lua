-- ============================================================
--  npc_vj_gekko / crush_system.lua
--
--  Three independent crush / blast systems:
--
--  1. Walk Crush  — front hull sweep while walking/running
--  2. Launch Blast — sphere damage at jump takeoff
--  3. Land Blast   — sphere damage + knockup on landing
-- ============================================================

-- Shared helper: apply damage + physics impulse to a single entity.
-- `impulseVec` is the world-space force to apply (can be zero vector).
local function CrushDamageEnt(attacker, target, dmg, impulseVec)
    if not IsValid(target)             then return end
    if target == attacker              then return end
    if not target:IsNPC()
       and not target:IsPlayer()
       and not target:GetPhysicsObject():IsValid() then return end

    local dmginfo = DamageInfo()
    dmginfo:SetDamage(dmg)
    dmginfo:SetAttacker(attacker)
    dmginfo:SetInflictor(attacker)
    dmginfo:SetDamageType(DMG_CRUSH)
    dmginfo:SetDamagePosition(target:GetPos())
    dmginfo:SetDamageForce(impulseVec)
    target:TakeDamageInfo(dmginfo)

    -- Also push physics objects directly so props actually fly
    local phys = target:GetPhysicsObject()
    if IsValid(phys) then
        phys:ApplyForceCenter(impulseVec)
    end
end

-- ============================================================
--  1. WALK CRUSH
--     Called every think tick from GeckoCrush_Think.
--     Only active during JUMP_NONE and speed > threshold.
-- ============================================================
local WALK_CRUSH_DIST    = 96     -- how far ahead to sweep (units)
local WALK_CRUSH_WIDTH   = 52     -- half-width / half-height of sweep box
local WALK_CRUSH_DAMAGE  = 35
local WALK_CRUSH_SPEED   = 30     -- minimum GekkoSpeed to enable
local WALK_CRUSH_COOLDOWN = 0.4   -- seconds between hits on the same entity
local WALK_CRUSH_IMPULSE  = 9000  -- force magnitude on hit entity

function ENT:GeckoCrush_Think()
    -- Only while fully grounded
    if self:GetGekkoJumpState() ~= self.JUMP_NONE then return end

    local speed = self:GetNWFloat("GekkoSpeed", 0)
    if speed < WALK_CRUSH_SPEED then return end

    local now   = CurTime()
    local pos   = self:GetPos() + Vector(0, 0, 80)   -- mid-body height
    local fwd   = self:GetForward()
    local sweep = pos + fwd * WALK_CRUSH_DIST

    local half  = Vector(WALK_CRUSH_WIDTH, WALK_CRUSH_WIDTH, WALK_CRUSH_WIDTH)

    local tr = util.TraceHull({
        start  = pos,
        endpos = sweep,
        mins   = -half,
        maxs   =  half,
        filter = self,
        mask   = MASK_SHOT_HULL,
    })

    local hit = tr.Entity
    if not IsValid(hit) then return end
    if not hit:IsNPC() and not hit:IsPlayer() then return end

    -- Per-entity cooldown
    if not self._crushHitTimes then self._crushHitTimes = {} end
    local lastHit = self._crushHitTimes[hit] or 0
    if now - lastHit < WALK_CRUSH_COOLDOWN then return end
    self._crushHitTimes[hit] = now

    -- Scale damage by how "head-on" the hit is (dot of our fwd vs to-target)
    local toTarget = (hit:GetPos() - self:GetPos()):GetNormalized()
    local dot      = math.Clamp(fwd:Dot(toTarget), 0.5, 1.0)
    local dmg      = WALK_CRUSH_DAMAGE * dot

    -- Push away in our forward direction + slight upward toss
    local impulse  = (fwd + Vector(0, 0, 0.3)):GetNormalized() * WALK_CRUSH_IMPULSE
    CrushDamageEnt(self, hit, dmg, impulse)

    print(string.format(
        "[GekkoCrush] Walk hit: %s  dmg=%.1f  dot=%.2f",
        hit:GetClass(), dmg, dot
    ))
end

-- ============================================================
--  2. LAUNCH BLAST  (called from GekkoJump_Execute)
--     Punishes anything standing right under/around the Gekko
--     as it fires its jets and leaps.
-- ============================================================
local LAUNCH_RADIUS  = 220
local LAUNCH_DAMAGE  = 60
local LAUNCH_IMPULSE = 18000

function ENT:GeckoCrush_LaunchBlast()
    local origin = self:GetPos() + Vector(0, 0, 40)

    for _, ent in ipairs(ents.FindInSphere(origin, LAUNCH_RADIUS)) do
        if ent ~= self and (ent:IsNPC() or ent:IsPlayer() or IsValid(ent:GetPhysicsObject())) then
            local dir     = (ent:GetPos() - origin):GetNormalized()
            -- Blast outward + slight up
            local impulse = (dir + Vector(0, 0, 0.5)):GetNormalized() * LAUNCH_IMPULSE
            CrushDamageEnt(self, ent, LAUNCH_DAMAGE, impulse)
        end
    end

    print(string.format("[GekkoCrush] LaunchBlast  r=%d  dmg=%d", LAUNCH_RADIUS, LAUNCH_DAMAGE))
end

-- ============================================================
--  3. LAND BLAST  (called from GekkoJump_LandImpact)
--     Larger radius, harder hit, strong upward component so
--     nearby entities get thrown up.
-- ============================================================
local LAND_RADIUS  = 300
local LAND_DAMAGE  = 80
local LAND_IMPULSE = 22000

function ENT:GeckoCrush_LandBlast()
    local origin = self:GetPos() + Vector(0, 0, 20)

    for _, ent in ipairs(ents.FindInSphere(origin, LAND_RADIUS)) do
        if ent ~= self and (ent:IsNPC() or ent:IsPlayer() or IsValid(ent:GetPhysicsObject())) then
            local dir     = (ent:GetPos() - origin):GetNormalized()
            -- Upward-biased knockup
            local impulse = (dir + Vector(0, 0, 1.2)):GetNormalized() * LAND_IMPULSE
            CrushDamageEnt(self, ent, LAND_DAMAGE, impulse)
        end
    end

    print(string.format("[GekkoCrush] LandBlast  r=%d  dmg=%d", LAND_RADIUS, LAND_DAMAGE))
end
