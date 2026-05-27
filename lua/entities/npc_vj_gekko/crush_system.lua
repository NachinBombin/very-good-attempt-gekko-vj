-- ============================================================
-- GEKKO CRUSH SYSTEM  (melee)
-- ============================================================
-- Fix (2026-05-27): Instant-damage bug resolved for 6 attacks.
--
-- Root cause: FireHeadbutt, FireKick, FireLKick, FireSpinKick,
-- FireFK360, FireFK360B called CrushDamageEnt() immediately
-- inside the Fire* function — damage fired the same Think tick
-- as the proximity check, making it feel instantaneous.
--
-- Fix: Each attack now uses timer.Simple(A.hit_t, ...) with a
-- deferred util.TraceHull sweep that re-evaluates the hit at
-- the actual impact frame.  The target captured at selection
-- time is no longer used — the trace finds whoever is actually
-- in range when the blow lands, which also prevents phantom
-- hits on players who stepped away.
--
-- Secondary fix: _crushHitTimes is now keyed by
-- (entityIndex .. "_" .. attackName) so per-attack cooldowns
-- cannot alias each other.
-- ============================================================

if SERVER then

-- ============================================================
-- CONFIG
-- ============================================================
local CFG = {
    CRUSH_RADIUS   = 96,
    CRUSH_COOLDOWN = 1.0,
    CONE_HALF_DEG  = 70,
}

-- ============================================================
-- ATTACKS
-- (hit_t  = seconds after Fire* call before damage fires)
-- (lock   = total animation lock; must be >= hit_t + buffer)
-- (sweep_* = hull-trace geometry for deferred attacks)
-- ============================================================
local ATTACKS = {

    -- ---- newly-fixed: deferred hull-trace attacks ----

    HEADBUTT = {
        w = 20, nwkey = "GekkoHeadbuttPulse",
        -- hit_t: fast but not instant; head-height hull sweep
        lock = 0.45, hit_t = 0.18,
        dmg = 20, impulse = 7000,
        sweep_dist = 85, sweep_half = 30, sweep_z = 95,
    },

    KICK = {
        w = 20, nwkey = "GekkoKickPulse",
        -- hit_t: short wind-up before damage fires
        lock = 0.50, hit_t = 0.22,
        dmg = 25, impulse = 9000,
        sweep_dist = 105, sweep_half = 35, sweep_z = 60,
    },

    LKICK = {
        w = 20, nwkey = "GekkoLKickPulse",
        -- hit_t: mirrors KICK, left-leg variant
        lock = 0.50, hit_t = 0.22,
        dmg = 25, impulse = 9000,
        sweep_dist = 105, sweep_half = 35, sweep_z = 60,
    },

    SPINKICK = {
        w = 20, nwkey = "GekkoSpinKickPulse",
        -- hit_t: delay accounts for spin wind-up before the kick lands
        lock = 0.65, hit_t = 0.35,
        dmg = 35, impulse = 11000,
        sweep_dist = 120, sweep_half = 45, sweep_z = 65,
    },

    FK360 = {
        w = 20, nwkey = "GekkoFrontKick360Pulse",
        -- hit_t: first-strike delay so damage lands mid-spin, not on proximity trigger
        hit_t = 0.25,
        dmg = 30, impulse = 10000,
        sweep_dist = 130, sweep_half = 45, sweep_z = 65,

        land_radius = 160, land_dmg_max = 45, land_dmg_min = 5, land_impulse = 13000,
    },

    FK360B = {
        w = 20, nwkey = "GekkoFrontKick360BPulse",
        -- hit_t: first-strike delay, mirrors FK360
        hit_t = 0.25,
        dmg = 30, impulse = 10000,
        sweep_dist = 130, sweep_half = 45, sweep_z = 65,

        land_radius = 160, land_dmg_max = 45, land_dmg_min = 5, land_impulse = 13000,
    },

    -- ---- already-correct: timer.Simple deferred attacks ----

    FOOTBALLKICK = {
        w = 20, nwkey = "GekkoFootballKickPulse",
        hit_t = 0.55, lock = 0.9,
        dmg = 40, impulse = 14000,
        sweep_dist = 110, sweep_half = 35, sweep_z = 55,
    },

    RFOOTBALLKICK = {
        w = 20, nwkey = "GekkoRFootballKickPulse",
        hit_t = 0.55, lock = 0.9,
        dmg = 40, impulse = 14000,
        sweep_dist = 110, sweep_half = 35, sweep_z = 55,
    },

    DIAGONALKICK = {
        w = 20, nwkey = "GekkoDiagonalKickPulse",
        hit_t = 0.60, lock = 0.95,
        dmg = 38, impulse = 13000,
        sweep_dist = 120, sweep_half = 40, sweep_z = 70,
    },

    DIAGONALKICKR = {
        w = 20, nwkey = "GekkoDiagonalKickRPulse",
        hit_t = 0.62, lock = 0.95,
        dmg = 38, impulse = 13000,
        sweep_dist = 120, sweep_half = 40, sweep_z = 70,
    },

    HEELHOOK = {
        w = 20, nwkey = "GekkoHeelHookPulse",
        hit_t = 0.62, hit_t2 = 0.82, lock = 1.1,
        dmg = 28, dmg2 = 22,
        impulse = 9500, impulse2 = 8000,
        sweep_dist = 100, sweep_half = 35, sweep_z = 75,
    },

    SIDEHOOKKICK = {
        w = 20, nwkey = "GekkoSideHookKickPulse",
        hit_t = 0.55, lock = 0.9,
        dmg = 35, impulse = 12000,
        sweep_dist = 115, sweep_half = 40, sweep_z = 65,
    },

    AXEKICK = {
        w = 15, nwkey = "GekkoAxeKickPulse",
        hit_t = 0.55, lock = 0.95,
        dmg = 42, impulse = 15000,
        sweep_dist = 100, sweep_half = 35, sweep_z = 50,
    },

    RAXEKICK = {
        w = 15, nwkey = "GekkoRAxeKickPulse",
        hit_t = 0.55, lock = 0.95,
        dmg = 42, impulse = 15000,
        sweep_dist = 100, sweep_half = 35, sweep_z = 50,
    },

    JUMPKICK = {
        w = 10, nwkey = "GekkoJumpKickPulse",
        hit_t = 0.55, lock = 0.9,
        dmg = 45, impulse = 16000,
        sweep_dist = 130, sweep_half = 45, sweep_z = 60,
    },

    BITE = {
        w = 10, nwkey = "GekkoBitePulse",
        hit_t = 0.70, lock = 1.0,
        dmg = 50, impulse = 8000,
        sweep_dist = 80, sweep_half = 30, sweep_z = 85,
    },

    TORQUEKICK = {
        w = 15, nwkey = "GekkoTorqueKickPulse",
        hit_t = 0.76, lock = 1.15,
        dmg = 55, impulse = 18000,
        sweep_dist = 125, sweep_half = 45, sweep_z = 60,
    },

    SPINNINGCAPOEIRA = {
        w = 10, nwkey = "GekkoSpinningCapoeiraPulse",
        hit_t = 0.96, hit_t2 = 1.15, lock = 1.5,
        dmg = 35, dmg2 = 35,
        impulse = 12000, impulse2 = 12000,
        sweep_dist = 130, sweep_half = 50, sweep_z = 65,
    },
}

