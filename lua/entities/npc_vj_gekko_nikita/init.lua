include("shared.lua")

-- ============================================================
--  npc_vj_gekko_nikita  /  init.lua
-- ============================================================

-- ---------------------------------------------------------
--  TUNING
-- ---------------------------------------------------------
local CRUISE_SPEED         = 360
local TURN_RATE            = 8.0   -- rad/s
local LEAD_TIME            = 0.55
local TARGET_Z_OFFS        = 40
local BODY_HALF            = 12
local PATHFIND_INTERVAL    = 0.12
local CORRIDOR_TURN_MULT   = 1.7
local TACT_CLOSE_BOOST     = 180
local LAST_KNOWN_TIMEOUT   = 5.0

local EMERG_DIST     = 200
local TACT_DIST      = 600
local STRAT_DIST     = 1800
local EMERG_STRENGTH = 1.0
local TACT_STRENGTH  = 0.82
local STRAT_STRENGTH = 0.30

local SCOUT_RAY_DIST     = 2900
local PATH_BLEND_NORMAL  = 0.70
local PATH_BLEND_LOCKED  = 0.97
local SCORE_ANGLE_WEIGHT = 1.5
local SCORE_DIST_WEIGHT  = 1.0
local SCORE_APT_BONUS    = 4.0

local RING_PROBE_LEN    = 220
local RING_EXIT_FRAC    = 0.55
local RING_RADII_COARSE = { 0, 40, 80, 140, 220, 320, 440, 600, 800 }
local RING_STEPS_COARSE = 16
local RING_FINE_RADIUS  = 60
local RING_STEPS_FINE   = 24
local APERTURE_REACHED  = 120
local WAYPOINT_MAX      = 2

local WALL_KICK_STRENGTH = 0.55
local BUMP_COOLDOWN      = 0.18
local ARMOR_MAX          = 6
local ARMOR_REGEN_INT    = 2.5
local STREAK_MAX         = 6
local STREAK_WINDOW      = 1.5

-- Physics-impact damage thresholds (debris / bullet props)
local PHYS_DMG_MIN_SPEED  = 200
local PHYS_DMG_SCALE      = 0.06

-- ---------------------------------------------------------
--  PRE-DETONATION SHOTGUN BURST
-- ---------------------------------------------------------
local PREDET_DELAY      = 0.4
local PREDET_PELLETS    = 39
local PREDET_PELLET_DMG = 8
local PREDET_RANGE      = 3000
local PREDET_SPREAD_DEG = 29.0
local PREDET_NOSE_OFFS  = 20

-- ---------------------------------------------------------
--  TIP CAP PROP
-- ---------------------------------------------------------
local TIPCAP_MODEL  = "models/xqm/cylinderx1.mdl"
local TIPCAP_SCALE  = 0.7
-- How far ahead of the missile origin the cap sits (along forward)
local TIPCAP_OFFSET = 14
-- Kick impulse range when the cap detaches (u/s)
local TIPCAP_VEL_MIN   = 220
local TIPCAP_VEL_MAX   = 520
-- Angular velocity range on detach (deg/s per axis)
local TIPCAP_ANGVEL_MIN = -380
local TIPCAP_ANGVEL_MAX =  380
-- Gravity scale applied to the flying cap
local TIPCAP_GRAVITY    = 1.0
-- Remove the cap after this many seconds so it does not litter the map forever
local TIPCAP_LIFETIME   = 6.0

-- ---------------------------------------------------------
--  SOUNDS
-- ---------------------------------------------------------
local SND_FIRE    = "nikita/distant_fire.wav"
local SND_WHISTLE = "nikita/bomb_whistle_loop.wav"
local SND_FLAME   = "nikita/flame_loop.wav"
local SND_LOCKON  = "nikita/lock on stinger.wav"
local SND_PREDET  = "weapons/shotgun/shotgun_fire7.wav"
-- Stage-1 fragmentation detonation blast (separate from the stage-2 pure explosion)
local SND_PREDET_BLAST = "ambient/explosions/explode_4.wav"

local LOCKON_DIST = 600

-- ---------------------------------------------------------
--  NET STRINGS
-- ---------------------------------------------------------
util.AddNetworkString("NikitaPelletTracer")
util.AddNetworkString("NikitaMuzzleFlash")

-- ---------------------------------------------------------
--  RAY TABLES  (pitch, yaw, weight)
-- ---------------------------------------------------------
local RAYS_EMERG = {
    { 0,    0,   1.2 }, { 0,  45, 1.0 }, { 0,  -45, 1.0 },
    { 0,   90,   1.0 }, { 0, -90, 1.0 }, { 0,  135, 0.8 },
    { 0,  -135,  0.8 }, { 0, 180, 0.6 },
    {-90,   0,   1.0 }, { 90,  0, 1.0 },
    {-45,   0,   1.0 }, {-45, 90, 0.9 }, {-45, -90, 0.9 },
    {-45,  45,   0.9 }, {-45,-45, 0.9 },
    { 45,   0,   1.0 }, { 45, 90, 0.9 }, { 45, -90, 0.9 },
    { 45,  45,   0.9 }, { 45,-45, 0.9 },
    {-20,  22,   1.0 }, {-20,-22, 1.0 },
    { 20,  22,   1.0 }, { 20,-22, 1.0 },
    { 0,   22,   1.1 }, { 0, -22, 1.1 },
}

