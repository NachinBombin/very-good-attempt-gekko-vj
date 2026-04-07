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
--                             FK360        ~14%  (b_pelvis flip, front only)
--                             HEADBUTT     ~14%
--                             KICK         ~14%  (only if dist+speed gates pass)
--                             SPINKICK     ~14%
--                             FOOTBALLKICK ~14%  (b_l_hippiston1 forward kick)
--                             DIAGONALKICK ~14%  (b_l_hippiston1 diagonal sweep)
--                             HEELHOOK     ~14%  (two-phase C-path hook kick)
--
--         If Kick is excluded from pool its weight redistributes
--         proportionally among the remaining entries.
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
--    Single hit at t=0.55 s (phase 3 start = leg extension).
--    Hull sweep forward, heavy forward impulse.
--
--  DIAGONAL KICK HIT TIMING:
--    Single hit at t=DK_HIT_T (phase 3 start = sweep begins).
--    Hull sweep forward+diagonal, forward/side impulse.
--
--  HEEL HOOK HIT TIMING:
--    Hit 1 at t=HH_HIT_T1 — heel extends outward across target line.
--    Hit 2 at t=HH_HIT_T2 — leg hooks inward/back (C-path return).
--    Two hull sweeps at different angles; hit 2 catches targets
--    slightly behind the initial contact point.
--
--  LAUNCH BLAST  — sphere damage at jump takeoff.
--  LAND BLAST    — sphere damage + knockup on landing.
-- ============================================================

if SERVER then
    util.AddNetworkString("GekkoCrushHit")
    util.AddNetworkString("GekkoSpinKickPulse")      -- true yaw spin
    util.AddNetworkString("GekkoFootballKickPulse")  -- left-leg football kick
    util.AddNetworkString("GekkoDiagonalKickPulse")  -- left-leg diagonal sweep kick
    util.AddNetworkString("GekkoHeelHookPulse")      -- two-phase heel hook kick
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

-- FK360
local FK360_DAMAGE        = 30
local FK360_IMPULSE       = 10000
local FK360_W             = 20
local FK360_LAND_RADIUS   = 160
local FK360_LAND_DMG_MAX  = 45
local FK360_LAND_DMG_MIN  = 5
local FK360_LAND_IMPULSE  = 13000

-- Headbutt
local HB_DAMAGE      = 20
local HB_IMPULSE     = 7000
local HB_W           = 20

-- Simple Kick
local KICK_DAMAGE    = 25
local KICK_IMPULSE   = 9000
local KICK_W         = 20
local KICK_MIN_DIST  = 48
local KICK_SPEED     = 30
local WALK_CRUSH_WIDTH = 50

-- SpinKick
local SK_DAMAGE      = 35
local SK_IMPULSE     = 11000
local SK_W           = 20

-- Football Kick
local FB_DAMAGE      = 40
local FB_IMPULSE     = 14000
local FB_W           = 20
local FB_DURATION    = 1.3
local FB_HIT_T       = 0.55
local FB_SWEEP_DIST  = 140
local FB_SWEEP_HALF  = 55

-- Diagonal Kick  (b_l_hippiston1 diagonal sweep; front-cone only)
local DK_DAMAGE      = 38
local DK_IMPULSE     = 13000
local DK_W           = 20
local DK_DURATION    = 1.4
local DK_HIT_T       = 0.60
local DK_SWEEP_DIST  = 150
local DK_SWEEP_HALF  = 55

-- Heel Hook Kick (two-phase C-path hook; front-cone only)
-- Hit 1: t=HH_HIT_T1 — heel extends outward across target line.
-- Hit 2: t=HH_HIT_T2 — leg hooks inward/back, catches targets on return arc.
local HH_DAMAGE_1    = 35
local HH_DAMAGE_2    = 28
local HH_IMPULSE_1   = 12000
local HH_IMPULSE_2   = 9500
local HH_W           = 20
local HH_DURATION    = 1.6
local HH_HIT_T1      = 0.62
local HH_HIT_T2      = 0.82
local HH_SWEEP_DIST  = 160
local HH_SWEEP_HALF  = 50
local HH_HOOK_ANGLE  = 55