-- ============================================================
-- WEIGHT TABLE
-- ============================================================
local TOTAL_WEIGHT = 0
for _, A in pairs(ATTACKS) do
    TOTAL_WEIGHT = TOTAL_WEIGHT + (A.w or 0)
end

-- ============================================================
-- HELPERS
-- ============================================================

local function BlastDamage(dmgMax, dmgMin, dist, radius)
    local frac = math.Clamp(1 - (dist / radius), 0, 1)
    return Lerp(frac, dmgMin, dmgMax)
end

local function ClaimKickLock(self, duration)
    self.PauseAttacks        = true
    self.GeckoCrush_LockUntil = CurTime() + duration
end

local function CrushDamageEnt(attacker, victim, dmg, impulseVec)
    if not IsValid(victim) then return end

    local dmgInfo = DamageInfo()
    dmgInfo:SetDamage(dmg)
    dmgInfo:SetAttacker(attacker)
    dmgInfo:SetInflictor(attacker)
    dmgInfo:SetDamageType(DMG_CLUB)
    dmgInfo:SetDamageForce(impulseVec)
    dmgInfo:SetDamagePosition(victim:GetPos())
    victim:TakeDamageInfo(dmgInfo)
end

-- ============================================================
-- FIRE FUNCTIONS
-- ============================================================

