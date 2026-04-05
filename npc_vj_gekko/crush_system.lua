-- ============================================================
--  npc_vj_gekko / crush_system.lua
--
--  Three independent crush / blast systems:
--
--  1. Walk Crush   -- front hull sweep while walking/running.
--                     Fires KICK OR HEADBUTT, never both:
--                       * 30% chance -> HEADBUTT (GekkoHeadbuttPulse)
--                           No speed gate.  No minimum range.
--                           Uses its own wider sphere check so the
--                           player can be literally on top of the Gekko.
--                       * 70% chance -> KICK (GekkoKickPulse)
--                           Speed gate + hull sweep as before.
--  2. Launch Blast -- sphere damage at jump takeoff
--  3. Land Blast   -- sphere damage + knockup on landing
-- ============================================================

if SERVER then
    util.AddNetworkString("GekkoCrushHit")
end

-- ============================================================
--  Shared helper: apply damage + physics impulse to a single entity.
-- ============================================================
local function CrushDamageEnt(attacker, target, dmg, impulseVec)
    if not IsValid(target)        then return end
    if target == attacker         then return end

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
local WALK_CRUSH_DIST      = 96
local WALK_CRUSH_WIDTH     = 50
local WALK_CRUSH_DAMAGE    = 25
local WALK_CRUSH_SPEED     = 30    -- minimum speed for the KICK path
local WALK_CRUSH_COOLDOWN  = 1.0
local WALK_CRUSH_IMPULSE   = 9000

-- Headbutt: 30% chance, no speed gate, radius covers point-blank range.
-- When headbutt wins the coin-flip the kick is suppressed entirely.
local HEADBUTT_CHANCE      = 0.30
local HEADBUTT_RADIUS      = 96    -- same reach as hull sweep
local HEADBUTT_DAMAGE      = 20
local HEADBUTT_IMPULSE     = 7000

function ENT:GeckoCrush_Think()
    if self:GetGekkoJumpState() ~= self.JUMP_NONE then return end

    local now = CurTime()
    if not self._crushHitTimes then self._crushHitTimes = {} end

    -- ---- Shared cooldown check: find closest valid target -------
    -- We need one target to gate the cooldown against.  We look for
    -- the closest NPC/Player within headbutt radius first (no speed
    -- gate), then fall back to the hull-sweep for the kick path.

    local speed = self:GetNWFloat("GekkoSpeed", 0)
    local pos   = self:GetPos() + Vector(0, 0, 80)
    local fwd   = self:GetForward()

    -- Find closest NPC/player within headbutt sphere (no speed req)
    local hbTarget = nil
    local hbDistSq = math.huge
    for _, ent in ipairs(ents.FindInSphere(pos, HEADBUTT_RADIUS)) do
        if ent == self then continue end
        if not ent:IsNPC() and not ent:IsPlayer() then continue end
        local dsq = pos:DistToSqr(ent:GetPos())
        if dsq < hbDistSq then
            hbDistSq = dsq
            hbTarget = ent
        end
    end

    -- Hull sweep for kick (speed-gated)
    local kickTarget = nil
    if speed >= WALK_CRUSH_SPEED then
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
        if IsValid(hit) and (hit:IsNPC() or hit:IsPlayer()) then
            kickTarget = hit
        end
    end

    -- Nothing in range at all
    if not hbTarget and not kickTarget then return end

    -- ---- Coin flip: headbutt OR kick (never both) ---------------
    local doHeadbutt = (math.random() < HEADBUTT_CHANCE)

    if doHeadbutt then
        -- Headbutt path -- requires hbTarget (no speed gate)
        if not IsValid(hbTarget) then return end

        local lastHit = self._crushHitTimes[hbTarget] or 0
        if now - lastHit < WALK_CRUSH_COOLDOWN then return end
        self._crushHitTimes[hbTarget] = now

        local impulse = (fwd + Vector(0, 0, 0.3)):GetNormalized() * HEADBUTT_IMPULSE
        CrushDamageEnt(self, hbTarget, HEADBUTT_DAMAGE, impulse)

        local hbPrev = self:GetNWInt("GekkoHeadbuttPulse", 0)
        self:SetNWInt("GekkoHeadbuttPulse", (hbPrev % 254) + 1)

        print(string.format(
            "[GekkoCrush] HEADBUTT  target=%s  hbPulse=%d",
            hbTarget:GetClass(), (self:GetNWInt("GekkoHeadbuttPulse", 0))
        ))

    else
        -- Kick path -- requires kickTarget + speed gate
        if not IsValid(kickTarget) then return end

        local lastHit = self._crushHitTimes[kickTarget] or 0
        if now - lastHit < WALK_CRUSH_COOLDOWN then return end
        self._crushHitTimes[kickTarget] = now

        local toTarget = (kickTarget:GetPos() - self:GetPos()):GetNormalized()
        local dot      = math.Clamp(fwd:Dot(toTarget), 0.5, 1.0)
        local dmg      = WALK_CRUSH_DAMAGE * dot
        local impulse  = (fwd + Vector(0, 0, 0.3)):GetNormalized() * WALK_CRUSH_IMPULSE
        CrushDamageEnt(self, kickTarget, dmg, impulse)

        local kickPrev = self:GetNWInt("GekkoKickPulse", 0)
        local kickNext = (kickPrev % 254) + 1
        self:SetNWInt("GekkoKickPulse", kickNext)

        print(string.format(
            "[GekkoCrush] KICK  target=%s  dmg=%.1f  dot=%.2f  kickPulse=%d",
            kickTarget:GetClass(), dmg, dot, kickNext
        ))
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
    local origin = self:GetPos() + Vector(0, 0, 20)
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