local RAYS_TACT = {
    { 0,   0,  1.4 }, { 0,  15, 1.2 }, { 0, -15, 1.2 },
    { 0,  30,  1.1 }, { 0, -30, 1.1 }, { 0,  50, 1.0 },
    { 0, -50,  1.0 }, { 0,  70, 0.8 }, { 0, -70, 0.8 },
    {-15,  0,  1.1 }, { 15,  0, 1.1 }, {-30,  0, 1.0 },
    { 30,  0,  1.0 }, {-20, 30, 1.0 }, {-20,-30, 1.0 },
    { 20, 30,  1.0 }, { 20,-30, 1.0 }, { 0,  90, 0.7 },
    { 0, -90,  0.7 },
}

local RAYS_STRAT = {
    { 0,  0, 1.0 }, { 0, 18, 0.8 }, { 0,-18, 0.8 },
    {-18, 0, 0.8 }, { 18, 0, 0.8 },
}

local SCOUT_RAYS = {
    {  0,   0 }, {  0,  30 }, {  0, -30 }, {  0,  60 }, {  0, -60 },
    {  0,  90 }, {  0, -90 }, {  0, 120 }, {  0,-120 },
    {  0, 150 }, {  0,-150 }, {  0, 180 },
    { 30,   0 }, {-30,   0 }, { 60,   0 }, {-60,   0 },
    { 30,  45 }, { 30, -45 }, {-30,  45 }, {-30, -45 },
    { 30,  90 }, { 30, -90 }, {-30,  90 }, {-30, -90 },
    { 30, 135 }, { 30,-135 }, {-30, 135 }, {-30,-135 },
    { 60,  60 }, { 60, -60 }, {-60,  60 }, {-60, -60 },
    { 60,  90 }, { 60, -90 }, {-60,  90 }, {-60, -90 },
    { 90,   0 }, {-90,   0 },
    { 45,   0 }, {-45,   0 }, { 45, 180 }, {-45, 180 },
    { 45,  90 }, { 45, -90 }, {-45,  90 }, {-45, -90 },
}

-- ---------------------------------------------------------
--  HELPERS
-- ---------------------------------------------------------
local function GetEntVelocity(ent)
    if ent.GetVelocity then return ent:GetVelocity() end
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then return phys:GetVelocity() end
    return Vector(0,0,0)
end

local function DirToAngle(dir)
    local a = dir:Angle()
    a.r = 0
    return a
end

local function CastLocalRay(ent, origin, pitch, yaw, maxDist, filter)
    local dir = ent:LocalToWorldAngles(Angle(pitch, yaw, 0)):Forward()
    return util.TraceLine({
        start  = origin,
        endpos = origin + dir * maxDist,
        mask   = MASK_SOLID_BRUSHONLY,
        filter = filter,
    }), dir
end

local function ComputeRepulsion(ent, origin, rayTable, maxDist, filter)
    local rep    = Vector(0,0,0)
    local anyHit = false
    local minD   = math.huge
    for _, ray in ipairs(rayTable) do
        local tr = CastLocalRay(ent, origin, ray[1], ray[2], maxDist, filter)
        if tr.Hit then
            local d = (origin - tr.HitPos):Length()
            if d < minD then minD = d end
            local w = 1.0 - math.Clamp(d / maxDist, 0, 1)
            if d < TACT_CLOSE_BOOST then w = w * 2.0 end
            rep     = rep + tr.HitNormal * (w * ray[3])
            anyHit  = true
        end
    end
    return rep, anyHit, minD
end

local function BodyFits(origin, dir, len, filter)
    local tr = util.TraceHull({
        start  = origin,
        endpos = origin + dir * len,
        mins   = Vector(-BODY_HALF,-BODY_HALF,-BODY_HALF),
        maxs   = Vector( BODY_HALF, BODY_HALF, BODY_HALF),
        mask   = MASK_SOLID_BRUSHONLY,
        filter = filter,
    })
    if not tr.Hit then return len, true end
    return (origin - tr.HitPos):Length(), false
end

local function BuildTangents(normal)
    local up    = Vector(0,0,1)
    local right = normal:Cross(up)
    if right:LengthSqr() < 0.001 then
        right = normal:Cross(Vector(1,0,0))
    end
    right:Normalize()
    local tang = right:Cross(normal)
    tang:Normalize()
    return right, tang
end

local function IsWorldEnt(ent)
    if not IsValid(ent) then return true end
    local cl = ent:GetClass()
    return cl == "worldspawn" or cl == "func_brush" or cl == "func_detail"
        or cl == "func_wall"  or cl == "func_wall_toggle"
end