-- ---- HEADBUTT (fixed: deferred) ----
local function FireHeadbutt(self)
    local A = ATTACKS.HEADBUTT

    ClaimKickLock(self, A.lock)

    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)

    local selfRef = self
    -- Deferred hull trace: fast but not instant; re-evaluates hit at impact frame
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end

        local fwdRef = selfRef:GetForward()
        local origin = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half   = Vector(A.sweep_half, A.sweep_half, A.sweep_half)

        local tr = util.TraceHull({
            start  = origin,
            endpos = origin + fwdRef * A.sweep_dist,
            mins   = -half, maxs = half,
            filter = selfRef, mask = MASK_SHOT_HULL,
        })

        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            CrushDamageEnt(selfRef, tr.Entity, A.dmg,
                (fwdRef + Vector(0, 0, 0.3)):GetNormalized() * A.impulse)

            print(string.format("[GekkoCrush] HEADBUTT HIT  target=%s  pulse=%d",
                tr.Entity:GetClass(), next))
        end
    end)
end

-- ---- KICK (fixed: deferred) ----
local function FireKick(self)
    local A = ATTACKS.KICK

    ClaimKickLock(self, A.lock)

    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)

    local selfRef = self
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end

        local fwdRef = selfRef:GetForward()
        local origin = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half   = Vector(A.sweep_half, A.sweep_half, A.sweep_half)

        local tr = util.TraceHull({
            start  = origin,
            endpos = origin + fwdRef * A.sweep_dist,
            mins   = -half, maxs = half,
            filter = selfRef, mask = MASK_SHOT_HULL,
        })

        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            local toT  = (tr.Entity:GetPos() - selfRef:GetPos()):GetNormalized()
            local dotT = math.Clamp(fwdRef:Dot(toT), 0.5, 1.0)
            CrushDamageEnt(selfRef, tr.Entity, A.dmg * dotT,
                (fwdRef + Vector(0, 0, 0.3)):GetNormalized() * A.impulse)

            print(string.format("[GekkoCrush] KICK HIT  target=%s  pulse=%d",
                tr.Entity:GetClass(), next))
        end
    end)
end

-- ---- LKICK (fixed: deferred) ----
local function FireLKick(self)
    local A = ATTACKS.LKICK

    ClaimKickLock(self, A.lock)

    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)

    local selfRef = self
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end

        local fwdRef = selfRef:GetForward()
        local origin = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half   = Vector(A.sweep_half, A.sweep_half, A.sweep_half)

        local tr = util.TraceHull({
            start  = origin,
            endpos = origin + fwdRef * A.sweep_dist,
            mins   = -half, maxs = half,
            filter = selfRef, mask = MASK_SHOT_HULL,
        })

        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            local toT  = (tr.Entity:GetPos() - selfRef:GetPos()):GetNormalized()
            local dotT = math.Clamp(fwdRef:Dot(toT), 0.5, 1.0)
            CrushDamageEnt(selfRef, tr.Entity, A.dmg * dotT,
                (fwdRef + Vector(0, 0, 0.3)):GetNormalized() * A.impulse)

            print(string.format("[GekkoCrush] LKICK HIT  target=%s  pulse=%d",
                tr.Entity:GetClass(), next))
        end
    end)
end

-- ---- SPINKICK (fixed: deferred) ----
local function FireSpinKick(self, dot, inCone)
    local A = ATTACKS.SPINKICK
    ClaimKickLock(self, A.lock)

    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)

    print(string.format("[GekkoCrush] SPINKICK wind-up  inCone=%s  dot=%.2f  pulse=%d",
        tostring(inCone), dot, next))

    local selfRef = self
    -- Deferred hull trace: delay covers spin wind-up; right-offset sweep catches the arc
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end

        local fwdRef   = selfRef:GetForward()
        local rightRef = selfRef:GetRight()
        local sweepDir = (fwdRef + rightRef * 0.5):GetNormalized()
        local origin   = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half     = Vector(A.sweep_half, A.sweep_half, A.sweep_half)

        local tr = util.TraceHull({
            start  = origin,
            endpos = origin + sweepDir * A.sweep_dist,
            mins   = -half, maxs = half,
            filter = selfRef, mask = MASK_SHOT_HULL,
        })

        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            local dir = (tr.Entity:GetPos() - selfRef:GetPos()):GetNormalized()
            CrushDamageEnt(selfRef, tr.Entity, A.dmg,
                (dir + Vector(0, 0, 0.4)):GetNormalized() * A.impulse)

            print(string.format("[GekkoCrush] SPINKICK HIT  target=%s  inCone=%s  dot=%.2f  pulse=%d",
                tr.Entity:GetClass(), tostring(inCone), dot, next))
        end
    end)
end

