-- ============================================================
--  npc_vj_gekko / crush_system.lua
--
--  Three independent crush / blast systems:
--
--  1. Walk Crush   -- four attacks, all evaluated independently:
--
--       * 360 FRONT KICK  (independent, own cooldown)
--           GekkoFrontKick360Pulse
--           Forward hull sweep.  Angle-gated only (no speed gate).
--           Fires whenever a target is in the forward arc,
--           on its own FK360_COOLDOWN timer.
--
--       * HEADBUTT         (25% of lottery roll)
--           GekkoHeadbuttPulse
--           96 u sphere.  No speed gate.
--
--       * KICK             (45% of lottery roll)
--           GekkoKickPulse
--           Forward hull sweep.  Speed gate >= 30.
--
--       * SPIN KICK        (30% of lottery roll)
--           GekkoSpinKickPulse
--           96 u sphere AoE.  No speed gate.
--
--     Each attack has its own per-target cooldown table so they
--     never suppress one another.
--
--  2. Launch Blast -- sphere damage at jump takeoff
--  3. Land Blast   -- sphere damage + knockup on landing
-- ============================================================

if SERVER then
    util.AddNetworkString("GekkoCrushHit")
end

-- ============================================================
--  Shared helper: apply damage + physics impulse to one entity.
-- ============================================================
local function CrushDamageEnt(attacker, target, dmg, impulseVec)
    if not IsValid(target)  then return end
    if target == attacker   then return end

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
-- ============================================================
local function BlastDamage(dmgMax, dmgMin, dist, radius)
    local k  = (dmgMax / dmgMin) - 1
    local dn = math.Clamp(dist / radius, 0, 1)
    return dmgMax / (1 + k * dn * dn)
end

-- ============================================================
--  1. WALK CRUSH
-- ============================================================
local CRUSH_RADIUS   = 96    -- shared reach for all attacks
local CRUSH_WIDTH    = 50    -- hull half-extents for sweep attacks

-- 360 Front Kick: independent, angle-gated only, own cooldown
local FK360_COOLDOWN = 1.2
local FK360_DAMAGE   = 30
local FK360_IMPULSE  = 10000

-- Headbutt (sphere, no speed gate)
local HEADBUTT_CHANCE   = 0.25
local HEADBUTT_COOLDOWN = 1.0
local HEADBUTT_DAMAGE   = 20
local HEADBUTT_IMPULSE  = 7000

-- Kick (forward hull sweep, speed-gated)
local KICK_CHANCE   = 0.45
local KICK_COOLDOWN = 1.0
local KICK_DAMAGE   = 25
local KICK_SPEED    = 30
local KICK_IMPULSE  = 9000

-- Spin Kick (sphere AoE, full 360 body spin, no speed gate)
local SK_COOLDOWN = 1.0
local SK_DAMAGE   = 35
local SK_IMPULSE  = 11000

-- Forward hull sweep: returns first NPC/player hit, or nil.
local function HullSweepForward(self, pos, fwd)
    local sweep = pos + fwd * CRUSH_RADIUS
    local half  = Vector(CRUSH_WIDTH, CRUSH_WIDTH, CRUSH_WIDTH)
    local tr = util.TraceHull({
        start  = pos,
        endpos = sweep,
        mins   = -half,
        maxs   =  half,
        filter = self,
        mask   = MASK_SHOT_HULL,
    })
    if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
        return tr.Entity
    end
    return nil
end

-- Sphere scan: returns closest NPC/player in CRUSH_RADIUS, or nil.
local function SphereNearest(self, pos)
    local best   = nil
    local bestSq = math.huge
    for _, ent in ipairs(ents.FindInSphere(pos, CRUSH_RADIUS)) do
        if ent == self then continue end
        if not ent:IsNPC() and not ent:IsPlayer() then continue end
        local dsq = pos:DistToSqr(ent:GetPos())
        if dsq < bestSq then
            bestSq = dsq
            best   = ent
        end
    end
    return best
end

