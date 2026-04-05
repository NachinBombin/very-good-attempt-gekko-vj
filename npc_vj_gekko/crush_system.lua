-- ============================================================
--  npc_vj_gekko / crush_system.lua
--
--  Four independent walk-crush attacks (mutually exclusive),
--  plus Launch Blast and Land Blast.
--
--  1. Walk Crush   -- fires exactly ONE of four attacks per
--                     cooldown window:
--
--                       * SPIN KICK      (30% chance)
--                           GekkoSpinKickPulse
--                           360 sphere detection, r=96.
--                           No speed gate. No angle gate.
--
--                       * 360 FRONT KICK (30% chance)
--                           GekkoFrontKick360Pulse
--                           Forward hull sweep, same as kick.
--                           No speed gate.
--
--                       * HEADBUTT       (20% chance)
--                           GekkoHeadbuttPulse
--                           96 u sphere. No speed gate.
--
--                       * KICK           (20% chance)
--                           GekkoKickPulse
--                           Forward hull sweep. Speed gate >= 30.
--
--                     Fall-through: if chosen attack has no valid
--                     target, cascades to the next tier.
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
local CRUSH_RADIUS   = 96     -- shared reach for all attacks
local CRUSH_WIDTH    = 50     -- hull half-extents for sweep attacks
local CRUSH_COOLDOWN = 1.0

-- Spin Kick (360 sphere, no speed gate)
local SK_CHANCE      = 0.30
local SK_DAMAGE      = 30
local SK_IMPULSE     = 10000

-- 360 Front Kick (forward hull sweep, no speed gate)
local FK360_CHANCE   = 0.30
local FK360_DAMAGE   = 30
local FK360_IMPULSE  = 10000

-- Headbutt (sphere, no speed gate)
local HB_CHANCE      = 0.20
local HB_DAMAGE      = 20
local HB_IMPULSE     = 7000

-- Kick (forward hull sweep, speed-gated)
local KICK_DAMAGE    = 25
local KICK_SPEED     = 30
local KICK_IMPULSE   = 9000

-- Shared forward hull sweep helper.
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

function ENT:GeckoCrush_Think()
    if self:GetGekkoJumpState() ~= self.JUMP_NONE then return end

    local now   = CurTime()
    local pos   = self:GetPos() + Vector(0, 0, 80)
    local fwd   = self:GetForward()
    local speed = self:GetNWFloat("GekkoSpeed", 0)

    if not self._crushHitTimes then self._crushHitTimes = {} end

    -- ----------------------------------------------------------------
    --  Gather targets per detection method
    -- ----------------------------------------------------------------

    -- Spin Kick: closest in full sphere
    local skTarget  = nil
    local skDistSq  = math.huge
    for _, ent in ipairs(ents.FindInSphere(pos, CRUSH_RADIUS)) do
        if ent == self then continue end
        if not ent:IsNPC() and not ent:IsPlayer() then continue end
        local dsq = pos:DistToSqr(ent:GetPos())
        if dsq < skDistSq then
            skDistSq = dsq
            skTarget = ent
        end
    end

    -- 360 Front Kick & Kick: forward hull sweep
    local fwdTarget = HullSweepForward(self, pos, fwd)

    -- Kick additionally needs speed gate
    local kickTarget = (speed >= KICK_SPEED) and fwdTarget or nil

    -- Headbutt: reuse sphere closest (same pool as spin kick)
    local hbTarget = skTarget

    if not skTarget and not fwdTarget then return end

    -- ----------------------------------------------------------------
    --  4-way coin flip
    --  [0,            SK_CHANCE)              -> spin kick
    --  [SK,           SK+FK360)               -> 360 front kick
    --  [SK+FK360,     SK+FK360+HB)            -> headbutt
    --  else                                   -> kick
    --  Fall-through if chosen attack has no target.
    -- ----------------------------------------------------------------
    local roll    = math.random()
    local doSK    = (roll < SK_CHANCE)
    local doFK360 = (not doSK)    and (roll < SK_CHANCE + FK360_CHANCE)
    local doHB    = (not doSK)    and (not doFK360) and (roll < SK_CHANCE + FK360_CHANCE + HB_CHANCE)
    local doKick  = (not doSK)    and (not doFK360) and (not doHB)

    -- Fall-through cascade
    if doSK    and not IsValid(skTarget)   then doSK = false;    doFK360 = true  end
    if doFK360 and not IsValid(fwdTarget)  then doFK360 = false; doHB    = true  end
    if doHB    and not IsValid(hbTarget)   then doHB = false;    doKick  = true  end
    if doKick  and not IsValid(kickTarget) then return end

    -- ----------------------------------------------------------------
    --  Execute
    -- ----------------------------------------------------------------
    if doSK then
        local target  = skTarget
        local lastHit = self._crushHitTimes[target] or 0
        if now - lastHit < CRUSH_COOLDOWN then return end
        self._crushHitTimes[target] = now

        -- Impulse radiates outward from Gekko centre
        local dir     = (target:GetPos() - self:GetPos()):GetNormalized()
        local impulse = (dir + Vector(0, 0, 0.4)):GetNormalized() * SK_IMPULSE
        CrushDamageEnt(self, target, SK_DAMAGE, impulse)

        local prev = self:GetNWInt("GekkoSpinKickPulse", 0)
        self:SetNWInt("GekkoSpinKickPulse", (prev % 254) + 1)

        print(string.format("[GekkoCrush] SPINKICK  target=%s  pulse=%d",
            target:GetClass(), self:GetNWInt("GekkoSpinKickPulse", 0)))

    elseif doFK360 then
        local target  = fwdTarget
        local lastHit = self._crushHitTimes[target] or 0
        if now - lastHit < CRUSH_COOLDOWN then return end
        self._crushHitTimes[target] = now

        local impulse = (fwd + Vector(0, 0, 0.4)):GetNormalized() * FK360_IMPULSE
        CrushDamageEnt(self, target, FK360_DAMAGE, impulse)

        local prev = self:GetNWInt("GekkoFrontKick360Pulse", 0)
        self:SetNWInt("GekkoFrontKick360Pulse", (prev % 254) + 1)

        print(string.format("[GekkoCrush] 360FRONTKICK  target=%s  pulse=%d",
            target:GetClass(), self:GetNWInt("GekkoFrontKick360Pulse", 0)))

    elseif doHB then
        local target  = hbTarget
        local lastHit = self._crushHitTimes[target] or 0
        if now - lastHit < CRUSH_COOLDOWN then return end
        self._crushHitTimes[target] = now

        local impulse = (fwd + Vector(0, 0, 0.3)):GetNormalized() * HB_IMPULSE
        CrushDamageEnt(self, target, HB_DAMAGE, impulse)

        local prev = self:GetNWInt("GekkoHeadbuttPulse", 0)
        self:SetNWInt("GekkoHeadbuttPulse", (prev % 254) + 1)

        print(string.format("[GekkoCrush] HEADBUTT  target=%s  pulse=%d",
            target:GetClass(), self:GetNWInt("GekkoHeadbuttPulse", 0)))

    else -- doKick
        local target  = kickTarget
        local lastHit = self._crushHitTimes[target] or 0
        if now - lastHit < CRUSH_COOLDOWN then return end
        self._crushHitTimes[target] = now

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
