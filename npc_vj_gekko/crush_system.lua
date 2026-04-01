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
--  attacker is ALWAYS excluded from both damage and impulse.
-- ============================================================
local function CrushDamageEnt(attacker, target, dmg, impulseVec)
    if not IsValid(target)        then return end
    if target == attacker         then return end  -- never self-damage

    -- Skip pure physics objects that are world-static (mass == 0)
    local phys = target:GetPhysicsObject()
    if not target:IsNPC() and not target:IsPlayer() then
        if not IsValid(phys) or phys:GetMass() <= 0 then return end
    end

    local dmginfo = DamageInfo()
    dmginfo:SetDamage(dmg)
    dmginfo:SetAttacker(attacker)
    dmginfo:SetInflictor(attacker)
    dmginfo:SetDamageType(DMG_CRUSH)
    dmginfo:SetDamagePosition(target:GetPos())
    dmginfo:SetDamageForce(impulseVec)
    target:TakeDamageInfo(dmginfo)

    if IsValid(phys) then
        phys:ApplyForceCenter(impulseVec)
    end

    net.Start("GekkoCrushHit")
        net.WriteVector(target:GetPos())
        net.WriteVector(attacker:GetPos())
    net.Broadcast()
end

-- ============================================================
--  Inverse-square damage falloff
--  dmg(0) = dmgMax  |  dmg(radius) = dmgMin
-- ============================================================
local function BlastDamage(dmgMax, dmgMin, dist, radius)
    local k  = (dmgMax / dmgMin) - 1
    local dn = math.Clamp(dist / radius, 0, 1)
    return dmgMax / (1 + k * dn * dn)
end

-- ============================================================
--  1. WALK CRUSH
-- ============================================================
local WALK_CRUSH_DIST     = 96
local WALK_CRUSH_WIDTH    = 50
local WALK_CRUSH_DAMAGE   = 25
local WALK_CRUSH_SPEED    = 30
local WALK_CRUSH_COOLDOWN = 1.0
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
    local impulse  = (fwd + Vector(0, 0, 0.3)):GetNormalized() * WALK_CRUSH_IMPULSE
    CrushDamageEnt(self, hit, dmg, impulse)

    print(string.format("[GekkoCrush] Walk hit: %s  dmg=%.1f  dot=%.2f", hit:GetClass(), dmg, dot))
end

-- ============================================================
--  2. LAUNCH BLAST
--  Inverse-square: max=60 at dist=0, min=2 at dist=radius(220)
-- ============================================================
local LAUNCH_RADIUS     = 220
local LAUNCH_DAMAGE_MAX = 40
local LAUNCH_DAMAGE_MIN = 1
local LAUNCH_IMPULSE    = 18000

function ENT:GeckoCrush_LaunchBlast()
    local origin = self:GetPos() + Vector(0, 0, 40)

    for _, ent in ipairs(ents.FindInSphere(origin, LAUNCH_RADIUS)) do
        if ent == self then continue end  -- explicit self-skip before anything else
        if not ent:IsNPC() and not ent:IsPlayer() and not IsValid(ent:GetPhysicsObject()) then continue end

        local dist    = ent:GetPos():Distance(origin)
        local dmg     = BlastDamage(LAUNCH_DAMAGE_MAX, LAUNCH_DAMAGE_MIN, dist, LAUNCH_RADIUS)
        local dir     = (ent:GetPos() - origin):GetNormalized()
        local impulse = (dir + Vector(0, 0, 0.5)):GetNormalized() * LAUNCH_IMPULSE
        CrushDamageEnt(self, ent, dmg, impulse)
    end

    print(string.format("[GekkoCrush] LaunchBlast  r=%d  dmg=%.0f..%.0f",
        LAUNCH_RADIUS, LAUNCH_DAMAGE_MAX, LAUNCH_DAMAGE_MIN))
end

-- ============================================================
--  3. LAND BLAST
--  Inverse-square: max=80 at dist=0, min=2 at dist=radius(300)
--
--  After firing, we re-zero the Gekko's velocity one tick later
--  so physics impulse leakage cannot bounce it into the skybox.
-- ============================================================
local LAND_RADIUS     = 300
local LAND_DAMAGE_MAX = 60
local LAND_DAMAGE_MIN = 1
local LAND_IMPULSE    = 22000

function ENT:GeckoCrush_LandBlast()
    local origin = self:GetPos() + Vector(0, 0, 20)
    local self_ref = self  -- upvalue for timer closure

    for _, ent in ipairs(ents.FindInSphere(origin, LAND_RADIUS)) do
        if ent == self then continue end  -- explicit self-skip
        if not ent:IsNPC() and not ent:IsPlayer() and not IsValid(ent:GetPhysicsObject()) then continue end

        local dist    = ent:GetPos():Distance(origin)
        local dmg     = BlastDamage(LAND_DAMAGE_MAX, LAND_DAMAGE_MIN, dist, LAND_RADIUS)
        local dir     = (ent:GetPos() - origin):GetNormalized()
        local impulse = (dir + Vector(0, 0, 1.2)):GetNormalized() * LAND_IMPULSE
        CrushDamageEnt(self, ent, dmg, impulse)
    end

    -- Safety net: physics solver may still impart velocity on the Gekko
    -- from objects it just blasted. Re-zero one tick later.
    timer.Simple(0, function()
        if not IsValid(self_ref) then return end
        local vel = self_ref:GetVelocity()
        -- Only intervene if something crazy happened (z > 50 means it got launched)
        if vel.z > 50 then
            self_ref:SetVelocity(Vector(0, 0, 0))
            print("[GekkoCrush] LandBlast velocity correction fired (velZ was " .. math.Round(vel.z) .. ")")
        end
    end)

    print(string.format("[GekkoCrush] LandBlast  r=%d  dmg=%.0f..%.0f",
        LAND_RADIUS, LAND_DAMAGE_MAX, LAND_DAMAGE_MIN))
end