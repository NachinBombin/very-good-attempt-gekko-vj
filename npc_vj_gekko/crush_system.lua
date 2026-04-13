-- ============================================================
--  npc_vj_gekko / crush_system.lua
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
    util.AddNetworkString("GekkoFrontKick360BPulse")
end

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

local CFG = {
    CRUSH_RADIUS    = 96,
    CRUSH_COOLDOWN  = 1.0,
    CONE_DOT        = 0.5,
    KICK_MIN_DIST   = 48,
    KICK_SPEED      = 30,
    WALK_CRUSH_W    = 50,
}

local ATTACKS = {
    FK360 = {
        w = 20, nwkey = "GekkoFrontKick360Pulse",
        dmg = 30, impulse = 10000,
        land_radius = 160, land_dmg_max = 45, land_dmg_min = 5, land_impulse = 13000,
    },

    FK360B = {
        w = 20, nwkey = "GekkoFrontKick360BPulse",
        dmg = 30, impulse = 10000,
        land_radius = 160, land_dmg_max = 45, land_dmg_min = 5, land_impulse = 13000,
        -- Phase durations matching cl_init constants
        prep_dur    = 0.30,
        elong_dur   = 0.20,
        land_dur    = 0.25,
        restore_dur = 0.35,
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

    JUMPKICK = {
        w = 20, nwkey = "GekkoJumpKickPulse",
        duration = 1.6, hit_t = 0.55,
        dmg = 42, impulse = 14500,
        sweep_dist = 160, sweep_half = 55, sweep_z = 75,
        hop_force = 240,
    },
}

local function FireFK360(self, closestTarget, fwd, dot)
    local A         = ATTACKS.FK360
    local fk360Dur  = self.FK360_DURATION or 0.9

    ClaimKickLock(self, fk360Dur + 0.3)

    local impulse = (fwd + Vector(0, 0, 0.4)):GetNormalized() * A.impulse
    CrushDamageEnt(self, closestTarget, A.dmg, impulse)

    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)

    print(string.format("[GekkoCrush] FK360 HIT1  target=%s  dot=%.2f  pulse=%d",
        closestTarget:GetClass(), dot, next))

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

-- ============================================================
--  FK360B  -  5-phase extended spinning kick
--
--  Timeline (all durations match cl_init FK360B constants):
--    [0.00]              trigger / pulse increment
--    [0.00 - 0.30]       PREP    (pedestal tilt + hip prep, no damage)
--    [0.30 - 0.50]       ELONGATION (pelvis rises to Z=43, no damage)
--    [0.50 - 0.50+spin]  SPIN    ** damage here **
--      pulse 1 fires at spinStart (t=0.50)
--      pulse 2 fires at spinStart + spinDur*0.50
--    [spinEnd]           LAND    (pelvis drops to Z=22, land blast)
--    [spinEnd+0.25]      RESTORE (smooth return, no damage)
--
--  Total lock = prep + elong + spin + land + restore + 0.2 buffer
-- ============================================================
local function FireFK360B(self, closestTarget, fwd, dot)
    local A        = ATTACKS.FK360B
    local spinDur  = self.FK360_DURATION or 0.9
    local spinStart = A.prep_dur + A.elong_dur          -- 0.50 s
    local spinEnd   = spinStart + spinDur
    local totalDur  = spinEnd + A.land_dur + A.restore_dur

    -- Lock the NPC for the full animation + small buffer
    ClaimKickLock(self, totalDur + 0.2)

    -- Increment pulse so cl_init driver triggers the visual
    local next = (self:GetNWInt(A.nwkey, 0) % 254) + 1
    self:SetNWInt(A.nwkey, next)

    print(string.format(
        "[GekkoCrush] FK360B START  target=%s  dot=%.2f  pulse=%d  spinStart=%.2f  total=%.2f",
        closestTarget:GetClass(), dot, next, spinStart, totalDur))

    local selfRef  = self
    local targetRef = closestTarget

    -- ---- Damage pulse 1: start of spin ----
    timer.Simple(spinStart, function()
        if not IsValid(selfRef) then return end
        if not IsValid(targetRef) then return end

        local curFwd = selfRef:GetForward()
        local impulse = (curFwd + Vector(0, 0, 0.4)):GetNormalized() * A.impulse
        CrushDamageEnt(selfRef, targetRef, A.dmg, impulse)

        print(string.format("[GekkoCrush] FK360B HIT1  t=%.2f", spinStart))
    end)

    -- ---- Damage pulse 2: midpoint of spin ----
    timer.Simple(spinStart + spinDur * 0.5, function()
        if not IsValid(selfRef) then return end
        if not IsValid(targetRef) then return end

        local curFwd = selfRef:GetForward()
        local impulse = (curFwd + Vector(0, 0, 0.4)):GetNormalized() * A.impulse
        CrushDamageEnt(selfRef, targetRef, A.dmg, impulse)

        print(string.format("[GekkoCrush] FK360B HIT2  t=%.2f", spinStart + spinDur * 0.5))
    end)

    -- ---- Land blast: end of spin (same as FK360 land) ----
    timer.Simple(spinEnd, function()
        if not IsValid(selfRef) then return end

        local origin = selfRef:GetPos() + Vector(0, 0, 40)
        for _, ent in ipairs(ents.FindInSphere(origin, A.land_radius)) do
            if ent == selfRef then continue end
            if not ent:IsNPC() and not ent:IsPlayer() then continue end

            local entDist = ent:GetPos():Distance(origin)
            local dmg     = BlastDamage(A.land_dmg_max, A.land_dmg_min, entDist, A.land_radius)
            local dir     = (ent:GetPos() - origin):GetNormalized()

            CrushDamageEnt(selfRef, ent, dmg, (dir + Vector(0, 0, 0.35)):GetNormalized() * A.land_impulse)
        end

        -- Trigger land dust effect
        local dustPulse = (selfRef:GetNWInt("GekkoFK360LandDust", 0) % 254) + 1
        selfRef:SetNWInt("GekkoFK360LandDust", dustPulse)

        print(string.format("[GekkoCrush] FK360B LAND BLAST  t=%.2f", spinEnd))
    end)
