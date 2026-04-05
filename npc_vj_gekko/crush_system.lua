-- ============================================================
--  npc_vj_gekko / crush_system.lua
--
--  1. WALK CRUSH
--
--     Gate order (evaluated every Think tick):
--
--       a) Find nearest enemy in CRUSH_RADIUS sphere.
--
--       b) Shared cooldown per target (CRUSH_COOLDOWN).
--
--       c) Distance gate:
--            Simple Kick excluded if target is within KICK_MIN_DIST.
--
--       d) Speed gate:
--            Simple Kick excluded if Gekko speed < KICK_SPEED.
--
--       e) Cone check (dot = fwd · toTarget vs CONE_DOT):
--
--            OUTSIDE cone  →  force SPIN KICK (yaw body rotation,
--                              valid from any direction).
--
--            INSIDE cone   →  weighted roll among eligible attacks:
--                              FK360 (pitch/forward flip)
--                              HEADBUTT
--                              SPINKICK
--                              KICK  (only if dist + speed gates pass)
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
    if not IsValid(target) then return end
    if target == attacker  then return end

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

    if IsValid(phys) then phys:ApplyForceCenter(impulseVec) end

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
local CRUSH_RADIUS   = 96      -- detection sphere radius
local CRUSH_COOLDOWN = 1.2     -- seconds between hits on same target

-- Cone threshold (dot product).  0.5 ≈ 60° half-angle.
local CONE_DOT       = 0.5

-- FK360  (pitch / forward flip — in-cone only)
local FK360_DAMAGE   = 30
local FK360_IMPULSE  = 10000
local FK360_WEIGHT   = 2

-- Headbutt  (pitch lunge — in-cone only)
local HB_DAMAGE      = 20
local HB_IMPULSE     = 7000
local HB_WEIGHT      = 2

-- Simple Kick  (in-cone only; distance + speed gated)
local KICK_DAMAGE    = 25
local KICK_IMPULSE   = 9000
local KICK_WEIGHT    = 2
local KICK_MIN_DIST  = 48      -- too close: kick excluded
local KICK_SPEED     = 30      -- too slow:  kick excluded

-- Spin Kick  (yaw body rotation — valid in-cone AND forced out-of-cone)
local SK_DAMAGE      = 35
local SK_IMPULSE     = 11000
local SK_WEIGHT      = 2

-- Sphere scan: closest enemy NPC/player within radius, or nil + dist.
local function SphereNearest(self, pos, radius)
    local best, bestSq = nil, math.huge
    for _, ent in ipairs(ents.FindInSphere(pos, radius)) do
        if ent == self then continue end
        if not ent:IsNPC() and not ent:IsPlayer() then continue end
        local dsq = pos:DistToSqr(ent:GetPos())
        if dsq < bestSq then bestSq = dsq; best = ent end
    end
    return best, (bestSq < math.huge and math.sqrt(bestSq) or 0)
end

function ENT:GeckoCrush_Think()
    if self:GetGekkoJumpState() ~= self.JUMP_NONE then return end

    local now   = CurTime()
    local pos   = self:GetPos() + Vector(0, 0, 80)
    local fwd   = self:GetForward()
    local speed = self:GetNWFloat("GekkoSpeed", 0)

    if not self._crushCooldowns then self._crushCooldowns = {} end

    -- 1. Find nearest target
    local target, dist = SphereNearest(self, pos, CRUSH_RADIUS)
    if not IsValid(target) then return end

    -- 2. Shared cooldown
    local lastHit = self._crushCooldowns[target] or 0
    if now - lastHit < CRUSH_COOLDOWN then return end

    -- 3. Cone check
    local toTarget = (target:GetPos() - self:GetPos()):GetNormalized()
    local dot      = fwd:Dot(toTarget)
    local inCone   = (dot >= CONE_DOT)

    -- 4. Simple kick eligibility (in-cone + distance + speed)
    local kickOk = inCone
                   and (dist > KICK_MIN_DIST)
                   and (speed >= KICK_SPEED)

    -- ----------------------------------------------------------------
    --  5. Select attack
    -- ----------------------------------------------------------------
    local attack

    if not inCone then
        -- Target is outside the forward cone.
        -- SpinKick is a full yaw-body rotation — works from any angle.
        attack = "SPINKICK"
    else
        -- Build weighted pool from eligible in-cone attacks.
        local pool = {}
        pool[#pool+1] = { name="FK360",    w=FK360_WEIGHT }
        pool[#pool+1] = { name="HEADBUTT", w=HB_WEIGHT    }
        pool[#pool+1] = { name="SPINKICK", w=SK_WEIGHT    }
        if kickOk then
            pool[#pool+1] = { name="KICK", w=KICK_WEIGHT  }
        end

        local total = 0
        for _, e in ipairs(pool) do total = total + e.w end

        local roll = math.random() * total
        local acc  = 0
        for _, e in ipairs(pool) do
            acc = acc + e.w
            if roll <= acc then attack = e.name; break end
        end
        attack = attack or pool[#pool].name  -- safety
    end

    -- ----------------------------------------------------------------
    --  6. Execute
    -- ----------------------------------------------------------------
    self._crushCooldowns[target] = now

    if attack == "FK360" then
        local impulse = (fwd + Vector(0, 0, 0.4)):GetNormalized() * FK360_IMPULSE
        CrushDamageEnt(self, target, FK360_DAMAGE, impulse)
        local next = (self:GetNWInt("GekkoFrontKick360Pulse", 0) % 254) + 1
        self:SetNWInt("GekkoFrontKick360Pulse", next)
        print(string.format("[GekkoCrush] FK360(pitch)  target=%s  dot=%.2f  pulse=%d",
            target:GetClass(), dot, next))

    elseif attack == "HEADBUTT" then
        local impulse = (fwd + Vector(0, 0, 0.3)):GetNormalized() * HB_IMPULSE
        CrushDamageEnt(self, target, HB_DAMAGE, impulse)
        local next = (self:GetNWInt("GekkoHeadbuttPulse", 0) % 254) + 1
        self:SetNWInt("GekkoHeadbuttPulse", next)
        print(string.format("[GekkoCrush] HEADBUTT  target=%s  pulse=%d",
            target:GetClass(), next))

    elseif attack == "KICK" then
        local dmg     = KICK_DAMAGE * math.Clamp(dot, 0.5, 1.0)
        local impulse = (fwd + Vector(0, 0, 0.3)):GetNormalized() * KICK_IMPULSE
        CrushDamageEnt(self, target, dmg, impulse)
        local next = (self:GetNWInt("GekkoKickPulse", 0) % 254) + 1
        self:SetNWInt("GekkoKickPulse", next)
        print(string.format("[GekkoCrush] KICK  target=%s  dist=%.0f  spd=%.0f  dmg=%.1f  pulse=%d",
            target:GetClass(), dist, speed, dmg, next))

    else -- SPINKICK (yaw) — in-cone roll OR forced out-of-cone
        local dir     = (target:GetPos() - self:GetPos()):GetNormalized()
        local impulse = (dir + Vector(0, 0, 0.4)):GetNormalized() * SK_IMPULSE
        CrushDamageEnt(self, target, SK_DAMAGE, impulse)
        local next = (self:GetNWInt("GekkoSpinKickPulse", 0) % 254) + 1
        self:SetNWInt("GekkoSpinKickPulse", next)
        print(string.format("[GekkoCrush] SPINKICK(yaw)  target=%s  inCone=%s  dot=%.2f  pulse=%d",
            target:GetClass(), tostring(inCone), dot, next))
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
