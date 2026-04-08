-- ============================================================
--  npc_vj_gekko / crush_system.lua
--
--  All per-attack numeric constants are stored in module-level
--  tables (CFG, ATTACKS) so that GeckoCrush_Think only closes
--  over a small number of upvalues and stays within LuaJIT's
--  hard cap of 60.
-- ============================================================

if SERVER then
    util.AddNetworkString("GekkoCrushHit")
    util.AddNetworkString("GekkoSpinKickPulse")
    util.AddNetworkString("GekkoFootballKickPulse")
    util.AddNetworkString("GekkoRFootballKickPulse")
    util.AddNetworkString("GekkoDiagonalKickPulse")
    util.AddNetworkString("GekkoHeelHookPulse")
    util.AddNetworkString("GekkoSideHookKickPulse")
    util.AddNetworkString("GekkoAxeKickPulse")
    util.AddNetworkString("GekkoRAxeKickPulse")
    util.AddNetworkString("GekkoJumpKickPulse")
    util.AddNetworkString("GekkoLKickPulse")
end

-- ============================================================
--  Shared helpers
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

local function BlastDamage(dmgMax, dmgMin, dist, radius)
    local k  = (dmgMax / dmgMin) - 1
    local dn = math.Clamp(dist / radius, 0, 1)
    return dmgMax / (1 + k * dn * dn)
end

local function ClaimKickLock(ent, duration)
    ent._gekkoSuppressActivity = CurTime() + duration
    ent.PauseAttacks = true
    timer.Create("gekko_kick_pauserelease" .. ent:EntIndex(), duration, 1, function()
        if IsValid(ent) then ent.PauseAttacks = false end
    end)
end

-- ============================================================
--  CFG  -  general detection constants (few, safe as upvalues)
-- ============================================================
local CFG = {
    CRUSH_RADIUS    = 96,
    CRUSH_COOLDOWN  = 1.0,
    CONE_DOT        = 0.5,
    KICK_MIN_DIST   = 48,
    KICK_SPEED      = 30,
    WALK_CRUSH_W    = 50,
}

-- ============================================================
--  ATTACKS  -  one sub-table per attack, keyed by attack name
-- ============================================================
local ATTACKS = {
    FK360 = {
        w = 20, nwkey = "GekkoFrontKick360Pulse",
        dmg = 30, impulse = 10000,
        land_radius = 160, land_dmg_max = 45, land_dmg_min = 5, land_impulse = 13000,
    },
    HEADBUTT = {
        w = 20, nwkey = "GekkoHeadbuttPulse",
        lock = 0.55, dmg = 20, impulse = 7000,
    },
    KICK = {
        w = 20, nwkey = "GekkoKickPulse",
        lock = 0.5, dmg = 25, impulse = 9000,
    },
    LKICK = {
        w = 20, nwkey = "GekkoLKickPulse",
        lock = 0.5, dmg = 25, impulse = 9000,
    },
    SPINKICK = {
        w = 20, nwkey = "GekkoSpinKickPulse",
        lock = 0.65, dmg = 35, impulse = 11000,
    },
    FOOTBALLKICK = {
        w = 20, nwkey = "GekkoFootballKickPulse",
        duration = 1.3, hit_t = 0.55,
        dmg = 40, impulse = 14000,
        sweep_dist = 140, sweep_half = 55, sweep_z = 60,
    },
    -- ============================================================
    --  RFOOTBALLKICK  -  mirrored football kick (right leg)
    --  Identical stats to FOOTBALLKICK; sweep direction is straight
    --  forward (the original uses the same hull sweep direction, so
    --  the mirror is behaviorally symmetric).  The only difference
    --  is that the client bone driver uses b_r_hippiston1 as the
    --  kicking leg and b_l_hippiston1 as the brace.
    -- ============================================================
    RFOOTBALLKICK = {
        w = 20, nwkey = "GekkoRFootballKickPulse",
        duration = 1.3, hit_t = 0.55,
        dmg = 40, impulse = 14000,
        sweep_dist = 140, sweep_half = 55, sweep_z = 60,
    },
    DIAGONALKICK = {
        w = 20, nwkey = "GekkoDiagonalKickPulse",
        duration = 1.4, hit_t = 0.60,
        dmg = 38, impulse = 13000,
        sweep_dist = 150, sweep_half = 55, sweep_z = 60,
    },
    HEELHOOK = {
        w = 20, nwkey = "GekkoHeelHookPulse",
        duration = 1.6, hit_t = 0.62, hit_t2 = 0.82,
        dmg = 35, dmg2 = 28, impulse = 12000, impulse2 = 9500,
        sweep_dist = 160, sweep_half = 50, sweep_z = 65,
        hook_angle = 55,
    },
    SIDEHOOKKICK = {
        w = 20, nwkey = "GekkoSideHookKickPulse",
        duration = 1.5, hit_t = 0.55,
        dmg = 36, impulse = 12500,
        sweep_dist = 145, sweep_half = 52, sweep_z = 65,
    },
    AXEKICK = {
        w = 20, nwkey = "GekkoAxeKickPulse",
        duration = 1.4, hit_t = 0.55,
        dmg = 45, impulse = 15000,
        sweep_dist = 155, sweep_half = 55, sweep_z = 90,
    },
    RAXEKICK = {
        w = 20, nwkey = "GekkoRAxeKickPulse",
        duration = 1.4, hit_t = 0.55,
        dmg = 45, impulse = 15000,
        sweep_dist = 155, sweep_half = 55, sweep_z = 90,
    },
    -- ============================================================
    --  JUMPKICK
    --  4 phases:
    --    Phase 1  preparation  (leg chamber, no movement)
    --    Phase 2  kick + small forward hop  (hit fires here)
    --    Phase 3  falling  (body tilts forward, pedestal recentres)
    --    Phase 4  smooth recovery to rest
    --
    --  Forward-cone only (inCone required).
    --  The Gekko gets a brief forward velocity impulse at hit_t.
    -- ============================================================
    JUMPKICK = {
        w = 20, nwkey = "GekkoJumpKickPulse",
        duration = 1.6,
        hit_t    = 0.55,          -- sweep fires mid-phase-2
        dmg = 42, impulse = 14500,
        sweep_dist = 160, sweep_half = 55, sweep_z = 75,
        hop_force = 240,          -- forward units/s applied at kick moment
    },
}