-- ---------------------------------------------------------
--  RING APERTURE SCANNER
-- ---------------------------------------------------------
local function RingApertureScan(hitPos, hitNormal, myPos, aimPos, filter)
    local right, tang = BuildTangents(hitNormal)
    local wallOrigin  = hitPos + hitNormal * (BODY_HALF + 4)
    local probeDir    = -hitNormal
    local toTarget    = (aimPos - hitPos):GetNormalized()
    local pi2         = math.pi * 2

    local function Score(pt)
        local pd = (aimPos - pt):GetNormalized():Dot(-hitNormal)
        local ad = math.max(0, (pt - myPos):GetNormalized():Dot(toTarget))
        local zs = 1.0 - math.Clamp(math.abs(pt.z - myPos.z) / 400, 0, 1)
        return pd * 2.0 + ad * 1.5 + zs * 0.8
    end

    local bestCS, bestCP = -math.huge, nil
    for _, radius in ipairs(RING_RADII_COARSE) do
        local steps = (radius == 0) and 1 or RING_STEPS_COARSE
        for i = 0, steps - 1 do
            local a  = (i / steps) * pi2
            local pt = wallOrigin
                     + right * (math.cos(a) * radius)
                     + tang  * (math.sin(a) * radius)
            local _, fits = BodyFits(pt, probeDir, RING_PROBE_LEN, filter)
            if fits then
                local s = Score(pt)
                if s > bestCS then bestCS, bestCP = s, pt end
            end
        end
        if bestCP and radius <= 80 then break end
    end
    if not bestCP then return nil, nil end

    local bestFS, bestFP = bestCS, bestCP
    for i = 0, RING_STEPS_FINE - 1 do
        local a  = (i / RING_STEPS_FINE) * pi2
        local pt = bestCP
                 + right * (math.cos(a) * RING_FINE_RADIUS)
                 + tang  * (math.sin(a) * RING_FINE_RADIUS)
        local _, fits = BodyFits(pt, probeDir, RING_PROBE_LEN, filter)
        if fits then
            local s = Score(pt)
            if s > bestFS then bestFS, bestFP = s, pt end
        end
    end

    return bestFP + probeDir * (RING_PROBE_LEN * RING_EXIT_FRAC), hitNormal
end

-- ---------------------------------------------------------
--  WAYPOINT CHAIN
-- ---------------------------------------------------------
local function ScanAhead(myPos, aimPos, filter)
    local tr = util.TraceHull({
        start  = myPos, endpos = aimPos,
        mins   = Vector(-BODY_HALF,-BODY_HALF,-BODY_HALF),
        maxs   = Vector( BODY_HALF, BODY_HALF, BODY_HALF),
        mask   = MASK_SOLID_BRUSHONLY, filter = filter,
    })
    if not tr.Hit then return nil, nil end
    return RingApertureScan(tr.HitPos, tr.HitNormal, myPos, aimPos, filter)
end

local function RebuildWaypoints(self, myPos, aimPos, filter)
    self._wp      = {}
    self._wpIdx   = 1
    self._aptLock = false
    self._pathDir = nil

    local p1, n1 = ScanAhead(myPos, aimPos, filter)
    if not p1 then return end
    local t1 = util.TraceLine({ start=myPos, endpos=p1,
        mask=MASK_SOLID_BRUSHONLY, filter=filter })
    if t1.Hit then return end
    self._wp[1] = { pos=p1, normal=n1 }

    if WAYPOINT_MAX < 2 then return end
    local p2, n2 = ScanAhead(p1, aimPos, filter)
    if not p2 then return end
    local t2 = util.TraceLine({ start=p1, endpos=p2,
        mask=MASK_SOLID_BRUSHONLY, filter=filter })
    if not t2.Hit then
        self._wp[2] = { pos=p2, normal=n2 }
    end
end

local function UpdatePath(self, myPos, aimPos, filter)
    if not aimPos then
        self._wp={} self._wpIdx=1 self._aptLock=false self._pathDir=nil
        return
    end

    if self._wp and #self._wp > 0 then
        local wp = self._wp[self._wpIdx]
        if wp then
            if (myPos - wp.pos):Length() < APERTURE_REACHED then
                self._wpIdx = self._wpIdx + 1
                wp = self._wp[self._wpIdx]
                if not wp then
                    self._wp={} self._aptLock=false self._pathDir=nil
                    return
                end
            end
            local vt = util.TraceLine({ start=myPos, endpos=wp.pos,
                mask=MASK_SOLID_BRUSHONLY, filter=filter })
            if not vt.Hit then
                local d = LerpVector(0.35, (wp.pos-myPos):GetNormalized(), -wp.normal)
                d:Normalize()
                self._pathDir = d
                self._aptLock = true
                return
            end
        end
    end

    local dt = util.TraceHull({ start=myPos, endpos=aimPos,
        mins=Vector(-BODY_HALF,-BODY_HALF,-BODY_HALF),
        maxs=Vector( BODY_HALF, BODY_HALF, BODY_HALF),
        mask=MASK_SOLID_BRUSHONLY, filter=filter })
    if not dt.Hit then
        self._wp={} self._aptLock=false self._pathDir=nil
        return
    end

    RebuildWaypoints(self, myPos, aimPos, filter)

    if self._wp and self._wp[1] then
        local wp = self._wp[1]
        local d  = LerpVector(0.35, (wp.pos-myPos):GetNormalized(), -wp.normal)
        d:Normalize()
        self._pathDir = d
        self._aptLock = true
        return
    end

    local toTarget = (aimPos - myPos):GetNormalized()
    local bestS, bestD = -math.huge, nil
    for _, ray in ipairs(SCOUT_RAYS) do
        local dir = self:LocalToWorldAngles(Angle(ray[1], ray[2], 0)):Forward()
        local od, fits = BodyFits(myPos, dir, SCOUT_RAY_DIST, filter)
        local score = SCORE_ANGLE_WEIGHT * math.max(0, dir:Dot(toTarget))
                    + SCORE_DIST_WEIGHT  * (od / SCOUT_RAY_DIST)
                    + (fits and SCORE_APT_BONUS or 0)
        if score > bestS then bestS, bestD = score, dir end
    end
    self._pathDir = bestD
    self._aptLock = false
