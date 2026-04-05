-- ============================================================
--  npc_vj_gekko / crush_system.lua
--
--  Three independent crush / blast systems:
--
--  1. Walk Crush   -- front hull sweep while walking/running.
--                     Fires exactly ONE of three attacks per
--                     cooldown window (mutually exclusive):
--
--                       * SPIN KICK  (40% chance)
--                           GekkoSpinKickPulse
--                           360 sphere, same radius as kick (96 u).
--                           No speed gate.  No angle gate.
--                           Uses ents.FindInSphere — hits targets
--                           in every direction including behind.
--
--                       * HEADBUTT   (30% chance)
--                           GekkoHeadbuttPulse
--                           Same 96 u sphere.  No speed gate.
--                           No minimum range.
--
--                       * KICK       (remaining 30% chance)
--                           GekkoKickPulse
--                           Hull sweep forward.  Speed gate >= 30.
--
--                     Priority when the chosen attack has no valid
--                     target: falls through to the next tier.
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
local CRUSH_RADIUS        = 96    -- shared by all three melee attacks
local CRUSH_COOLDOWN      = 1.0

-- Spin kick
local SPINKICK_CHANCE     = 0.40
local SPINKICK_DAMAGE     = 30
local SPINKICK_IMPULSE    = 10000

-- Headbutt
local HEADBUTT_CHANCE     = 0.30   -- evaluated only if spinkick lost
local HEADBUTT_DAMAGE     = 20
local HEADBUTT_IMPULSE    = 7000

-- Kick (forward hull sweep, speed-gated)
local WALK_CRUSH_WIDTH    = 50
local WALK_CRUSH_DAMAGE   = 25
local WALK_CRUSH_SPEED    = 30
local WALK_CRUSH_IMPULSE  = 9000

function ENT:GeckoCrush_Think()
    if self:GetGekkoJumpState() ~= self.JUMP_NONE then return end

    local now  = CurTime()
    local pos  = self:GetPos() + Vector(0, 0, 80)
    local fwd  = self:GetForward()
    local speed = self:GetNWFloat("GekkoSpeed", 0)

    if not self._crushHitTimes then self._crushHitTimes = {} end

    -- ----------------------------------------------------------------
    --  Gather candidates once (sphere covers all three attack ranges)
    -- ----------------------------------------------------------------
    local sphereTargets = {}
    for _, ent in ipairs(ents.FindInSphere(pos, CRUSH_RADIUS)) do
        if ent == self then continue end
        if not ent:IsNPC() and not ent:IsPlayer() then continue end
        table.insert(sphereTargets, ent)
    end

    -- Kick needs a hull-sweep target (speed-gated, forward only)
    local kickTarget = nil
    if speed >= WALK_CRUSH_SPEED then
        local sweep = pos + fwd * CRUSH_RADIUS
        local half  = Vector(WALK_CRUSH_WIDTH, WALK_CRUSH_WIDTH, WALK_CRUSH_WIDTH)
        local tr = util.TraceHull({
            start  = pos,
            endpos = sweep,
            mins   = -half,
            maxs   =  half,
            filter = self,
            mask   = MASK_SHOT_HULL,
        })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            kickTarget = tr.Entity
        end
    end

    -- Nothing reachable at all
    if #sphereTargets == 0 and not kickTarget then return end

    -- ----------------------------------------------------------------
    --  Closest sphere target (used by spin kick and headbutt)
    -- ----------------------------------------------------------------
    local closestTarget = nil
    local closestDistSq = math.huge
    for _, ent in ipairs(sphereTargets) do
        local dsq = pos:DistToSqr(ent:GetPos())
        if dsq < closestDistSq then
            closestDistSq = dsq
            closestTarget = ent
        end
    end

    -- ----------------------------------------------------------------
    --  3-way coin flip
    --  Roll once: [0, SPINKICK_CHANCE)        -> spin kick
    --             [SPINKICK_CHANCE, SK+HB)    -> headbutt
    --             else                        -> kick
    --  If the chosen attack has no valid target, fall through in order:
    --  spinkick -> headbutt -> kick -> abort
    -- ----------------------------------------------------------------
    local roll = math.random()
    local doSpinkick  = (roll < SPINKICK_CHANCE)
    local doHeadbutt  = (not doSpinkick) and (roll < SPINKICK_CHANCE + HEADBUTT_CHANCE)
    local doKick      = (not doSpinkick) and (not doHeadbutt)

    -- Fall-through: if preferred attack has no target, try next
    if doSpinkick  and not IsValid(closestTarget) then doSpinkick = false; doHeadbutt = true  end
    if doHeadbutt  and not IsValid(closestTarget) then doHeadbutt = false; doKick     = true  end
    if doKick      and not IsValid(kickTarget)    then return end

    -- ----------------------------------------------------------------
    --  Execute chosen attack
    -- ----------------------------------------------------------------
    if doSpinkick then
        local target  = closestTarget
        local lastHit = self._crushHitTimes[target] or 0
        if now - lastHit < CRUSH_COOLDOWN then return end
        self._crushHitTimes[target] = now

        -- Impulse radiates outward from Gekko centre
        local dir     = (target:GetPos() - self:GetPos()):GetNormalized()
        local impulse = (dir + Vector(0, 0, 0.4)):GetNormalized() * SPINKICK_IMPULSE
        CrushDamageEnt(self, target, SPINKICK_DAMAGE, impulse)

        local prev = self:GetNWInt("GekkoSpinKickPulse", 0)
        self:SetNWInt("GekkoSpinKickPulse", (prev % 254) + 1)

        print(string.format("[GekkoCrush] SPINKICK  target=%s  skPulse=%d",
            target:GetClass(), self:GetNWInt("GekkoSpinKickPulse", 0)))

    elseif doHeadbutt then
        local target  = closestTarget
        local lastHit = self._crushHitTimes[target] or 0
        if now - lastHit < CRUSH_COOLDOWN then return end
        self._crushHitTimes[target] = now

        local impulse = (fwd + Vector(0, 0, 0.3)):GetNormalized() * HEADBUTT_IMPULSE
        CrushDamageEnt(self, target, HEADBUTT_DAMAGE, impulse)

        local prev = self:GetNWInt("GekkoHeadbuttPulse", 0)
        self:SetNWInt("GekkoHeadbuttPulse", (prev % 254) + 1)

        print(string.format("[GekkoCrush] HEADBUTT  target=%s  hbPulse=%d",
            target:GetClass(), self:GetNWInt("GekkoHeadbuttPulse", 0)))

    else -- doKick
        local target  = kickTarget
        local lastHit = self._crushHitTimes[target] or 0
        if now - lastHit < CRUSH_COOLDOWN then return end
        self._crushHitTimes[target] = now

        local toTarget = (target:GetPos() - self:GetPos()):GetNormalized()
        local dot      = math.Clamp(fwd:Dot(toTarget), 0.5, 1.0)
        local dmg      = WALK_CRUSH_DAMAGE * dot
        local impulse  = (fwd + Vector(0, 0, 0.3)):GetNormalized() * WALK_CRUSH_IMPULSE
        CrushDamageEnt(self, target, dmg, impulse)

        local prev = self:GetNWInt("GekkoKickPulse", 0)
        local next = (prev % 254) + 1
        self:SetNWInt("GekkoKickPulse", next)

        print(string.format("[GekkoCrush] KICK  target=%s  dmg=%.1f  dot=%.2f  kickPulse=%d",
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