-- ============================================================
--  Per-attack fire helpers
-- ============================================================

local function FireFK360(self, closestTarget, fwd, dot)
    local A         = ATTACKS.FK360
    local fk360Dur  = self.FK360_DURATION or 0.9
    ClaimKickLock(self, fk360Dur + 0.3)
    local impulse = (fwd + Vector(0, 0, 0.4)):GetNormalized() * A.impulse
    CrushDamageEnt(self, closestTarget, A.dmg, impulse)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
    print(string.format("[GekkoCrush] FK360 HIT1  target=%s  dot=%.2f  pulse=%d", closestTarget:GetClass(), dot, next))
    local selfRef = self
    timer.Simple(fk360Dur, function()
        if not IsValid(selfRef) then return end
        local origin = selfRef:GetPos() + Vector(0, 0, 40)
        for _, ent in ipairs(ents.FindInSphere(origin, A.land_radius)) do
            if ent == selfRef then continue end
            if not ent:IsNPC() and not ent:IsPlayer() then continue end
            local entDist = ent:GetPos():Distance(origin)
            local dmg     = BlastDamage(A.land_dmg_max, A.land_dmg_min, entDist, A.land_radius)
            local dir     = (ent:GetPos() - origin):GetNormalized()
            CrushDamageEnt(selfRef, ent, dmg, (dir + Vector(0,0,0.35)):GetNormalized() * A.land_impulse)
        end
        local dustPulse = (selfRef:GetNWInt("GekkoFK360LandDust", 0) % 254) + 1
        selfRef:SetNWInt("GekkoFK360LandDust", dustPulse)
    end)
end

local function FireHeadbutt(self, closestTarget, fwd)
    local A = ATTACKS.HEADBUTT
    ClaimKickLock(self, A.lock)
    CrushDamageEnt(self, closestTarget, A.dmg, (fwd + Vector(0,0,0.3)):GetNormalized() * A.impulse)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
end

local function FireKick(self, kickTarget, fwd)
    local A     = ATTACKS.KICK
    ClaimKickLock(self, A.lock)
    local toT  = (kickTarget:GetPos() - self:GetPos()):GetNormalized()
    local dotT = math.Clamp(fwd:Dot(toT), 0.5, 1.0)
    CrushDamageEnt(self, kickTarget, A.dmg * dotT, (fwd + Vector(0,0,0.3)):GetNormalized() * A.impulse)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