function ENT:GeckoCrush_Think()
    if self:GetGekkoJumpState() ~= self.JUMP_NONE then return end

    local now = CurTime()
    if now < (self._gekkoSuppressActivity or 0) then return end
    if self.PauseAttacks then return end
    if self.AttackAnimTime and self.AttackAnimTime > now then return end

    local pos   = self:GetPos() + Vector(0, 0, 80)
    local fwd   = self:GetForward()
    local speed = self:GetNWFloat("GekkoSpeed", 0)

    if not self._crushHitTimes then self._crushHitTimes = {} end

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

    local attack

    if not inCone then
        attack = "SPINKICK"
    else
        local pool = {}
        pool[#pool+1] = { name = "FK360",        w = FK360_W }
        pool[#pool+1] = { name = "HEADBUTT",      w = HB_W    }
        pool[#pool+1] = { name = "SPINKICK",      w = SK_W    }
        pool[#pool+1] = { name = "FOOTBALLKICK",  w = FB_W    }
        pool[#pool+1] = { name = "DIAGONALKICK",  w = DK_W    }
        pool[#pool+1] = { name = "HEELHOOK",      w = HH_W    }
        if kickTarget then
            pool[#pool+1] = { name = "KICK", w = KICK_W }
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
                local dmg        = BlastDamage(FK360_LAND_DMG_MAX, FK360_LAND_DMG_MIN, entDist, FK360_LAND_RADIUS)
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

    elseif attack == "FOOTBALLKICK" then
        ClaimKickLock(self, FB_DURATION + 0.2)
        local next = (self:GetNWInt("GekkoFootballKickPulse", 0) % 254) + 1
        self:SetNWInt("GekkoFootballKickPulse", next)
        print(string.format("[GekkoCrush] FOOTBALLKICK  target=%s  dot=%.2f  pulse=%d",
            closestTarget:GetClass(), dot, next))
        local selfRef = self
        timer.Simple(FB_HIT_T, function()
            if not IsValid(selfRef) then return end
            local fwdRef = selfRef:GetForward()
            local origin = selfRef:GetPos() + Vector(0, 0, 60)
            local sweep  = origin + fwdRef * FB_SWEEP_DIST
            local half   = Vector(FB_SWEEP_HALF, FB_SWEEP_HALF, FB_SWEEP_HALF)
            local tr = util.TraceHull({
                start  = origin, endpos = sweep,
                mins   = -half,  maxs   =  half,
                filter = selfRef, mask  = MASK_SHOT_HULL,
            })
            if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
                local fwdImpulse = (fwdRef + Vector(0, 0, 0.25)):GetNormalized() * FB_IMPULSE
                CrushDamageEnt(selfRef, tr.Entity, FB_DAMAGE, fwdImpulse)
                print(string.format("[GekkoCrush] FOOTBALLKICK HIT  target=%s  pulse=%d",
                    tr.Entity:GetClass(), next))
            end
        end)

    elseif attack == "DIAGONALKICK" then
        ClaimKickLock(self, DK_DURATION + 0.2)
        local next = (self:GetNWInt("GekkoDiagonalKickPulse", 0) % 254) + 1
        self:SetNWInt("GekkoDiagonalKickPulse", next)
        print(string.format("[GekkoCrush] DIAGONALKICK  target=%s  dot=%.2f  pulse=%d",
            closestTarget:GetClass(), dot, next))
        local selfRef = self
        timer.Simple(DK_HIT_T, function()
            if not IsValid(selfRef) then return end
            local fwdRef  = selfRef:GetForward()
            local rightRef = selfRef:GetRight()
            local sweepDir = (fwdRef - rightRef * 0.35):GetNormalized()
            local origin   = selfRef:GetPos() + Vector(0, 0, 60)
            local sweep    = origin + sweepDir * DK_SWEEP_DIST
            local half     = Vector(DK_SWEEP_HALF, DK_SWEEP_HALF, DK_SWEEP_HALF)
            local tr = util.TraceHull({
                start  = origin, endpos = sweep,
                mins   = -half,  maxs   =  half,
                filter = selfRef, mask  = MASK_SHOT_HULL,
            })
            if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
                local impDir = (sweepDir + Vector(0, 0, 0.3)):GetNormalized()
                CrushDamageEnt(selfRef, tr.Entity, DK_DAMAGE, impDir * DK_IMPULSE)
                print(string.format("[GekkoCrush] DIAGONALKICK HIT  target=%s  pulse=%d",
                    tr.Entity:GetClass(), next))
            end
        end)

    elseif attack == "HEELHOOK" then
        ClaimKickLock(self, HH_DURATION + 0.3)
        local next = (self:GetNWInt("GekkoHeelHookPulse", 0) % 254) + 1
        self:SetNWInt("GekkoHeelHookPulse", next)
        print(string.format("[GekkoCrush] HEELHOOK  target=%s  dot=%.2f  pulse=%d",
            closestTarget:GetClass(), dot, next))

        local selfRef = self

        -- HIT 1: heel extends outward across target line
        timer.Simple(HH_HIT_T1, function()
            if not IsValid(selfRef) then return end
            local fwdRef   = selfRef:GetForward()
            local rightRef = selfRef:GetRight()
            local sweepDir1 = (fwdRef + rightRef * 0.6):GetNormalized()
            local origin1   = selfRef:GetPos() + Vector(0, 0, 65)
            local sweep1    = origin1 + sweepDir1 * HH_SWEEP_DIST
            local half      = Vector(HH_SWEEP_HALF, HH_SWEEP_HALF, HH_SWEEP_HALF)
            local tr1 = util.TraceHull({
                start  = origin1, endpos = sweep1,
                mins   = -half,   maxs   =  half,
                filter = selfRef, mask   = MASK_SHOT_HULL,
            })
            if IsValid(tr1.Entity) and (tr1.Entity:IsNPC() or tr1.Entity:IsPlayer()) then
                local impDir1 = (sweepDir1 + Vector(0, 0, 0.3)):GetNormalized()
                CrushDamageEnt(selfRef, tr1.Entity, HH_DAMAGE_1, impDir1 * HH_IMPULSE_1)
                print(string.format("[GekkoCrush] HEELHOOK HIT1 (extension)  target=%s  pulse=%d",
                    tr1.Entity:GetClass(), next))
            end
        end)

        -- HIT 2: leg hooks inward/back, C-path return catches targets behind initial line
        timer.Simple(HH_HIT_T2, function()
            if not IsValid(selfRef) then return end
            local fwdRef   = selfRef:GetForward()
            local rightRef = selfRef:GetRight()
            local hookRad  = math.rad(HH_HOOK_ANGLE)
            local sweepDir2 = (fwdRef - rightRef * math.tan(hookRad * 0.5)):GetNormalized()
            local origin2   = selfRef:GetPos() + Vector(0, 0, 60)
            local sweep2    = origin2 + sweepDir2 * HH_SWEEP_DIST
            local half      = Vector(HH_SWEEP_HALF, HH_SWEEP_HALF, HH_SWEEP_HALF)
            local tr2 = util.TraceHull({
                start  = origin2, endpos = sweep2,
                mins   = -half,   maxs   =  half,
                filter = selfRef, mask   = MASK_SHOT_HULL,
            })
            if IsValid(tr2.Entity) and (tr2.Entity:IsNPC() or tr2.Entity:IsPlayer()) then
                local impDir2 = (sweepDir2 + Vector(0, 0, 0.4)):GetNormalized()
                CrushDamageEnt(selfRef, tr2.Entity, HH_DAMAGE_2, impDir2 * HH_IMPULSE_2)
                print(string.format("[GekkoCrush] HEELHOOK HIT2 (hook-back)  target=%s  pulse=%d",
                    tr2.Entity:GetClass(), next))
            end
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
