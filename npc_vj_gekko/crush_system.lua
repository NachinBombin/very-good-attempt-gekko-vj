-- ============================================================
--  npc_vj_gekko / crush_system.lua
--
--  WALK CRUSH — fires one attack per cooldown window.
--
--  Gate order evaluated every Think tick:
--
--    1. Distance gate:
--         Simple Kick excluded if dist <= KICK_MIN_DIST.
--
--    2. Speed gate:
--         Simple Kick excluded if Gekko speed < KICK_SPEED.
--
--    3. Cone check (dot = fwd . toTarget vs CONE_DOT = 0.5):
--
--         OUTSIDE cone  ->  force SPINKICK (b_Pedestal yaw, any dir)
--
--         INSIDE cone   ->  weighted roll:
--                             FK360     25%  (b_pelvis flip, front only)
--                             HEADBUTT  20%
--                             KICK      20%  (only if dist+speed gates pass)
--                             SPINKICK  15%
--                             FKICK     20%  (football kick, front only)
--
--         If Kick is excluded from pool its weight redistributes
--         proportionally among the remaining four.
--
--  FK360 HIT TIMING:
--    Hit 1 (launch) — fires immediately when FK360 is selected.
--                     forward impulse, single target.
--    Hit 2 (landing kick) — fires after ENT.FK360_DURATION seconds
--                     (read from shared.lua — do NOT hardcode here).
--                     full 360-degree sphere (no cone — spin means
--                     rear targets hit equally), outward impulse,
--                     pulses GekkoFK360LandDust for ThumperDust.
--
--  FOOTBALL KICK HIT TIMING:
--    Hit fires at phase 3 (leg extension) after FKICK_HIT_DELAY seconds.
--    Forward cone sweep, single closest target.
--    Leg slowly returns to neutral over phase 4.
--
--  LAUNCH BLAST  — sphere damage at jump takeoff.
--  LAND BLAST    — sphere damage + knockup on landing.
-- ============================================================

if SERVER then
    util.AddNetworkString("GekkoCrushHit")
    util.AddNetworkString("GekkoSpinKickPulse")      -- true yaw spin
    util.AddNetworkString("GekkoFootballKickPulse")  -- football kick
end

-- ============================================================
--  Shared helper: damage + physics impulse on one entity.
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
--  ClaimKickLock
--
--  Sets _gekkoSuppressActivity and PauseAttacks for the given
--  duration so the range-attack system and GekkoUpdateAnimation
--  are both blocked while a kick animation plays.
-- ============================================================
local function ClaimKickLock(ent, duration)
    local until_t = CurTime() + duration
    ent._gekkoSuppressActivity = until_t
    ent.PauseAttacks = true
    timer.Create("gekko_kick_pauserelease" .. ent:EntIndex(), duration, 1, function()
        if IsValid(ent) then
            ent.PauseAttacks = false
        end
    end)
end

-- ============================================================
--  1. WALK CRUSH
-- ============================================================
local CRUSH_RADIUS   = 96
local CRUSH_COOLDOWN = 1.0
local CONE_DOT       = 0.5   -- ~60 deg half-angle forward cone

-- FK360  (b_pelvis Angle(0,val,0) -- forward flip, front-cone only)
-- Hit 1: immediate launch, single target, forward impulse.
-- Hit 2: after ENT.FK360_DURATION (from shared.lua), full sphere, outward impulse + ThumperDust.
-- NOTE: do NOT define a local FK360_DURATION here — use self.FK360_DURATION at call time.
local FK360_DAMAGE        = 30
local FK360_IMPULSE       = 10000
local FK360_W             = 25   -- was 30, reduced to make room for FKICK
local FK360_LAND_RADIUS   = 160
local FK360_LAND_DMG_MAX  = 45
local FK360_LAND_DMG_MIN  = 5
local FK360_LAND_IMPULSE  = 13000

-- Headbutt
local HB_DAMAGE      = 20
local HB_IMPULSE     = 7000
local HB_W           = 20   -- was 25