-- ---- FK360 (fixed: first hit deferred) ----
local function FireFK360(self, fwd, dot)
    local A         = ATTACKS.FK360
    local fk360Dur  = self.FK360_DURATION or 0.9

    ClaimKickLock(self, fk360Dur + 0.3)

    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)

    print(string.format("[GekkoCrush] FK360 wind-up  dot=%.2f  pulse=%d", dot, next))

    local selfRef = self
    -- First hit: deferred hull trace so damage lands mid-spin, not on proximity trigger
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end

        local fwdRef = selfRef:GetForward()
        local origin = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half   = Vector(A.sweep_half, A.sweep_half, A.sweep_half)

        local tr = util.TraceHull({
            start  = origin,
            endpos = origin + fwdRef * A.sweep_dist,
            mins   = -half, maxs = half,
            filter = selfRef, mask = MASK_SHOT_HULL,
        })

        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            local impDir = (fwdRef + Vector(0, 0, 0.4)):GetNormalized()
            CrushDamageEnt(selfRef, tr.Entity, A.dmg, impDir * A.impulse)

            print(string.format("[GekkoCrush] FK360 HIT1  target=%s  dot=%.2f  pulse=%d",
                tr.Entity:GetClass(), dot, next))
        end
    end)

    timer.Simple(fk360Dur, function()
        if not IsValid(selfRef) then return end

        local npcPos = selfRef:GetPos()

        -- Landing shockwave
        for _, ent in ipairs(ents.FindInSphere(npcPos, A.land_radius)) do
            if IsValid(ent) and (ent:IsNPC() or ent:IsPlayer()) and ent ~= selfRef then
                local dist   = npcPos:Distance(ent:GetPos())
                local frac   = 1 - (dist / A.land_radius)
                local dmg    = Lerp(frac, A.land_dmg_min, A.land_dmg_max)
                local dir    = (ent:GetPos() - npcPos):GetNormalized()
                local imp    = (dir + Vector(0,0,0.6)):GetNormalized() * A.land_impulse * frac
                CrushDamageEnt(selfRef, ent, dmg, imp)
            end
        end

        print(string.format("[GekkoCrush] FK360 LAND  pulse=%d", next))
    end)
end

-- ---- FK360B (fixed: first hit deferred) ----
local function FireFK360B(self, fwd, dot)
    local A         = ATTACKS.FK360B
    local fk360Dur  = self.FK360_DURATION or 0.9

    ClaimKickLock(self, fk360Dur + 0.3)

    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)

    print(string.format("[GekkoCrush] FK360B wind-up  dot=%.2f  pulse=%d", dot, next))

    local selfRef = self
    -- First hit: deferred hull trace, mirrors FK360
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end

        local fwdRef = selfRef:GetForward()
        local origin = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half   = Vector(A.sweep_half, A.sweep_half, A.sweep_half)

        local tr = util.TraceHull({
            start  = origin,
            endpos = origin + fwdRef * A.sweep_dist,
            mins   = -half, maxs = half,
            filter = selfRef, mask = MASK_SHOT_HULL,
        })

        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            local impDir = (fwdRef + Vector(0, 0, 0.4)):GetNormalized()
            CrushDamageEnt(selfRef, tr.Entity, A.dmg, impDir * A.impulse)

            print(string.format("[GekkoCrush] FK360B HIT1  target=%s  dot=%.2f  pulse=%d",
                tr.Entity:GetClass(), dot, next))
        end
    end)

    timer.Simple(fk360Dur, function()
        if not IsValid(selfRef) then return end

        local npcPos = selfRef:GetPos()

        for _, ent in ipairs(ents.FindInSphere(npcPos, A.land_radius)) do
            if IsValid(ent) and (ent:IsNPC() or ent:IsPlayer()) and ent ~= selfRef then
                local dist   = npcPos:Distance(ent:GetPos())
                local frac   = 1 - (dist / A.land_radius)
                local dmg    = Lerp(frac, A.land_dmg_min, A.land_dmg_max)
                local dir    = (ent:GetPos() - npcPos):GetNormalized()
                local imp    = (dir + Vector(0,0,0.6)):GetNormalized() * A.land_impulse * frac
                CrushDamageEnt(selfRef, ent, dmg, imp)
            end
        end

        print(string.format("[GekkoCrush] FK360B LAND  pulse=%d", next))
    end)
end

-- ---- Already-correct attacks (unchanged logic) ----