end

-- ---------------------------------------------------------
--  CLEARANCE PROBE
-- ---------------------------------------------------------
local function ClearanceProbe(origin, moveDir, filter)
    local tr = util.TraceHull({
        start  = origin, endpos = origin + moveDir * 80,
        mins   = Vector(-BODY_HALF,-BODY_HALF,-BODY_HALF),
        maxs   = Vector( BODY_HALF, BODY_HALF, BODY_HALF),
        mask   = MASK_SOLID_BRUSHONLY, filter = filter,
    })
    if not tr.Hit then return true, nil end
    local normal = tr.HitNormal
    local slide  = moveDir - normal * moveDir:Dot(normal)
    if slide:LengthSqr() < 0.001 then
        local a, b = BuildTangents(normal)
        slide = math.abs(a:Dot(moveDir)) >= math.abs(b:Dot(moveDir)) and a or b
    end
    slide:Normalize()
    return false, slide
end

-- ---------------------------------------------------------
--  COLLISION RESILIENCE
-- ---------------------------------------------------------
local function BumpArmor(self, now)
    if now - self._lastBump < BUMP_COOLDOWN then return false end
    self._lastBump = now
    self._armorHP  = self._armorHP - 1
    if now - self._streakStart > STREAK_WINDOW then
        self._bumpStreak  = 0
        self._streakStart = now
    end
    self._bumpStreak = self._bumpStreak + 1
    return self._armorHP <= 0 or self._bumpStreak > STREAK_MAX
end

local function WallKick(self, hitNormal)
    local cur     = self:GetForward()
    local reflect = cur - hitNormal * (2 * cur:Dot(hitNormal))
    local kicked  = LerpVector(WALL_KICK_STRENGTH, cur, reflect)
    kicked:Normalize()
    self:SetAngles(DirToAngle(kicked))
    self:SetAbsVelocity(kicked * CRUISE_SPEED)
end

-- ---------------------------------------------------------
--  AIM POSITION
-- ---------------------------------------------------------
local function GetAimPos(self)
    local enemy = self:GetEnemy()
    if not IsValid(enemy) and IsValid(self.NikitaTargetEnt) then
        enemy = self.NikitaTargetEnt
    end
    if IsValid(enemy) then
        local p   = enemy:GetPos()
        local vel = GetEntVelocity(enemy)
        self._lkPos  = Vector(p.x, p.y, p.z + TARGET_Z_OFFS)
        self._lkVel  = vel
        self._lkTime = CurTime()
        return Vector(
            p.x + vel.x * LEAD_TIME,
            p.y + vel.y * LEAD_TIME,
            p.z + TARGET_Z_OFFS + vel.z * LEAD_TIME
        )
    end
    if self._lkPos and self._lkTime then
        local age = CurTime() - self._lkTime
        if age < LAST_KNOWN_TIMEOUT then
            return self._lkPos + (self._lkVel or Vector(0,0,0)) * age
        end
    end
    return nil
end

-- ---------------------------------------------------------
--  TIP CAP HELPERS
-- ---------------------------------------------------------
local function SpawnTipCap(missile)
    if not IsValid(missile) then return nil end
    local cap = ents.Create("prop_physics")
    if not IsValid(cap) then return nil end
    cap:SetModel(TIPCAP_MODEL)
    -- Place at the missile tip
    cap:SetPos(missile:GetPos() + missile:GetForward() * TIPCAP_OFFSET)
    cap:SetAngles(missile:GetAngles())
    cap:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    cap:Spawn()
    cap:Activate()
    cap:SetModelScale(TIPCAP_SCALE, 0)
    cap:DrawShadow(false)
    -- Physically disable while riding the missile: no motion, parented via manual position
    local phys = cap:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        phys:SetMass(1)
        phys:Wake()
    end
    -- Schedule removal in case it never gets ejected (missile removed without predet)
    local capRef = cap
    timer.Simple(TIPCAP_LIFETIME, function()
        if IsValid(capRef) then capRef:Remove() end
    end)
    return cap