end

local function FireLKick(self, kickTarget, fwd)
    local A     = ATTACKS.LKICK
    ClaimKickLock(self, A.lock)
    local toT  = (kickTarget:GetPos() - self:GetPos()):GetNormalized()
    local dotT = math.Clamp(fwd:Dot(toT), 0.5, 1.0)
    CrushDamageEnt(self, kickTarget, A.dmg * dotT, (fwd + Vector(0,0,0.3)):GetNormalized() * A.impulse)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
end

local function FireSpinKick(self, closestTarget, fwd, dot, inCone)
    local A   = ATTACKS.SPINKICK
    ClaimKickLock(self, A.lock)
    local dir = (closestTarget:GetPos() - self:GetPos()):GetNormalized()
    CrushDamageEnt(self, closestTarget, A.dmg, (dir + Vector(0,0,0.4)):GetNormalized() * A.impulse)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
    print(string.format("[GekkoCrush] SPINKICK  target=%s  inCone=%s  dot=%.2f  pulse=%d", closestTarget:GetClass(), tostring(inCone), dot, next))
end

local function FireFootballKick(self)
    local A    = ATTACKS.FOOTBALLKICK
    ClaimKickLock(self, A.duration + 0.2)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
    local selfRef = self
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end
        local fwdRef = selfRef:GetForward()
        local origin = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half   = Vector(A.sweep_half, A.sweep_half, A.sweep_half)
        local tr = util.TraceHull({ start = origin, endpos = origin + fwdRef * A.sweep_dist, mins = -half, maxs = half, filter = selfRef, mask = MASK_SHOT_HULL })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            CrushDamageEnt(selfRef, tr.Entity, A.dmg, (fwdRef + Vector(0,0,0.25)):GetNormalized() * A.impulse)
        end
    end)
end

-- ============================================================
--  RFOOTBALLKICK fire helper
--  Identical hull sweep to FOOTBALLKICK; NW key is different so
--  the client bone driver knows which leg to animate.
-- ============================================================
local function FireRFootballKick(self)
    local A    = ATTACKS.RFOOTBALLKICK
    ClaimKickLock(self, A.duration + 0.2)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
    local selfRef = self
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end
        local fwdRef = selfRef:GetForward()
        local origin = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half   = Vector(A.sweep_half, A.sweep_half, A.sweep_half)
        local tr = util.TraceHull({ start = origin, endpos = origin + fwdRef * A.sweep_dist, mins = -half, maxs = half, filter = selfRef, mask = MASK_SHOT_HULL })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            CrushDamageEnt(selfRef, tr.Entity, A.dmg, (fwdRef + Vector(0,0,0.25)):GetNormalized() * A.impulse)
        end
    end)
end

local function FireDiagonalKick(self)
    local A    = ATTACKS.DIAGONALKICK
    ClaimKickLock(self, A.duration + 0.2)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
    local selfRef = self
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end
        local fwdRef   = selfRef:GetForward()
        local rightRef = selfRef:GetRight()
        local sweepDir = (fwdRef - rightRef * 0.35):GetNormalized()
        local origin   = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half     = Vector(A.sweep_half, A.sweep_half, A.sweep_half)
        local tr = util.TraceHull({ start = origin, endpos = origin + sweepDir * A.sweep_dist, mins = -half, maxs = half, filter = selfRef, mask = MASK_SHOT_HULL })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            CrushDamageEnt(selfRef, tr.Entity, A.dmg, (sweepDir + Vector(0,0,0.3)):GetNormalized() * A.impulse)
        end
    end)
end