local function FireFootballKick(self, closestTarget, fwd)
    local A = ATTACKS.FOOTBALLKICK
    ClaimKickLock(self, A.lock)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
    local selfRef = self
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end
        local fwdRef = selfRef:GetForward()
        local origin = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half   = Vector(A.sweep_half, A.sweep_half, A.sweep_half)
        local tr = util.TraceHull({ start = origin, endpos = origin + fwdRef * A.sweep_dist,
            mins = -half, maxs = half, filter = selfRef, mask = MASK_SHOT_HULL })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            CrushDamageEnt(selfRef, tr.Entity, A.dmg,
                (fwdRef + Vector(0,0,0.3)):GetNormalized() * A.impulse)
            print(string.format("[GekkoCrush] FOOTBALLKICK HIT  target=%s  pulse=%d",
                tr.Entity:GetClass(), next))
        end
    end)
end

local function FireRFootballKick(self, closestTarget, fwd)
    local A = ATTACKS.RFOOTBALLKICK
    ClaimKickLock(self, A.lock)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
    local selfRef = self
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end
        local fwdRef = selfRef:GetForward()
        local origin = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half   = Vector(A.sweep_half, A.sweep_half, A.sweep_half)
        local tr = util.TraceHull({ start = origin, endpos = origin + fwdRef * A.sweep_dist,
            mins = -half, maxs = half, filter = selfRef, mask = MASK_SHOT_HULL })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            CrushDamageEnt(selfRef, tr.Entity, A.dmg,
                (fwdRef + Vector(0,0,0.3)):GetNormalized() * A.impulse)
            print(string.format("[GekkoCrush] RFOOTBALLKICK HIT  target=%s  pulse=%d",
                tr.Entity:GetClass(), next))
        end
    end)
end

local function FireDiagonalKick(self, closestTarget, fwd)
    local A = ATTACKS.DIAGONALKICK
    ClaimKickLock(self, A.lock)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
    local selfRef = self
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end
        local fwdRef = selfRef:GetForward()
        local origin = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half   = Vector(A.sweep_half, A.sweep_half, A.sweep_half)
        local tr = util.TraceHull({ start = origin, endpos = origin + fwdRef * A.sweep_dist,
            mins = -half, maxs = half, filter = selfRef, mask = MASK_SHOT_HULL })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            CrushDamageEnt(selfRef, tr.Entity, A.dmg,
                (fwdRef + Vector(0,0,0.35)):GetNormalized() * A.impulse)
            print(string.format("[GekkoCrush] DIAGONALKICK HIT  target=%s  pulse=%d",
                tr.Entity:GetClass(), next))
        end
    end)
end

local function FireDiagonalKickR(self, closestTarget, fwd)
    local A = ATTACKS.DIAGONALKICKR
    ClaimKickLock(self, A.lock)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
    local selfRef = self
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end
        local fwdRef = selfRef:GetForward()
        local origin = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half   = Vector(A.sweep_half, A.sweep_half, A.sweep_half)
        local tr = util.TraceHull({ start = origin, endpos = origin + fwdRef * A.sweep_dist,
            mins = -half, maxs = half, filter = selfRef, mask = MASK_SHOT_HULL })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            CrushDamageEnt(selfRef, tr.Entity, A.dmg,
                (fwdRef + Vector(0,0,0.35)):GetNormalized() * A.impulse)
            print(string.format("[GekkoCrush] DIAGONALKICKR HIT  target=%s  pulse=%d",
                tr.Entity:GetClass(), next))
        end
    end)
end

local function FireHeelHook(self, closestTarget, fwd)
    local A = ATTACKS.HEELHOOK
    ClaimKickLock(self, A.lock)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
    local selfRef = self
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end
        local fwdRef = selfRef:GetForward()
        local origin = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half   = Vector(A.sweep_half, A.sweep_half, A.sweep_half)
        local tr = util.TraceHull({ start = origin, endpos = origin + fwdRef * A.sweep_dist,
            mins = -half, maxs = half, filter = selfRef, mask = MASK_SHOT_HULL })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            CrushDamageEnt(selfRef, tr.Entity, A.dmg,
                (fwdRef + Vector(0,0,0.3)):GetNormalized() * A.impulse)
        end
    end)
    timer.Simple(A.hit_t2, function()
        if not IsValid(selfRef) then return end
        local fwdRef = selfRef:GetForward()
        local origin = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half   = Vector(A.sweep_half, A.sweep_half, A.sweep_half)
        local tr = util.TraceHull({ start = origin, endpos = origin + fwdRef * A.sweep_dist,
            mins = -half, maxs = half, filter = selfRef, mask = MASK_SHOT_HULL })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            CrushDamageEnt(selfRef, tr.Entity, A.dmg2,
                (fwdRef + Vector(0,0,0.3)):GetNormalized() * A.impulse2)
            print(string.format("[GekkoCrush] HEELHOOK HIT2  target=%s  pulse=%d",
                tr.Entity:GetClass(), next))
        end
    end)