end

local function EjectTipCap(missile)
    local cap = missile._tipCap
    if not IsValid(cap) then return end
    missile._tipCap = nil

    -- Release physics
    local phys = cap:GetPhysicsObject()
    if not IsValid(phys) then return end
    phys:EnableMotion(true)
    phys:SetMass(1)
    phys:Wake()

    -- Random kick: mostly forward-ish hemisphere + pure random lateral component
    -- so it clearly flies away from the missile
    local fwd    = missile:GetForward()
    local right  = missile:GetRight()
    local up     = missile:GetUp()
    local speed  = math.Rand(TIPCAP_VEL_MIN, TIPCAP_VEL_MAX)
    -- Random point on hemisphere in front of the missile
    -- theta in [0, pi/2] biased toward lateral to make it look dramatic
    local theta  = math.Rand(math.rad(35), math.rad(120))
    local phi    = math.Rand(0, math.pi * 2)
    local kickDir = fwd   * math.cos(theta)
                  + right * (math.sin(theta) * math.cos(phi))
                  + up    * (math.sin(theta) * math.sin(phi))
    kickDir:Normalize()

    phys:SetVelocity(kickDir * speed)
    phys:SetAngleVelocity(Vector(
        math.Rand(TIPCAP_ANGVEL_MIN, TIPCAP_ANGVEL_MAX),
        math.Rand(TIPCAP_ANGVEL_MIN, TIPCAP_ANGVEL_MAX),
        math.Rand(TIPCAP_ANGVEL_MIN, TIPCAP_ANGVEL_MAX)
    ))

    -- Schedule timed removal after it's been flying
    local capRef = cap
    timer.Simple(TIPCAP_LIFETIME, function()
        if IsValid(capRef) then capRef:Remove() end
    end)
end

-- ---------------------------------------------------------
--  UNIFORM-SPHERE CONE DIRECTION
--  Produces pellet directions uniformly distributed over the
--  solid angle of the cone (no axis-clustering bias).
--  aimDir MUST be normalised before calling.
-- ---------------------------------------------------------
local function UniformConeDir(aimDir, halfAngleDeg)
    -- Build an orthonormal basis aligned to aimDir
    local up    = math.abs(aimDir.z) < 0.999 and Vector(0, 0, 1) or Vector(1, 0, 0)
    local right = aimDir:Cross(up);  right:Normalize()
    local tang  = right:Cross(aimDir); tang:Normalize()

    -- Uniform sampling over the spherical cap:
    -- cos(theta) drawn uniformly in [cos(halfAngle), 1]
    -- This is the correct inverse-CDF for solid-angle-uniform cone sampling.
    local cosHalf = math.cos(math.rad(halfAngleDeg))
    local cosT    = cosHalf + math.random() * (1.0 - cosHalf)   -- in [cosHalf, 1]
    local sinT    = math.sqrt(math.max(0, 1.0 - cosT * cosT))
    local phi     = math.random() * 2 * math.pi

    local d = aimDir * cosT
            + right  * (sinT * math.cos(phi))
            + tang   * (sinT * math.sin(phi))
    d:Normalize()
    return d
end

-- ---------------------------------------------------------
--  PRE-DETONATION SHOTGUN BURST
-- ---------------------------------------------------------
function ENT:Nikita_PreDetBurst()
    if self.Nikita_Exploded    then return end
    if self._predetFired       then return end
    self._predetFired = true

    local muzzlePos = self:GetPos() + self:GetForward() * PREDET_NOSE_OFFS
    local owner     = IsValid(self.NikitaOwner) and self.NikitaOwner or self

    -- --------------------------------------------------------
    --  Cone aim: point toward the missile's current target,
    --  using the same lead-position the guidance system uses.
    --  Falls back to missile forward if no target is known.
    -- --------------------------------------------------------
    local aimPos = GetAimPos(self)
    local aimDir
    if aimPos then
        aimDir = (aimPos - muzzlePos):GetNormalized()
        -- Edge case: aimPos is right at the muzzle (shouldn't happen,
        -- but guard against a zero vector)
        if aimDir:LengthSqr() < 0.01 then
            aimDir = self:GetForward()
        end
    else
        aimDir = self:GetForward()
    end

    -- Eject the tip cap before firing the pellets
    EjectTipCap(self)

    -- Stage-1 fragmentation sound (distinct from stage-2 explosion)
    sound.Play(SND_PREDET_BLAST, muzzlePos, 95, math.random(95, 105))
    sound.Play(SND_PREDET, muzzlePos, 85, 100)

    -- Broadcast muzzle flash to all clients
    net.Start("NikitaMuzzleFlash")
        net.WriteVector(muzzlePos)
        net.WriteVector(aimDir)
    net.Broadcast()

    for i = 1, PREDET_PELLETS do
        -- Use uniform solid-angle sampling so pellets are evenly distributed
        -- across the cone face, not clustered at the axis
        local pelletDir = UniformConeDir(aimDir, PREDET_SPREAD_DEG)

        local tr = util.TraceLine({
            start  = muzzlePos,
            endpos  = muzzlePos + pelletDir * PREDET_RANGE,
            filter  = { self },
            mask    = MASK_SHOT,
        })

        local endPos = tr.Hit and tr.HitPos or (muzzlePos + pelletDir * PREDET_RANGE)

        net.Start("NikitaPelletTracer")
            net.WriteVector(muzzlePos)
            net.WriteVector(endPos)
        net.Broadcast()

        if tr.Hit then
            local ed = EffectData()
            ed:SetOrigin(tr.HitPos)
            ed:SetNormal(tr.HitNormal)
            ed:SetSurfaceProp(tr.SurfaceProps)
            ed:SetDamageType(DMG_BULLET)
            util.Effect("Impact", ed)

            if IsValid(tr.Entity) and tr.Entity ~= self then
                local dmginfo = DamageInfo()
                dmginfo:SetDamage(PREDET_PELLET_DMG)
                dmginfo:SetAttacker(owner)
                dmginfo:SetInflictor(self)
                dmginfo:SetDamageType(DMG_BULLET)
                dmginfo:SetDamagePosition(tr.HitPos)
                dmginfo:SetDamageForce(pelletDir * PREDET_PELLET_DMG * 50)
                tr.Entity:TakeDamageInfo(dmginfo)
            end
        end
    end

    local missileRef = self
    timer.Simple(PREDET_DELAY, function()
        if IsValid(missileRef) and not missileRef.Nikita_Exploded then
            missileRef:Nikita_DoExplosion()
        end
    end)