local function FireHeelHook(self)
    local A    = ATTACKS.HEELHOOK
    ClaimKickLock(self, A.duration + 0.3)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
    local selfRef = self
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end
        local fwdRef   = selfRef:GetForward()
        local rightRef = selfRef:GetRight()
        local sweepDir = (fwdRef + rightRef * 0.6):GetNormalized()
        local origin   = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half     = Vector(A.sweep_half, A.sweep_half, A.sweep_half)
        local tr = util.TraceHull({ start = origin, endpos = origin + sweepDir * A.sweep_dist, mins = -half, maxs = half, filter = selfRef, mask = MASK_SHOT_HULL })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            CrushDamageEnt(selfRef, tr.Entity, A.dmg, (sweepDir + Vector(0,0,0.3)):GetNormalized() * A.impulse)
        end
    end)
    timer.Simple(A.hit_t2, function()
        if not IsValid(selfRef) then return end
        local fwdRef   = selfRef:GetForward()
        local rightRef = selfRef:GetRight()
        local hookRad  = math.rad(A.hook_angle)
        local sweepDir = (fwdRef - rightRef * math.tan(hookRad * 0.5)):GetNormalized()
        local origin   = selfRef:GetPos() + Vector(0, 0, A.sweep_z - 5)
        local half     = Vector(A.sweep_half, A.sweep_half, A.sweep_half)
        local tr = util.TraceHull({ start = origin, endpos = origin + sweepDir * A.sweep_dist, mins = -half, maxs = half, filter = selfRef, mask = MASK_SHOT_HULL })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            CrushDamageEnt(selfRef, tr.Entity, A.dmg2, (sweepDir + Vector(0,0,0.4)):GetNormalized() * A.impulse2)
        end
    end)
end

local function FireSideHookKick(self)
    local A    = ATTACKS.SIDEHOOKKICK
    ClaimKickLock(self, A.duration + 0.2)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
    local selfRef = self
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end
        local fwdRef   = selfRef:GetForward()
        local rightRef = selfRef:GetRight()
        local sweepDir = (fwdRef * 0.4 + rightRef * 0.9):GetNormalized()
        local origin   = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half     = Vector(A.sweep_half, A.sweep_half, A.sweep_half)
        local tr = util.TraceHull({ start = origin, endpos = origin + sweepDir * A.sweep_dist, mins = -half, maxs = half, filter = selfRef, mask = MASK_SHOT_HULL })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            CrushDamageEnt(selfRef, tr.Entity, A.dmg, (sweepDir + Vector(0,0,0.25)):GetNormalized() * A.impulse)
        end
    end)
end

local function FireAxeKick(self, closestTarget, dot)
    local A    = ATTACKS.AXEKICK
    ClaimKickLock(self, A.duration + 0.2)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
    print(string.format("[GekkoCrush] AXEKICK  target=%s  dot=%.2f  pulse=%d", closestTarget:GetClass(), dot, next))
    local selfRef = self
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end
        local fwdRef   = selfRef:GetForward()
        local sweepDir = (fwdRef - Vector(0,0,0.3)):GetNormalized()
        local origin   = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half     = Vector(A.sweep_half, A.sweep_half, A.sweep_half)
        local tr = util.TraceHull({ start = origin, endpos = origin + sweepDir * A.sweep_dist, mins = -half, maxs = half, filter = selfRef, mask = MASK_SHOT_HULL })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            local impDir = (fwdRef * 0.4 - Vector(0,0,1) * 0.6):GetNormalized()
            CrushDamageEnt(selfRef, tr.Entity, A.dmg, impDir * A.impulse)
            print(string.format("[GekkoCrush] AXEKICK HIT  target=%s  pulse=%d", tr.Entity:GetClass(), next))
        end
    end)
end

local function FireRAxeKick(self, closestTarget, dot)
    local A    = ATTACKS.RAXEKICK
    ClaimKickLock(self, A.duration + 0.2)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
    print(string.format("[GekkoCrush] RAXEKICK  target=%s  dot=%.2f  pulse=%d", closestTarget:GetClass(), dot, next))
    local selfRef = self
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end
        local fwdRef   = selfRef:GetForward()
        local sweepDir = (fwdRef - Vector(0,0,0.3)):GetNormalized()
        local origin   = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half     = Vector(A.sweep_half, A.sweep_half, A.sweep_half)
        local tr = util.TraceHull({ start = origin, endpos = origin + sweepDir * A.sweep_dist, mins = -half, maxs = half, filter = selfRef, mask = MASK_SHOT_HULL })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            local impDir = (fwdRef * 0.4 - Vector(0,0,1) * 0.6):GetNormalized()
            CrushDamageEnt(selfRef, tr.Entity, A.dmg, impDir * A.impulse)
            print(string.format("[GekkoCrush] RAXEKICK HIT  target=%s  pulse=%d", tr.Entity:GetClass(), next))
        end
    end)