function ENT:GeckoCrush_Think()
    if self:GetGekkoJumpState() ~= self.JUMP_NONE then return end

    local now   = CurTime()
    local pos   = self:GetPos() + Vector(0, 0, 80)
    local fwd   = self:GetForward()
    local speed = self:GetNWFloat("GekkoSpeed", 0)

    -- Per-attack independent cooldown tables (keyed by target entity)
    if not self._crushHitFK360   then self._crushHitFK360   = {} end
    if not self._crushHitHB      then self._crushHitHB      = {} end
    if not self._crushHitKick    then self._crushHitKick    = {} end
    if not self._crushHitSK      then self._crushHitSK      = {} end

    -- ----------------------------------------------------------------
    --  360 FRONT KICK: independent check, runs every Think tick.
    --  Fires as soon as a target enters the forward arc, on its own
    --  cooldown.  Not part of the lottery below.
    -- ----------------------------------------------------------------
    local fk360Target = HullSweepForward(self, pos, fwd)
    if IsValid(fk360Target) then
        local lastHit = self._crushHitFK360[fk360Target] or 0
        if now - lastHit >= FK360_COOLDOWN then
            self._crushHitFK360[fk360Target] = now

            local impulse = (fwd + Vector(0, 0, 0.4)):GetNormalized() * FK360_IMPULSE
            CrushDamageEnt(self, fk360Target, FK360_DAMAGE, impulse)

            local prev = self:GetNWInt("GekkoFrontKick360Pulse", 0)
            local next = (prev % 254) + 1
            self:SetNWInt("GekkoFrontKick360Pulse", next)

            print(string.format("[GekkoCrush] 360FRONTKICK  target=%s  pulse=%d",
                fk360Target:GetClass(), next))
        end
    end

    -- ----------------------------------------------------------------
    --  LOTTERY: headbutt / kick / spin-kick (mutually exclusive per tick)
    --  Each has its own cooldown table so FK360 never blocks them.
    -- ----------------------------------------------------------------

    -- Gather targets
    local hbTarget   = SphereNearest(self, pos)
    local kickTarget = (speed >= KICK_SPEED) and HullSweepForward(self, pos, fwd) or nil
    local skTarget   = SphereNearest(self, pos)

    if not hbTarget and not kickTarget and not skTarget then return end

    -- Weighted roll among the three remaining attacks
    local roll   = math.random()
    local doHB   = (roll < HEADBUTT_CHANCE)
    local doKick = (not doHB) and (roll < HEADBUTT_CHANCE + KICK_CHANCE)
    local doSK   = (not doHB) and (not doKick)

    -- Fall-through cascade
    if doHB   and not IsValid(hbTarget)   then doHB = false;   doKick = true  end
    if doKick and not IsValid(kickTarget) then doKick = false;  doSK   = true  end
    if doSK   and not IsValid(skTarget)   then return end

    if doHB then
        local target  = hbTarget
        local lastHit = self._crushHitHB[target] or 0
        if now - lastHit < HEADBUTT_COOLDOWN then return end
        self._crushHitHB[target] = now

        local impulse = (fwd + Vector(0, 0, 0.3)):GetNormalized() * HEADBUTT_IMPULSE
        CrushDamageEnt(self, target, HEADBUTT_DAMAGE, impulse)

        local prev = self:GetNWInt("GekkoHeadbuttPulse", 0)
        local next = (prev % 254) + 1
        self:SetNWInt("GekkoHeadbuttPulse", next)

        print(string.format("[GekkoCrush] HEADBUTT  target=%s  pulse=%d",
            target:GetClass(), next))

    elseif doKick then
        local target  = kickTarget
        local lastHit = self._crushHitKick[target] or 0
        if now - lastHit < KICK_COOLDOWN then return end
        self._crushHitKick[target] = now

        local toTarget = (target:GetPos() - self:GetPos()):GetNormalized()
        local dot      = math.Clamp(fwd:Dot(toTarget), 0.5, 1.0)
        local dmg      = KICK_DAMAGE * dot
        local impulse  = (fwd + Vector(0, 0, 0.3)):GetNormalized() * KICK_IMPULSE
        CrushDamageEnt(self, target, dmg, impulse)

        local prev = self:GetNWInt("GekkoKickPulse", 0)
        local next = (prev % 254) + 1
        self:SetNWInt("GekkoKickPulse", next)

        print(string.format("[GekkoCrush] KICK  target=%s  dmg=%.1f  dot=%.2f  pulse=%d",
            target:GetClass(), dmg, dot, next))

    else -- doSK
        local target  = skTarget
        local lastHit = self._crushHitSK[target] or 0
        if now - lastHit < SK_COOLDOWN then return end
        self._crushHitSK[target] = now

        local dir     = (target:GetPos() - self:GetPos()):GetNormalized()
        local impulse = (dir + Vector(0, 0, 0.4)):GetNormalized() * SK_IMPULSE
        CrushDamageEnt(self, target, SK_DAMAGE, impulse)

        local prev = self:GetNWInt("GekkoSpinKickPulse", 0)
        local next = (prev % 254) + 1
        self:SetNWInt("GekkoSpinKickPulse", next)

        print(string.format("[GekkoCrush] SPINKICK  target=%s  dmg=%d  pulse=%d",
            target:GetClass(), SK_DAMAGE, next))
    end
end

-- ============================================================
--  2. LAUNCH BLAST
-- ============================================================
local LAUNCH_RADIUS     = 220
local LAUNCH_DAMAGE_MAX = 40
local LAUNCH_DAMAGE_MIN = 1
local LAUNCH_IMPULSE    = 18000

function ENT:GeckoCrush_LaunchBlast()
    local origin = self:GetPos() + Vector(0, 0, 40)

    for _, ent in ipairs(ents.FindInSphere(origin, LAUNCH_RADIUS)) do
        if ent == self then continue end
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
-- ============================================================
local LAND_RADIUS     = 300
local LAND_DAMAGE_MAX = 60
local LAND_DAMAGE_MIN = 1
local LAND_IMPULSE    = 22000

function ENT:GeckoCrush_LandBlast()
    local origin   = self:GetPos() + Vector(0, 0, 20)
    local self_ref = self

    for _, ent in ipairs(ents.FindInSphere(origin, LAND_RADIUS)) do
        if ent == self then continue end
        if not ent:IsNPC() and not ent:IsPlayer() and not IsValid(ent:GetPhysicsObject()) then continue end

        local dist    = ent:GetPos():Distance(origin)
        local dmg     = BlastDamage(LAND_DAMAGE_MAX, LAND_DAMAGE_MIN, dist, LAND_RADIUS)
        local dir     = (ent:GetPos() - origin):GetNormalized()
        local impulse = (dir + Vector(0, 0, 1.2)):GetNormalized() * LAND_IMPULSE
        CrushDamageEnt(self, ent, dmg, impulse)
    end

    timer.Simple(0, function()
        if not IsValid(self_ref) then return end
        local vel = self_ref:GetVelocity()
        if vel.z > 50 then
            self_ref:SetVelocity(Vector(0, 0, 0))
            print("[GekkoCrush] LandBlast velocity correction fired (velZ was " .. math.Round(vel.z) .. ")")
        end
    end)

    print(string.format("[GekkoCrush] LandBlast  r=%d  dmg=%.0f..%.0f",
        LAND_RADIUS, LAND_DAMAGE_MAX, LAND_DAMAGE_MIN))
end