end

-- ---------------------------------------------------------
--  INITIALIZE
-- ---------------------------------------------------------
function ENT:CustomOnInitialize()
    self:SetModel("models/nikita/mam.mdl")
    self:SetModelScale(1.3, 0)
    self:SetSolid(SOLID_BBOX)
    self:SetCollisionBounds(Vector(-12,-12,-12), Vector(12,12,12))

    self.Nikita_SpawnTime  = CurTime()
    self.Nikita_ExpireTime = CurTime() + self.Nikita_LifeTime
    self.Nikita_Exploded   = false

    self.HasMeleeAttack = false
    self.HasRangeAttack = false

    self._wp           = {}
    self._wpIdx        = 1
    self._pathDir      = nil
    self._aptLock      = false
    self._nextPath     = 0

    self._armorHP      = ARMOR_MAX
    self._lastBump     = -999
    self._bumpStreak   = 0
    self._streakStart  = CurTime()
    self._nextArmorReg = CurTime() + ARMOR_REGEN_INT

    self._lkPos        = nil
    self._lkVel        = nil
    self._lkTime       = nil

    self._lastPhysDmg  = -999
    self._predetFired  = false

    self._lockOnArmed  = true
    self._lockOnActive = false

    -- Spawn the tip cap and store reference
    self._tipCap = nil
    local selfRef = self
    -- Use timer.Simple(0) so the missile has fully initialised its position/angles
    timer.Simple(0, function()
        if not IsValid(selfRef) then return end
        selfRef._tipCap = SpawnTipCap(selfRef)
    end)

    sound.Play(SND_FIRE, self:GetPos(), 90, 100)
    self:EmitSound(SND_WHISTLE, 80, 100)
    self:EmitSound(SND_FLAME,   75, 100)
end

function ENT:CustomOnPostInitialize()
    self:SetMoveType(MOVETYPE_NOCLIP)
    self:SetSolid(SOLID_BBOX)
    self:AddSolidFlags(FSOLID_NOT_SOLID)
    self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
    self:SetCollisionBounds(Vector(-12,-12,-12), Vector(12,12,12))

    self:PhysicsInitSphere(12, "metal")
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        phys:SetMass(1)
        phys:EnableCollisions(true)
        phys:Wake()
    end
    self:StartMotionController()
end

local PHYS_DMG_COOLDOWN = 0.05

function ENT:PhysicsCollide(data, physobj)
    if self.Nikita_Exploded then return end
    local other = data.HitEntity
    if IsWorldEnt(other) then return end
    local now = CurTime()
    if now - self._lastPhysDmg < PHYS_DMG_COOLDOWN then return end
    self._lastPhysDmg = now
    local speed = data.Speed
    if speed < PHYS_DMG_MIN_SPEED then return end
    local dmg  = math.max(1, speed * PHYS_DMG_SCALE)
    local inf  = IsValid(other) and other or game.GetWorld()
    local dmginfo = DamageInfo()
    dmginfo:SetDamage(dmg)
    dmginfo:SetAttacker(inf)
    dmginfo:SetInflictor(inf)
    dmginfo:SetDamageType(DMG_CRUSH)
    dmginfo:SetDamagePosition(self:GetPos())
    dmginfo:SetDamageForce(data.OurOldVelocity * dmg)
    self:TakeDamageInfo(dmginfo)
end