end

-- ============================================================
--  JUMPKICK fire helper
--
--  Phase timing (seconds):
--    0.00 - 0.30   Phase 1: preparation  (bone anim only, no damage)
--    0.30 - 0.55   Phase 2: kick + forward hop  (hit_t = 0.55)
--    0.55 - 1.00   Phase 3: falling
--    1.00 - 1.60   Phase 4: recovery
--
--  Server responsibility:
--    - ClaimKickLock for full duration
--    - Apply a brief forward velocity at hit_t (the hop)
--    - Forward hull sweep at hit_t for damage
-- ============================================================
local function FireJumpKick(self, closestTarget, fwd, dot)
    local A    = ATTACKS.JUMPKICK
    ClaimKickLock(self, A.duration + 0.2)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
    print(string.format("[GekkoCrush] JUMPKICK  target=%s  dot=%.2f  pulse=%d", closestTarget:GetClass(), dot, next))
    local selfRef = self
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end
        -- forward hop velocity
        local fwdRef = selfRef:GetForward()
        local curVel = selfRef:GetVelocity()
        selfRef:SetVelocity(Vector(curVel.x + fwdRef.x * A.hop_force,
                                   curVel.y + fwdRef.y * A.hop_force,
                                   curVel.z))
        -- hull sweep
        local origin = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half   = Vector(A.sweep_half, A.sweep_half, A.sweep_half)
        local tr = util.TraceHull({
            start  = origin,
            endpos = origin + fwdRef * A.sweep_dist,
            mins   = -half, maxs = half,
            filter = selfRef, mask = MASK_SHOT_HULL,
        })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            local impDir = (fwdRef + Vector(0, 0, 0.3)):GetNormalized()
            CrushDamageEnt(selfRef, tr.Entity, A.dmg, impDir * A.impulse)
            print(string.format("[GekkoCrush] JUMPKICK HIT  target=%s  pulse=%d", tr.Entity:GetClass(), next))
        end
    end)
end