-- Simple Kick  (hull sweep forward; dist + speed gated)
local KICK_DAMAGE    = 25
local KICK_IMPULSE   = 9000
local KICK_W         = 20   -- was 25
local KICK_MIN_DIST  = 48
local KICK_SPEED     = 30
local WALK_CRUSH_WIDTH = 50

-- SpinKick  (b_Pedestal yaw; forced out-of-cone, also in-cone at 15%)
local SK_DAMAGE      = 35
local SK_IMPULSE     = 11000
local SK_W           = 15   -- was 20

-- ============================================================
--  Football Kick (FKICK)
--
--  4-phase animation (see cl_init.lua GekkoDoFootballKickBone):
--    Phase 1  t 0.00-0.20  preparation  b_l_hippiston1 ramps to Y=105, X=36
--                                       b_r_hippiston1 ramps to X=36 (stabilise)
--    Phase 2  t 0.20-0.45  hold         stabilisation, force accumulation
--    Phase 3  t 0.45-0.65  extension    b_l_hippiston1 drives Y to -105 (kick out)
--    Phase 4  t 0.65-1.00  recovery     all bones ease back to zero
--
--  Hit fires at FKICK_HIT_DELAY (phase 3 midpoint) as a forward hull sweep.
--  Total duration: FKICK_DURATION = 1.1 s
--  Lock:           FKICK_DURATION + 0.1 s safety margin
-- ============================================================
local FKICK_W             = 20
local FKICK_DAMAGE        = 30
local FKICK_IMPULSE       = 10500
local FKICK_DURATION      = 1.1
local FKICK_HIT_DELAY     = 0.55    -- midpoint of phase 3 (t=0.45..0.65)
local FKICK_SWEEP_RADIUS  = 120     -- forward hull sweep length
local FKICK_SWEEP_WIDTH   = 55      -- half-extents of hull

