include("shared.lua")

-- ============================================================
--  npc_vj_gekko_nikita  /  init.lua
-- ============================================================

-- ---------------------------------------------------------
--  TUNING
-- ---------------------------------------------------------
local CRUISE_SPEED         = 310
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

local SCOUT_RAY_DIST     = 2000
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
local PHYS_DMG_MIN_SPEED  = 200   -- below this speed, no damage
local PHYS_DMG_SCALE      = 0.06  -- damage = impactSpeed * scale

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

-- Returns true if 'ent' is a world brush / static geometry.
-- Used to distinguish "weapon projectile hit us" from "we scraped a wall".
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
--  COLLISION RESILIENCE  (geometry only, never health)
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
--  INITIALIZE
-- ---------------------------------------------------------
function ENT:CustomOnInitialize()
    self:SetModel("models/weapons/w_missile_launch.mdl")
    self:SetModelScale(7, 0)
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
end

function ENT:CustomOnPostInitialize()
    self:SetMoveType(MOVETYPE_NOCLIP)

    -- SOLID_BBOX + FSOLID_NOT_SOLID:
    --   SOLID_BBOX       -> hitscan FireBullets (MASK_SHOT) registers a hit.
    --   FSOLID_NOT_SOLID -> won't physically block NPCs / locomotor.
    self:SetSolid(SOLID_BBOX)
    self:AddSolidFlags(FSOLID_NOT_SOLID)
    self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
    self:SetCollisionBounds(Vector(-12,-12,-12), Vector(12,12,12))

    -- Real vphysics shadow so PhysicsCollide fires for physics projectiles.
    -- Motion disabled so it never moves under physics.
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

-- ---------------------------------------------------------
--  PHYSICS / DEBRIS DAMAGE
--
--  PhysicsCollide fires whenever any physics object touches the
--  vphysics shadow — including the world itself when the missile
--  clips a wall.  We only want WEAPON projectiles and props to
--  count, not geometry.  IsWorldEnt() gates that distinction.
--
--  Hitscan weapons reach OnTakeDamage directly via SOLID_BBOX.
-- ---------------------------------------------------------
local PHYS_DMG_COOLDOWN = 0.05

function ENT:PhysicsCollide(data, physobj)
    if self.Nikita_Exploded then return end

    -- Ignore collisions with world geometry / static brushes.
    -- Those are handled by the wall-bump resilience system (BumpArmor)
    -- and must NEVER feed into health.
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
    -- Block DMG_CRUSH that originates from the world entity.
    -- This catches any path where a wall-scrape noise or residual
    -- vphysics event slips through as DMG_CRUSH with world as attacker.
    local dmgType     = dmginfo:GetDamageType()
    local dmgAttacker = dmginfo:GetAttacker()
    if dmgType == DMG_CRUSH and IsWorldEnt(dmgAttacker) then
        dmginfo:SetDamage(0)
        return
    end

    -- Immediate explosion when any weapon hit is lethal, bypassing
    -- VJ's scheduler stall (HasDeathRagdoll=false leaves it ambiguous).
    if self:Health() - dmginfo:GetDamage() <= 0 then
        self:Nikita_DoExplosion(dmginfo)
    end
end

-- ---------------------------------------------------------
--  EXPLOSION
-- ---------------------------------------------------------
function ENT:Nikita_DoExplosion(dmginfo)
    if self.Nikita_Exploded then return end
    self.Nikita_Exploded = true

    local pos   = self:GetPos()
    local dmg   = self.Nikita_Damage or 120
    local rad   = self.Nikita_Radius or 700
    local owner = IsValid(self.NikitaOwner) and self.NikitaOwner or self

    sound.Play("ambient/explosions/explode_8.wav", pos, 100, 100)
    util.ScreenShake(pos, 16, 200, 1, 3000)

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

    util.BlastDamage(self, owner, pos + Vector(0,0,50), rad, dmg)
    self:Remove()
end

-- ---------------------------------------------------------
--  MAIN THINK
-- ---------------------------------------------------------
function ENT:CustomOnThink()
    if self.Nikita_Exploded then return end

    -- Keep NOCLIP every tick in case VJ's scheduler resets it.
    -- Do NOT reset solid — SOLID_BBOX+FSOLID_NOT_SOLID must persist.
    if self:GetMoveType() ~= MOVETYPE_NOCLIP then
        self:SetMoveType(MOVETYPE_NOCLIP)
        return
    end

    local now = CurTime()
    local dt  = math.max(FrameTime(), 0.001)

    if self.Nikita_ExpireTime and now > self.Nikita_ExpireTime then
        self:Nikita_DoExplosion(); return
    end

    if now >= self._nextArmorReg then
        self._nextArmorReg = now + ARMOR_REGEN_INT
        self._armorHP = math.min(self._armorHP + 1, ARMOR_MAX)
    end

    local myPos      = self:GetPos()
    local currentDir = self:GetForward()
    local filter     = { self }

    local aimPos = GetAimPos(self)
    if not aimPos then return end

    local enemy = self:GetEnemy()
    if not IsValid(enemy) and IsValid(self.NikitaTargetEnt) then
        enemy = self.NikitaTargetEnt
    end
    if IsValid(enemy) then
        if myPos:Distance(enemy:GetPos()) <= (self.Nikita_ProxRadius or 220) then
            self:Nikita_DoExplosion(); return
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

    -- Wall-bump resilience: uses BumpArmor (geometry counter) only.
    -- This path NEVER damages health — that is intentional.
    -- World collision = navigate around it, not die from it.
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