-- ============================================================
--  GeckoCrush_Think
-- ============================================================
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

    -- find closest NPC/player in sphere
    local closestTarget, closestDistSq = nil, math.huge
    for _, ent in ipairs(ents.FindInSphere(pos, CFG.CRUSH_RADIUS)) do
        if ent == self then continue end
        if not ent:IsNPC() and not ent:IsPlayer() then continue end
        local dsq = pos:DistToSqr(ent:GetPos())
        if dsq < closestDistSq then closestDistSq = dsq; closestTarget = ent end
    end
    if not IsValid(closestTarget) then return end

    local lastHit = self._crushHitTimes[closestTarget] or 0
    if now - lastHit < CFG.CRUSH_COOLDOWN then return end

    local dist     = math.sqrt(closestDistSq)
    local toTarget = (closestTarget:GetPos() - self:GetPos()):GetNormalized()
    local dot      = fwd:Dot(toTarget)
    local inCone   = (dot >= CFG.CONE_DOT)

    -- walking kick scan
    local kickTarget = nil
    if inCone and dist > CFG.KICK_MIN_DIST and speed >= CFG.KICK_SPEED then
        local sweep = pos + fwd * CFG.CRUSH_RADIUS
        local half  = Vector(CFG.WALK_CRUSH_W, CFG.WALK_CRUSH_W, CFG.WALK_CRUSH_W)
        local tr = util.TraceHull({ start = pos, endpos = sweep, mins = -half, maxs = half, filter = self, mask = MASK_SHOT_HULL })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            kickTarget = tr.Entity
        end
    end

    -- attack selection
    local attack
    if not inCone then
        attack = "SPINKICK"
    else
        local pool = {
            { name = "FK360",          w = ATTACKS.FK360.w          },
            { name = "HEADBUTT",       w = ATTACKS.HEADBUTT.w       },
            { name = "SPINKICK",       w = ATTACKS.SPINKICK.w       },
            { name = "FOOTBALLKICK",   w = ATTACKS.FOOTBALLKICK.w   },
            { name = "RFOOTBALLKICK",  w = ATTACKS.RFOOTBALLKICK.w  },
            { name = "DIAGONALKICK",   w = ATTACKS.DIAGONALKICK.w   },
            { name = "HEELHOOK",       w = ATTACKS.HEELHOOK.w       },
            { name = "SIDEHOOKKICK",   w = ATTACKS.SIDEHOOKKICK.w   },
            { name = "AXEKICK",        w = ATTACKS.AXEKICK.w        },
            { name = "RAXEKICK",       w = ATTACKS.RAXEKICK.w       },
            { name = "JUMPKICK",       w = ATTACKS.JUMPKICK.w       },
        }
        if kickTarget then
            pool[#pool+1] = { name = "KICK",  w = ATTACKS.KICK.w  }
            pool[#pool+1] = { name = "LKICK", w = ATTACKS.LKICK.w }
        end
        local total = 0
        for _, e in ipairs(pool) do total = total + e.w end
        local roll, acc = math.random() * total, 0
        for _, e in ipairs(pool) do
            acc = acc + e.w
            if roll <= acc then attack = e.name; break end
        end
        attack = attack or pool[#pool].name
    end

    self._crushHitTimes[closestTarget] = now

    -- dispatch
    if     attack == "FK360"           then FireFK360(self, closestTarget, fwd, dot)
    elseif attack == "HEADBUTT"        then FireHeadbutt(self, closestTarget, fwd)
    elseif attack == "KICK"            then FireKick(self, kickTarget, fwd)
    elseif attack == "LKICK"           then FireLKick(self, kickTarget, fwd)
    elseif attack == "FOOTBALLKICK"    then FireFootballKick(self)
    elseif attack == "RFOOTBALLKICK"   then FireRFootballKick(self)
    elseif attack == "DIAGONALKICK"    then FireDiagonalKick(self)
    elseif attack == "HEELHOOK"        then FireHeelHook(self)
    elseif attack == "SIDEHOOKKICK"    then FireSideHookKick(self)
    elseif attack == "AXEKICK"         then FireAxeKick(self, closestTarget, dot)
    elseif attack == "RAXEKICK"        then FireRAxeKick(self, closestTarget, dot)
    elseif attack == "JUMPKICK"        then FireJumpKick(self, closestTarget, fwd, dot)
    else                                    FireSpinKick(self, closestTarget, fwd, dot, inCone)
    end
end

-- ============================================================
--  LAUNCH BLAST
-- ============================================================
local LAUNCH = { radius = 220, dmg_max = 40, dmg_min = 1, impulse = 18000 }

function ENT:GeckoCrush_LaunchBlast()
    local origin = self:GetPos() + Vector(0, 0, 40)
    for _, ent in ipairs(ents.FindInSphere(origin, LAUNCH.radius)) do
        if ent == self then continue end
        if not ent:IsNPC() and not ent:IsPlayer() and not IsValid(ent:GetPhysicsObject()) then continue end
        local dist = ent:GetPos():Distance(origin)
        local dmg  = BlastDamage(LAUNCH.dmg_max, LAUNCH.dmg_min, dist, LAUNCH.radius)
        local dir  = (ent:GetPos() - origin):GetNormalized()
        CrushDamageEnt(self, ent, dmg, (dir + Vector(0,0,0.5)):GetNormalized() * LAUNCH.impulse)
    end
end

-- ============================================================
--  LAND BLAST
-- ============================================================
local LAND = { radius = 300, dmg_max = 60, dmg_min = 1, impulse = 22000 }

function ENT:GeckoCrush_LandBlast()
    local origin   = self:GetPos() + Vector(0, 0, 20)
    local self_ref = self
    for _, ent in ipairs(ents.FindInSphere(origin, LAND.radius)) do
        if ent == self then continue end
        if not ent:IsNPC() and not ent:IsPlayer() and not IsValid(ent:GetPhysicsObject()) then continue end
        local dist = ent:GetPos():Distance(origin)
        local dmg  = BlastDamage(LAND.dmg_max, LAND.dmg_min, dist, LAND.radius)
        local dir  = (ent:GetPos() - origin):GetNormalized()
        CrushDamageEnt(self, ent, dmg, (dir + Vector(0,0,1.2)):GetNormalized() * LAND.impulse)
    end
    timer.Simple(0, function()
        if not IsValid(self_ref) then return end
        local vel = self_ref:GetVelocity()
        if vel.z > 50 then self_ref:SetVelocity(Vector(0,0,0)) end
    end)
end