end

local function FireSideHookKick(self, closestTarget, fwd)
    local A = ATTACKS.SIDEHOOKKICK
    ClaimKickLock(self, A.lock)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
    local selfRef = self
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end
        local fwdRef = selfRef:GetForward()
        local origin = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half   = Vector(A.sweep_half, A.sweep_half, A.sweep_half)
        local tr = util.TraceHull({ start = origin, endpos = origin + fwdRef * A.sweep_dist,
            mins = -half, maxs = half, filter = selfRef, mask = MASK_SHOT_HULL })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            CrushDamageEnt(selfRef, tr.Entity, A.dmg,
                (fwdRef + Vector(0,0,0.3)):GetNormalized() * A.impulse)
            print(string.format("[GekkoCrush] SIDEHOOKKICK HIT  target=%s  pulse=%d",
                tr.Entity:GetClass(), next))
        end
    end)
end

local function FireAxeKick(self, closestTarget, fwd)
    local A = ATTACKS.AXEKICK
    ClaimKickLock(self, A.lock)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
    local selfRef = self
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end
        local fwdRef = selfRef:GetForward()
        local origin = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half   = Vector(A.sweep_half, A.sweep_half, A.sweep_half)
        local tr = util.TraceHull({ start = origin, endpos = origin + fwdRef * A.sweep_dist,
            mins = -half, maxs = half, filter = selfRef, mask = MASK_SHOT_HULL })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            CrushDamageEnt(selfRef, tr.Entity, A.dmg,
                (fwdRef + Vector(0,0,-0.2)):GetNormalized() * A.impulse)
            print(string.format("[GekkoCrush] AXEKICK HIT  target=%s  pulse=%d",
                tr.Entity:GetClass(), next))
        end
    end)
end

local function FireRAxeKick(self, closestTarget, fwd)
    local A = ATTACKS.RAXEKICK
    ClaimKickLock(self, A.lock)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
    local selfRef = self
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end
        local fwdRef = selfRef:GetForward()
        local origin = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half   = Vector(A.sweep_half, A.sweep_half, A.sweep_half)
        local tr = util.TraceHull({ start = origin, endpos = origin + fwdRef * A.sweep_dist,
            mins = -half, maxs = half, filter = selfRef, mask = MASK_SHOT_HULL })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            CrushDamageEnt(selfRef, tr.Entity, A.dmg,
                (fwdRef + Vector(0,0,-0.2)):GetNormalized() * A.impulse)
            print(string.format("[GekkoCrush] RAXEKICK HIT  target=%s  pulse=%d",
                tr.Entity:GetClass(), next))
        end
    end)
end

local function FireJumpKick(self, closestTarget, fwd)
    local A = ATTACKS.JUMPKICK
    ClaimKickLock(self, A.lock)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
    local selfRef = self
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end
        local fwdRef = selfRef:GetForward()
        local origin = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half   = Vector(A.sweep_half, A.sweep_half, A.sweep_half)
        local tr = util.TraceHull({ start = origin, endpos = origin + fwdRef * A.sweep_dist,
            mins = -half, maxs = half, filter = selfRef, mask = MASK_SHOT_HULL })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            CrushDamageEnt(selfRef, tr.Entity, A.dmg,
                (fwdRef + Vector(0,0,0.4)):GetNormalized() * A.impulse)
            print(string.format("[GekkoCrush] JUMPKICK HIT  target=%s  pulse=%d",
                tr.Entity:GetClass(), next))
        end
    end)
end

local function FireBite(self)
    local A = ATTACKS.BITE
    ClaimKickLock(self, A.lock)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
    local selfRef = self
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end
        local fwdRef = selfRef:GetForward()
        local origin = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half   = Vector(A.sweep_half, A.sweep_half, A.sweep_half)
        local tr = util.TraceHull({ start = origin, endpos = origin + fwdRef * A.sweep_dist,
            mins = -half, maxs = half, filter = selfRef, mask = MASK_SHOT_HULL })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            CrushDamageEnt(selfRef, tr.Entity, A.dmg,
                fwdRef:GetNormalized() * A.impulse)
            print(string.format("[GekkoCrush] BITE HIT  target=%s  pulse=%d",
                tr.Entity:GetClass(), next))
        end
    end)
end