function ENT:CustomOnTakeDamage_BeforeDamage(dmginfo, hitgroup)
    local dmgType     = dmginfo:GetDamageType()
    local dmgAttacker = dmginfo:GetAttacker()
    if dmgType == DMG_CRUSH and IsWorldEnt(dmgAttacker) then
        dmginfo:SetDamage(0)
        return
    end
    if self:Health() - dmginfo:GetDamage() <= 0 then
        self:Nikita_DoExplosion(dmginfo)
    end
end

-- ---------------------------------------------------------
--  FALLOFF BLAST HELPERS
-- ---------------------------------------------------------
local FALLOFF_MIN_FRAC = 0.08

local function EntAimPos( ent )
    local phys = ent:GetPhysicsObject()
    if IsValid( phys ) then return phys:GetMassCenter() end
    return ent:GetPos()
end

local function DoFalloffBlastDamage( inflictor, attacker, origin, radius, maxDmg )
    for _, ent in ipairs( ents.FindInSphere( origin, radius ) ) do
        if not IsValid( ent ) then continue end
        if ent == inflictor   then continue end

        local entPos = EntAimPos( ent )
        local los = util.TraceLine({
            start  = origin,
            endpos = entPos,
            mask   = MASK_SOLID_BRUSHONLY,
            filter = inflictor,
        })
        if los.Hit then continue end

        local dist  = ( entPos - origin ):Length()
        local frac  = math.Clamp( 1 - ( dist / radius ), 0, 1 )
        local scale = FALLOFF_MIN_FRAC + ( 1 - FALLOFF_MIN_FRAC ) * frac
        local dmg   = maxDmg * scale
        if dmg < 1 then continue end

        local dmginfo = DamageInfo()
        dmginfo:SetDamage( dmg )
        dmginfo:SetAttacker( attacker )
        dmginfo:SetInflictor( inflictor )
        dmginfo:SetDamageType( DMG_BLAST )
        dmginfo:SetDamagePosition( origin )
        dmginfo:SetDamageForce( ( entPos - origin ):GetNormalized() * dmg * 80 )
        ent:TakeDamageInfo( dmginfo )
    end
end

-- ---------------------------------------------------------
--  EXPLOSION
-- ---------------------------------------------------------
function ENT:Nikita_DoExplosion(dmginfo)
    if self.Nikita_Exploded then return end
    self.Nikita_Exploded = true

    -- Safety: eject cap in case we explode without going through PreDetBurst
    EjectTipCap(self)

    local pos   = self:GetPos()
    local dmg   = self.Nikita_Damage or 120
    local rad   = self.Nikita_Radius or 700
    local owner = IsValid(self.NikitaOwner) and self.NikitaOwner or self

    self:StopSound(SND_WHISTLE)
    self:StopSound(SND_FLAME)
    self:StopSound(SND_LOCKON)

    sound.Play("ambient/explosions/explode_8.wav", pos, 100, 100)

    for _, ply in ipairs( player.GetAll() ) do
        if not IsValid( ply ) then continue end
        local _sd = ( ply:GetPos() - pos ):Length()
        if _sd < 3000 then
            local _sf = math.Clamp( 1 - ( _sd / 3000 ), 0, 1 )
            util.ScreenShake( ply:GetPos(), 20 * _sf, 200, 1.0, 1 )
        end
    end

    local ed = EffectData()
    ed:SetOrigin(pos)
    util.Effect("Explosion", ed)

    local pe = ents.Create("env_physexplosion")
    if IsValid(pe) then
        pe:SetPos(pos)
        pe:SetKeyValue("Magnitude",  tostring(math.floor(dmg * 5)))
        pe:SetKeyValue("radius",     tostring(rad))
        pe:SetKeyValue("spawnflags", "19")
        pe:Spawn(); pe:Activate()
        pe:Fire("Explode", "", 0)
        pe:Fire("Kill",    "", 0.5)
    end

    DoFalloffBlastDamage( self, owner, pos + Vector(0,0,50), rad, dmg )
    self:Remove()
end