function ENT:GeckoCrush_Think()
    if self:GetGekkoJumpState() ~= self.JUMP_NONE then return end

    -- ── Mutual exclusion gate ─────────────────────────────────
    local now = CurTime()
    if now < (self._gekkoSuppressActivity or 0) then return end
    if self.PauseAttacks then return end
    if self.AttackAnimTime and self.AttackAnimTime > now then return end

    local pos   = self:GetPos() + Vector(0, 0, 80)
    local fwd   = self:GetForward()
    local speed = self:GetNWFloat("GekkoSpeed", 0)

    if not self._crushHitTimes then self._crushHitTimes = {} end

    -- ----------------------------------------------------------------
    --  Gather candidates
    -- ----------------------------------------------------------------
    local sphereTargets = {}
    for _, ent in ipairs(ents.FindInSphere(pos, CRUSH_RADIUS)) do
        if ent == self then continue end
        if not ent:IsNPC() and not ent:IsPlayer() then continue end
        table.insert(sphereTargets, ent)
    end

    local closestTarget, closestDistSq = nil, math.huge
    for _, ent in ipairs(sphereTargets) do
        local dsq = pos:DistToSqr(ent:GetPos())
        if dsq < closestDistSq then closestDistSq = dsq; closestTarget = ent end
    end

    if not IsValid(closestTarget) then return end

    local lastHit = self._crushHitTimes[closestTarget] or 0
    if now - lastHit < CRUSH_COOLDOWN then return end

    -- ----------------------------------------------------------------
    --  Gate checks
    -- ----------------------------------------------------------------
    local dist      = math.sqrt(closestDistSq)
    local toTarget  = (closestTarget:GetPos() - self:GetPos()):GetNormalized()
    local dot       = fwd:Dot(toTarget)
    local inCone    = (dot >= CONE_DOT)

    local kickTarget = nil
    if inCone and dist > KICK_MIN_DIST and speed >= KICK_SPEED then
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

    -- ----------------------------------------------------------------
    --  Attack selection
    -- ----------------------------------------------------------------
    local attack

    if not inCone then
        attack = "SPINKICK"
    else
        local pool = {}
        pool[#pool+1] = { name = "FK360",    w = FK360_W }
        pool[#pool+1] = { name = "HEADBUTT", w = HB_W    }
        pool[#pool+1] = { name = "SPINKICK", w = SK_W    }
        pool[#pool+1] = { name = "FKICK",    w = FKICK_W }
        if kickTarget then
            pool[#pool+1] = { name = "KICK", w = KICK_W  }
        end

        local total = 0
        for _, e in ipairs(pool) do total = total + e.w end

        local roll = math.random() * total
        local acc  = 0
        for _, e in ipairs(pool) do
            acc = acc + e.w
            if roll <= acc then attack = e.name; break end
        end
        attack = attack or pool[#pool].name
    end

    -- ----------------------------------------------------------------
    --  Execute
    -- ----------------------------------------------------------------
    self._crushHitTimes[closestTarget] = now

    if attack == "FK360" then
        local fk360Dur = self.FK360_DURATION or 0.9
        ClaimKickLock(self, fk360Dur + 0.3)

        local impulse = (fwd + Vector(0, 0, 0.4)):GetNormalized() * FK360_IMPULSE
        CrushDamageEnt(self, closestTarget, FK360_DAMAGE, impulse)

        local next = (self:GetNWInt("GekkoFrontKick360Pulse", 0) % 254) + 1
        self:SetNWInt("GekkoFrontKick360Pulse", next)
        print(string.format("[GekkoCrush] FK360 HIT1  target=%s  dot=%.2f  pulse=%d",
            closestTarget:GetClass(), dot, next))

        local selfRef = self
        timer.Simple(fk360Dur, function()
            if not IsValid(selfRef) then return end
            local origin = selfRef:GetPos() + Vector(0, 0, 40)
            for _, ent in ipairs(ents.FindInSphere(origin, FK360_LAND_RADIUS)) do
                if ent == selfRef then continue end
                if not ent:IsNPC() and not ent:IsPlayer() then continue end
                local entDist    = ent:GetPos():Distance(origin)
                local dmg        = BlastDamage(FK360_LAND_DMG_MAX, FK360_LAND_DMG_MIN,
                                               entDist, FK360_LAND_RADIUS)
                local dir        = (ent:GetPos() - origin):GetNormalized()
                local landImpulse = (dir + Vector(0, 0, 0.35)):GetNormalized() * FK360_LAND_IMPULSE
                CrushDamageEnt(selfRef, ent, dmg, landImpulse)
                print(string.format("[GekkoCrush] FK360 HIT2  target=%s  dist=%.0f  dmg=%.1f",
                    ent:GetClass(), entDist, dmg))
            end
            local dustPulse = (selfRef:GetNWInt("GekkoFK360LandDust", 0) % 254) + 1
            selfRef:SetNWInt("GekkoFK360LandDust", dustPulse)
            print(string.format("[GekkoCrush] FK360 LandDust  dur=%.2f  pulse=%d", fk360Dur, dustPulse))
        end)

    elseif attack == "HEADBUTT" then
        ClaimKickLock(self, 0.55)
        local impulse = (fwd + Vector(0, 0, 0.3)):GetNormalized() * HB_IMPULSE
        CrushDamageEnt(self, closestTarget, HB_DAMAGE, impulse)
        local next = (self:GetNWInt("GekkoHeadbuttPulse", 0) % 254) + 1
        self:SetNWInt("GekkoHeadbuttPulse", next)
        print(string.format("[GekkoCrush] HEADBUTT  target=%s  pulse=%d",
            closestTarget:GetClass(), next))

    elseif attack == "KICK" then
        ClaimKickLock(self, 0.5)
        local target  = kickTarget
        local toT     = (target:GetPos() - self:GetPos()):GetNormalized()
        local dotT    = math.Clamp(fwd:Dot(toT), 0.5, 1.0)
        local dmg     = KICK_DAMAGE * dotT
        local impulse = (fwd + Vector(0, 0, 0.3)):GetNormalized() * KICK_IMPULSE
        CrushDamageEnt(self, target, dmg, impulse)
        local next = (self:GetNWInt("GekkoKickPulse", 0) % 254) + 1
        self:SetNWInt("GekkoKickPulse", next)
        print(string.format("[GekkoCrush] KICK  target=%s  dist=%.0f  spd=%.0f  dmg=%.1f  pulse=%d",
            target:GetClass(), dist, speed, dmg, next))

    elseif attack == "FKICK" then
        -- ── FOOTBALL KICK ──────────────────────────────────────────
        -- Lock lasts the full animation duration + safety margin.
        ClaimKickLock(self, FKICK_DURATION + 0.1)

        -- Signal client bone driver to play the 4-phase animation.
        local next = (self:GetNWInt("GekkoFootballKickPulse", 0) % 254) + 1
        self:SetNWInt("GekkoFootballKickPulse", next)
        print(string.format("[GekkoCrush] FKICK  target=%s  dot=%.2f  pulse=%d  hitDelay=%.2f",
            closestTarget:GetClass(), dot, next, FKICK_HIT_DELAY))

        -- Hit fires at phase 3 midpoint (leg fully extended forward).
        local selfRef      = self
        local capturedFwd  = fwd
        timer.Simple(FKICK_HIT_DELAY, function()
            if not IsValid(selfRef) then return end

            -- Forward hull sweep to find the closest valid target at hit time.
            local hitOrigin = selfRef:GetPos() + Vector(0, 0, 80)
            local hitEnd    = hitOrigin + capturedFwd * FKICK_SWEEP_RADIUS
            local half      = Vector(FKICK_SWEEP_WIDTH, FKICK_SWEEP_WIDTH, FKICK_SWEEP_WIDTH)
            local tr = util.TraceHull({
                start  = hitOrigin,
                endpos = hitEnd,
                mins   = -half,
                maxs   =  half,
                filter = selfRef,
                mask   = MASK_SHOT_HULL,
            })

            local hitTarget = nil
            if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
                hitTarget = tr.Entity
            else
                -- Fallback: nearest entity in cone sphere if hull missed.
                local nearest, nearDsq = nil, math.huge
                for _, ent in ipairs(ents.FindInSphere(hitOrigin, FKICK_SWEEP_RADIUS)) do
                    if ent == selfRef then continue end
                    if not ent:IsNPC() and not ent:IsPlayer() then continue end
                    local toE = (ent:GetPos() - selfRef:GetPos()):GetNormalized()
                    if capturedFwd:Dot(toE) < CONE_DOT then continue end
                    local dsq = hitOrigin:DistToSqr(ent:GetPos())
                    if dsq < nearDsq then nearDsq = dsq; nearest = ent end
                end
                hitTarget = nearest
            end

            if not IsValid(hitTarget) then
                print("[GekkoCrush] FKICK  no target found at hit time")
                return
            end

            -- Impulse: strongly forward and slightly upward (football punt).
            local toHit   = (hitTarget:GetPos() - selfRef:GetPos()):GetNormalized()
            local impulse = (toHit + Vector(0, 0, 0.45)):GetNormalized() * FKICK_IMPULSE
            CrushDamageEnt(selfRef, hitTarget, FKICK_DAMAGE, impulse)
            print(string.format("[GekkoCrush] FKICK  HIT  target=%s  dmg=%d",
                hitTarget:GetClass(), FKICK_DAMAGE))
        end)

    else -- SPINKICK
        ClaimKickLock(self, 0.65)
        local dir     = (closestTarget:GetPos() - self:GetPos()):GetNormalized()
        local impulse = (dir + Vector(0, 0, 0.4)):GetNormalized() * SK_IMPULSE
        CrushDamageEnt(self, closestTarget, SK_DAMAGE, impulse)
        local next = (self:GetNWInt("GekkoSpinKickPulse", 0) % 254) + 1
        self:SetNWInt("GekkoSpinKickPulse", next)
        print(string.format("[GekkoCrush] SPINKICK  target=%s  inCone=%s  dot=%.2f  pulse=%d",
            closestTarget:GetClass(), tostring(inCone), dot, next))
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
