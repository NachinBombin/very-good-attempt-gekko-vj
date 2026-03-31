-- ============================================================
--  npc_vj_gekko / crush_system.lua
--
--  Three independent crush / blast systems:
--
--  1. Walk Crush   — front hull sweep while walking/running
--  2. Launch Blast — sphere damage at jump takeoff
--  3. Land Blast   — sphere damage + knockup on landing
-- ============================================================

if SERVER then
    util.AddNetworkString("GekkoCrushHit")
end

-- ============================================================
--  Shared helper: apply damage + physics impulse to a single entity.
-- ============================================================
local function CrushDamageEnt(attacker, target, dmg, impulseVec)
    if not IsValid(target)   then return end
    if target == attacker    then return end
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

    local phys = target:GetPhysicsObject()
    if IsValid(phys) then
        phys:ApplyForceCenter(impulseVec)
    end

    net.Start("GekkoCrushHit")
        net.WriteVector(target:GetPos())
        net.WriteVector(attacker:GetPos())
    net.Broadcast()
end

-- ============================================================
--  Inverse-square damage falloff helper
--
--  dmg(0)      = dmgMax        (direct hit)
--  dmg(radius) = dmgMin        (edge of radius)
--
--  Formula:  dmg = dmgMax / (1 + k * (dist/radius)^2)
--  where k is solved from:  dmgMin = dmgMax / (1 + k)
--  => k = dmgMax/dmgMin - 1
-- ============================================================
local function BlastDamage(dmgMax, dmgMin, dist, radius)
    local k    = (dmgMax / dmgMin) - 1          -- shape constant
    local dn   = math.Clamp(dist / radius, 0, 1) -- normalised distance
    return dmgMax / (1 + k * dn * dn)
end

-- ============================================================
--  1. WALK CRUSH
-- ============================================================
local WALK_CRUSH_DIST     = 96
local WALK_CRUSH_WIDTH    = 52
local WALK_CRUSH_DAMAGE   = 35
local WALK_CRUSH_SPEED    = 30
local WALK_CRUSH_COOLDOWN = 0.4
local WALK_CRUSH_IMPULSE  = 9000

function ENT:GeckoCrush_Think()
    if self:GetGekkoJumpState() ~= self.JUMP_NONE then return end

    local speed = self:GetNWFloat("GekkoSpeed", 0)
    if speed < WALK_CRUSH_SPEED then return end

    local now   = CurTime()
    local pos   = self:GetPos() + Vector(0, 0, 80)
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

    if not self._crushHitTimes then self._crushHitTimes = {} end
    local lastHit = self._crushHitTimes[hit] or 0
    if now - lastHit < WALK_CRUSH_COOLDOWN then return end
    self._crushHitTimes[hit] = now

    local toTarget = (hit:GetPos() - self:GetPos()):GetNormalized()
    local dot      = math.Clamp(fwd:Dot(toTarget), 0.5, 1.0)
    local dmg      = WALK_CRUSH_DAMAGE * dot

    local impulse = (fwd + Vector(0, 0, 0.3)):GetNormalized() * WALK_CRUSH_IMPULSE
    CrushDamageEnt(self, hit, dmg, impulse)

    print(string.format("[GekkoCrush] Walk hit: %s  dmg=%.1f  dot=%.2f", hit:GetClass(), dmg, dot))
end

-- ============================================================
--  2. LAUNCH BLAST
--
--  Inverse-square: max=60 at dist=0, min=2 at dist=radius(220)
-- ============================================================
local LAUNCH_RADIUS     = 220
local LAUNCH_DAMAGE_MAX = 60
local LAUNCH_DAMAGE_MIN = 2
local LAUNCH_IMPULSE    = 18000

function ENT:GeckoCrush_LaunchBlast()
    local origin = self:GetPos() + Vector(0, 0, 40)

    for _, ent in ipairs(ents.FindInSphere(origin, LAUNCH_RADIUS)) do
        if ent ~= self and (ent:IsNPC() or ent:IsPlayer() or IsValid(ent:GetPhysicsObject())) then
            local dist    = ent:GetPos():Distance(origin)
            local dmg     = BlastDamage(LAUNCH_DAMAGE_MAX, LAUNCH_DAMAGE_MIN, dist, LAUNCH_RADIUS)
            local dir     = (ent:GetPos() - origin):GetNormalized()
            local impulse = (dir + Vector(0, 0, 0.5)):GetNormalized() * LAUNCH_IMPULSE
            CrushDamageEnt(self, ent, dmg, impulse)
        end
    end

    print(string.format("[GekkoCrush] LaunchBlast  r=%d  dmg=%.0f..%.0f",
        LAUNCH_RADIUS, LAUNCH_DAMAGE_MAX, LAUNCH_DAMAGE_MIN))
end

-- ============================================================
--  3. LAND BLAST
--
--  Inverse-square: max=80 at dist=0, min=2 at dist=radius(300)
--  => k = 80/2 - 1 = 39
-- ============================================================
local LAND_RADIUS     = 300
local LAND_DAMAGE_MAX = 80
local LAND_DAMAGE_MIN = 2
local LAND_IMPULSE    = 22000

function ENT:GeckoCrush_LandBlast()
    local origin = self:GetPos() + Vector(0, 0, 20)

    for _, ent in ipairs(ents.FindInSphere(origin, LAND_RADIUS)) do
        if ent ~= self and (ent:IsNPC() or ent:IsPlayer() or IsValid(ent:GetPhysicsObject())) then
            local dist    = ent:GetPos():Distance(origin)
            local dmg     = BlastDamage(LAND_DAMAGE_MAX, LAND_DAMAGE_MIN, dist, LAND_RADIUS)
            local dir     = (ent:GetPos() - origin):GetNormalized()
            local impulse = (dir + Vector(0, 0, 1.2)):GetNormalized() * LAND_IMPULSE
            CrushDamageEnt(self, ent, dmg, impulse)
        end
    end

    print(string.format("[GekkoCrush] LandBlast  r=%d  dmg=%.0f..%.0f",
        LAND_RADIUS, LAND_DAMAGE_MAX, LAND_DAMAGE_MIN))
end