end

-- (all other Fire* helpers unchanged)

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

    local closestTarget, closestDistSq = nil, math.huge
    for _, ent in ipairs(ents.FindInSphere(pos, CFG.CRUSH_RADIUS)) do
        if ent == self then continue end
        if not ent:IsNPC() and not ent:IsPlayer() then continue end

        local dsq = pos:DistToSqr(ent:GetPos())
        if dsq < closestDistSq then
            closestDistSq = dsq
            closestTarget = ent
        end
    end

    if not IsValid(closestTarget) then return end

    local lastHit = self._crushHitTimes[closestTarget] or 0
    if now - lastHit < CFG.CRUSH_COOLDOWN then return end

    local dist     = math.sqrt(closestDistSq)
    local toTarget = (closestTarget:GetPos() - self:GetPos()):GetNormalized()
    local dot      = fwd:Dot(toTarget)
    local inCone   = (dot >= CFG.CONE_DOT)

    local kickTarget = nil
    if inCone and dist > CFG.KICK_MIN_DIST and speed >= CFG.KICK_SPEED then
        local sweep = pos + fwd * CFG.CRUSH_RADIUS
        local half  = Vector(CFG.WALK_CRUSH_W, CFG.WALK_CRUSH_W, CFG.WALK_CRUSH_W)

        local tr = util.TraceHull({
            start  = pos,
            endpos = sweep,
            mins   = -half, maxs = half,
            filter = self, mask = MASK_SHOT_HULL,
        })

        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            kickTarget = tr.Entity
        end
    end

    local attack
    if not inCone then
        attack = "SPINKICK"
    else
        local pool = {
            { name = "FK360",          w = ATTACKS.FK360.w          },
            { name = "FK360B",         w = ATTACKS.FK360B.w         },
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

        local roll = math.random() * total
        local acc  = 0
        for _, e in ipairs(pool) do
            acc = acc + e.w
            if roll <= acc then
                attack = e.name
                break
            end
        end

        attack = attack or pool[#pool].name
    end

    self._crushHitTimes[closestTarget] = now

    if     attack == "FK360"           then FireFK360(self, closestTarget, fwd, dot)
    elseif attack == "FK360B"          then FireFK360B(self, closestTarget, fwd, dot)
    -- other attacks dispatched as before ...
    end
end