-- ---------------------------------------------------------
--  MAIN THINK
-- ---------------------------------------------------------
function ENT:CustomOnThink()
    if self.Nikita_Exploded then return end

    if self:GetMoveType() ~= MOVETYPE_NOCLIP then
        self:SetMoveType(MOVETYPE_NOCLIP)
        return
    end

    local now = CurTime()
    local dt  = math.max(FrameTime(), 0.001)

    if self.Nikita_ExpireTime and now > self.Nikita_ExpireTime then
        self:Nikita_PreDetBurst()
        return
    end

    if now >= self._nextArmorReg then
        self._nextArmorReg = now + ARMOR_REGEN_INT
        self._armorHP = math.min(self._armorHP + 1, ARMOR_MAX)
    end

    local myPos      = self:GetPos()
    local currentDir = self:GetForward()
    local filter     = { self }

    -- Keep the tip cap glued to the missile nose every tick
    if IsValid(self._tipCap) then
        local capPos = myPos + currentDir * TIPCAP_OFFSET
        self._tipCap:SetPos(capPos)
        self._tipCap:SetAngles(self:GetAngles())
    end

    local aimPos = GetAimPos(self)
    if not aimPos then return end

    local enemy = self:GetEnemy()
    if not IsValid(enemy) and IsValid(self.NikitaTargetEnt) then
        enemy = self.NikitaTargetEnt
    end
    if IsValid(enemy) then
        local distToEnemy = myPos:Distance(enemy:GetPos())

        if self._lockOnArmed and distToEnemy <= LOCKON_DIST then
            self._lockOnArmed  = false
            self._lockOnActive = true
            sound.Play(SND_LOCKON, myPos, 85, 100)
        elseif self._lockOnActive and distToEnemy > LOCKON_DIST then
            self:StopSound(SND_LOCKON)
            self._lockOnActive = false
            self._lockOnArmed  = true
        end

        if distToEnemy <= (self.Nikita_ProxRadius or 220) then
            self:Nikita_PreDetBurst()
            return
        end
    end

    if now >= self._nextPath then
        self._nextPath = now + PATHFIND_INTERVAL
        UpdatePath(self, myPos, aimPos, filter)
    end

    local noseTip = myPos + currentDir * 20

    local eRep, eHit, eMin = ComputeRepulsion(self, noseTip, RAYS_EMERG, EMERG_DIST, filter)
    local tRep, tHit, tMin = ComputeRepulsion(self, noseTip, RAYS_TACT,  TACT_DIST,  filter)

    local sRep, sHit = Vector(0,0,0), false
    local trL = CastLocalRay(self, noseTip, 0,  90, TACT_DIST, filter)
    local trR = CastLocalRay(self, noseTip, 0, -90, TACT_DIST, filter)
    local inCorridor = trL.Hit and trR.Hit
        and (noseTip-trL.HitPos):Length() < TACT_DIST
        and (noseTip-trR.HitPos):Length() < TACT_DIST

    local activeTurn = TURN_RATE
    if inCorridor then
        activeTurn = TURN_RATE * CORRIDOR_TURN_MULT
    else
        sRep, sHit = ComputeRepulsion(self, noseTip, RAYS_STRAT, STRAT_DIST, filter)
    end

    local rawHoming = (aimPos - myPos):GetNormalized()
    local pathBlend = self._aptLock and PATH_BLEND_LOCKED or PATH_BLEND_NORMAL
    local homingDir = rawHoming
    if self._pathDir then
        homingDir = LerpVector(pathBlend, rawHoming, self._pathDir)
        homingDir:Normalize()
    end

    local totalRep = Vector(0,0,0)
    if eHit then local n=eRep:Length(); if n>0 then totalRep=totalRep+(eRep/n)*EMERG_STRENGTH end end
    if tHit then local n=tRep:Length(); if n>0 then totalRep=totalRep+(tRep/n)*TACT_STRENGTH  end end
    if sHit then local n=sRep:Length(); if n>0 then totalRep=totalRep+(sRep/n)*STRAT_STRENGTH end end

    local desiredDir
    local repLen = totalRep:Length()
    if repLen > 0.01 then
        local bf
        if eHit and eMin < EMERG_DIST then
            bf = 1.0
        elseif tHit then
            bf = math.Clamp(1.0 - (tMin / TACT_DIST), 0, TACT_STRENGTH)
        else
            bf = STRAT_STRENGTH * 0.5
        end
        if self._aptLock and not (eHit and eMin < EMERG_DIST) then
            bf = bf * 0.4
        end
        desiredDir = LerpVector(bf, homingDir, totalRep:GetNormalized())
        desiredDir:Normalize()
    else
        desiredDir = homingDir
    end

    local fits, slideDir = ClearanceProbe(myPos, desiredDir, filter)
    if not fits and slideDir then
        desiredDir = LerpVector(0.7, desiredDir, slideDir)
        desiredDir:Normalize()
    end

    local maxAng = activeTurn * dt
    local cosA   = math.Clamp(currentDir:Dot(desiredDir), -1, 1)
    local ang    = math.acos(cosA)
    local moveDir
    if ang < 0.001 then
        moveDir = desiredDir
    else
        local t = math.min(maxAng / ang, 1.0)
        moveDir = LerpVector(t, currentDir, desiredDir)
        moveDir:Normalize()
    end

    self:SetAngles(DirToAngle(moveDir))
    self:SetAbsVelocity(moveDir * CRUISE_SPEED)

    local stepDist = CRUISE_SPEED * dt + 16
    local tr = util.TraceHull({
        start  = myPos,
        endpos = myPos + moveDir * stepDist,
        mins   = Vector(-8,-8,-8), maxs = Vector(8,8,8),
        mask   = MASK_SHOT, filter = filter,
    })
    if tr.Hit and tr.HitWorld then
        local dead = BumpArmor(self, now)
        if dead then
            self:SetPos(myPos + (aimPos - myPos):GetNormalized() * 32)
            self._armorHP    = ARMOR_MAX
            self._bumpStreak = 0
        else
            WallKick(self, tr.HitNormal)
        end
    end
end

function ENT:CustomOnThink_AIEnabled()
end

function ENT:CustomOnKilled(dmginfo, hitgroup)
    self:Nikita_DoExplosion(dmginfo)
end