local function FireTorqueKick(self)
    local A = ATTACKS.TORQUEKICK
    ClaimKickLock(self, A.lock)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
    local selfRef = self
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end
        local fwdRef = selfRef:GetForward()
        local origin = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half   = Vector(A.sweep_half, A.sweep_half, A.sweep_half)
        local tr = util.TraceHull({ start = origin, endpos = origin + fwdRef * A.sweep_dist,
            mins = -half, maxs = half, filter = selfRef, mask = MASK_SHOT_HULL })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            CrushDamageEnt(selfRef, tr.Entity, A.dmg,
                (fwdRef + Vector(0,0,0.5)):GetNormalized() * A.impulse)
            print(string.format("[GekkoCrush] TORQUEKICK HIT  target=%s  pulse=%d",
                tr.Entity:GetClass(), next))
        end
    end)
end

local function FireSpinningCapoeira(self)
    local A = ATTACKS.SPINNINGCAPOEIRA
    ClaimKickLock(self, A.lock)
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)
    local selfRef = self
    timer.Simple(A.hit_t, function()
        if not IsValid(selfRef) then return end
        local fwdRef = selfRef:GetForward()
        local origin = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half   = Vector(A.sweep_half, A.sweep_half, A.sweep_half)
        local tr = util.TraceHull({ start = origin, endpos = origin + fwdRef * A.sweep_dist,
            mins = -half, maxs = half, filter = selfRef, mask = MASK_SHOT_HULL })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            CrushDamageEnt(selfRef, tr.Entity, A.dmg,
                (fwdRef + Vector(0,0,0.4)):GetNormalized() * A.impulse)
        end
    end)
    timer.Simple(A.hit_t2, function()
        if not IsValid(selfRef) then return end
        local fwdRef = selfRef:GetForward()
        local rRef   = selfRef:GetRight()
        local sweepDir = (fwdRef - rRef * 0.5):GetNormalized()
        local origin = selfRef:GetPos() + Vector(0, 0, A.sweep_z)
        local half   = Vector(A.sweep_half, A.sweep_half, A.sweep_half)
        local tr = util.TraceHull({ start = origin, endpos = origin + sweepDir * A.sweep_dist,
            mins = -half, maxs = half, filter = selfRef, mask = MASK_SHOT_HULL })
        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            local dir = (tr.Entity:GetPos() - selfRef:GetPos()):GetNormalized()
            CrushDamageEnt(selfRef, tr.Entity, A.dmg2,
                (dir + Vector(0,0,0.4)):GetNormalized() * A.impulse2)
            print(string.format("[GekkoCrush] SPINNINGCAPOEIRA HIT2  target=%s  pulse=%d",
                tr.Entity:GetClass(), next))
        end
    end)
end

-- ============================================================
-- ATTACK PICKER
-- ============================================================

local function WeightedPick(exclude)
    local pool = {}
    local total = 0
    for name, A in pairs(ATTACKS) do
        if name ~= exclude then
            pool[#pool+1] = { name = name, w = A.w or 0 }
            total = total + (A.w or 0)
        end
    end
    local r = math.random() * total
    local acc = 0
    for _, entry in ipairs(pool) do
        acc = acc + entry.w
        if r <= acc then return entry.name end
    end
    return pool[#pool].name
end

-- ============================================================
-- THINK HOOK  (GeckoCrush_Think)
-- ============================================================

function ENT:GeckoCrush_Think()
    if not self._crushHitTimes then self._crushHitTimes = {} end

    -- Release lock
    if self.PauseAttacks and self.GeckoCrush_LockUntil then
        if CurTime() >= self.GeckoCrush_LockUntil then
            self.PauseAttacks        = false
            self.GeckoCrush_LockUntil = nil
        end
    end
    if self.PauseAttacks then return end

    -- Find closest valid target
    local closestTarget = nil
    local closestDist   = math.huge
    for _, ent in ipairs(ents.FindInSphere(self:GetPos(), CFG.CRUSH_RADIUS)) do
        if IsValid(ent) and ent ~= self and (ent:IsPlayer() or (ent:IsNPC() and ent:GetClass() ~= self:GetClass())) then
            local d = self:GetPos():Distance(ent:GetPos())
            if d < closestDist then
                closestDist   = d
                closestTarget = ent
            end
        end
    end
    if not IsValid(closestTarget) then return end

    local now    = CurTime()
    local fwd    = self:GetForward()
    local toEnt  = (closestTarget:GetPos() - self:GetPos()):GetNormalized()
    local dot    = fwd:Dot(toEnt)
    local inCone = dot >= math.cos(math.rad(CFG.CONE_HALF_DEG))

    -- Per-(entity, attack) cooldown key prevents cross-attack aliasing
    local attack = WeightedPick(self._lastCrushAttack)
    local hitKey  = tostring(closestTarget:EntIndex()) .. "_" .. (attack or "")
    local lastHit = self._crushHitTimes[hitKey] or 0
    if now - lastHit < CFG.CRUSH_COOLDOWN then return end

    self._crushHitTimes[hitKey] = now
    self._lastCrushAttack        = attack

    -- Decide kick target (for attacks that still accept it via parameter)
    local kickTarget = closestTarget

    -- Dispatch
    if     attack == "FK360"           then FireFK360(self, fwd, dot)
    elseif attack == "FK360B"          then FireFK360B(self, fwd, dot)
    elseif attack == "HEADBUTT"        then FireHeadbutt(self)
    elseif attack == "KICK"            then FireKick(self)
    elseif attack == "LKICK"           then FireLKick(self)
    elseif attack == "FOOTBALLKICK"    then FireFootballKick(self, kickTarget, fwd)
    elseif attack == "RFOOTBALLKICK"   then FireRFootballKick(self, kickTarget, fwd)
    elseif attack == "DIAGONALKICK"    then FireDiagonalKick(self, kickTarget, fwd)
    elseif attack == "DIAGONALKICKR"   then FireDiagonalKickR(self, kickTarget, fwd)
    elseif attack == "HEELHOOK"        then FireHeelHook(self, kickTarget, fwd)
    elseif attack == "SIDEHOOKKICK"    then FireSideHookKick(self, kickTarget, fwd)
    elseif attack == "AXEKICK"         then FireAxeKick(self, kickTarget, fwd)
    elseif attack == "RAXEKICK"        then FireRAxeKick(self, kickTarget, fwd)
    elseif attack == "JUMPKICK"        then FireJumpKick(self, kickTarget, fwd)
    elseif attack == "BITE"            then FireBite(self)
    elseif attack == "TORQUEKICK"      then FireTorqueKick(self)
    elseif attack == "SPINNINGCAPOEIRA" then FireSpinningCapoeira(self)
    else                                    FireSpinKick(self, dot, inCone)
    end
end

-- ============================================================
--  LAUNCH BLAST  (called by targeted_jump_system.lua on jump launch)
-- ============================================================
local LAUNCH = {
    radius   = 220,
    dmg_max  = 40,
    dmg_min  = 1,
    impulse  = 18000,
}

function ENT:GeckoCrush_LaunchBlast()
    local origin = self:GetPos() + Vector(0, 0, 40)

    for _, ent in ipairs(ents.FindInSphere(origin, LAUNCH.radius)) do
        if ent == self then continue end
        if not ent:IsNPC() and not ent:IsPlayer()
            and not IsValid(ent:GetPhysicsObject()) then
            continue
        end

        local dist = ent:GetPos():Distance(origin)
        local dmg  = BlastDamage(LAUNCH.dmg_max, LAUNCH.dmg_min, dist, LAUNCH.radius)
        local dir  = (ent:GetPos() - origin):GetNormalized()

        CrushDamageEnt(self, ent, dmg,
            (dir + Vector(0, 0, 0.5)):GetNormalized() * LAUNCH.impulse)
    end
end

-- ============================================================
--  LAND BLAST  (called by targeted_jump_system.lua on landing)
-- ============================================================
local LAND = {
    radius   = 300,
    dmg_max  = 60,
    dmg_min  = 1,
    impulse  = 22000,
}

function ENT:GeckoCrush_LandBlast()
    local origin   = self:GetPos() + Vector(0, 0, 20)
    local self_ref = self

    for _, ent in ipairs(ents.FindInSphere(origin, LAND.radius)) do
        if ent == self then continue end
        if not ent:IsNPC() and not ent:IsPlayer()
            and not IsValid(ent:GetPhysicsObject()) then continue end

        local dist = ent:GetPos():Distance(origin)
        local dmg  = BlastDamage(LAND.dmg_max, LAND.dmg_min, dist, LAND.radius)
        local dir  = (ent:GetPos() - origin):GetNormalized()

        CrushDamageEnt(self, ent, dmg,
            (dir + Vector(0, 0, 1.2)):GetNormalized() * LAND.impulse)
    end

    -- Kill residual upward velocity so the NPC doesn't bounce on landing
    timer.Simple(0, function()
        if not IsValid(self_ref) then return end
        local vel = self_ref:GetVelocity()
        if vel.z > 50 then
            self_ref:SetVelocity(Vector(0, 0, 0))
        end
    end)
end

end -- SERVER
