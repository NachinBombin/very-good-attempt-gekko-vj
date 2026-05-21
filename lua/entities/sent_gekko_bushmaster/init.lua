-- init.lua  (SERVER)
-- M242 Bushmaster 25mm round.

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

util.AddNetworkString("GekkoBushImpact")
util.AddNetworkString("GekkoBulletImpact")

-- =========================================================================
-- Configuration
-- =========================================================================
local SPEED          = 3950
local ORBIT_RADIUS_A = 4
local ORBIT_RADIUS_B = 3
local ORBIT_SPEED    = 4.5
local LIFETIME       = 12
local DAMAGE         = 35
local BLAST_RADIUS   = 7

local GRAVITY_SCALE  = 0.55
local SOURCE_GRAVITY = 600
local G_ACCEL        = SOURCE_GRAVITY * GRAVITY_SCALE

local FLAME_LOOP_SND  = "gekko/brushmaster_25mm/shellwhiz.wav"
local FLAME_SND_LEVEL = 20

local IMPACT_SOUNDS = {
    "physics/concrete/impact_bullet1.wav",
    "physics/concrete/impact_bullet2.wav",
    "physics/concrete/impact_bullet3.wav",
    "physics/dirt/impact_bullet1.wav",
    "physics/dirt/impact_bullet2.wav",
    "physics/dirt/impact_bullet3.wav",
    "physics/metal/metal_solid_impact_bullet1.wav",
    "physics/metal/metal_solid_impact_bullet2.wav",
    "physics/metal/metal_solid_impact_bullet3.wav",
}

local GIB_RICO_CHANCE = 0.15
local GIB_LIFETIME    = 3.5
local GIB_MODELS = {
    "models/props_junk/PopCan01a.mdl",
    "models/props_junk/MetalBucket01a.mdl",
    "models/props_debris/concrete_chunk01a.mdl",
}

-- =========================================================================
-- Gib helper
-- =========================================================================
local function SpawnIgnitedGib(hitPos, hitNormal)
    local mdl = GIB_MODELS[math.random(#GIB_MODELS)]
    local gib = ents.Create("prop_physics")
    if not IsValid(gib) then return end
    gib:SetModel(mdl)
    gib:SetPos(hitPos + hitNormal * 4)
    gib:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    gib:Spawn(); gib:Activate()
    gib:DrawShadow(false)
    timer.Simple(GIB_LIFETIME, function()
        if IsValid(gib) then gib:Remove() end
    end)
    local phys = gib:GetPhysicsObject()
    if not IsValid(phys) then gib:Remove() return end
    local helper
    if math.abs(hitNormal.z) < 0.9 then
        helper = Vector(0, 0, 1)
    else
        helper = Vector(1, 0, 0)
    end
    local tangent   = hitNormal:Cross(helper)  tangent:Normalize()
    local bitangent = hitNormal:Cross(tangent) bitangent:Normalize()
    local cos_theta = math.random()
    local sin_theta = math.sqrt(1 - cos_theta * cos_theta)
    local phi       = math.random() * (2 * math.pi)
    local cp        = math.cos(phi)
    local sp        = math.sin(phi)
    local nx, ny, nz = hitNormal.x, hitNormal.y, hitNormal.z
    local dx = nx * cos_theta + tangent.x * (sin_theta * cp) + bitangent.x * (sin_theta * sp)
    local dy = ny * cos_theta + tangent.y * (sin_theta * cp) + bitangent.y * (sin_theta * sp)
    local dz = nz * cos_theta + tangent.z * (sin_theta * cp) + bitangent.z * (sin_theta * sp)
    local dlen = math.sqrt(dx*dx + dy*dy + dz*dz)
    if dlen < 0.001 then gib:Remove() return end
    dx = dx / dlen  dy = dy / dlen  dz = dz / dlen
    local speed = math.Rand(120, 340)
    phys:SetVelocity(Vector(dx * speed, dy * speed, dz * speed))
    phys:SetAngleVelocity(Vector(math.Rand(-400,400), math.Rand(-400,400), math.Rand(-400,400)))
    gib:Ignite(0, 0)
end

-- =========================================================================
-- Falloff blast helpers
-- =========================================================================
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

-- =========================================================================
-- Initialize
-- =========================================================================
function ENT:Initialize()
    self:SetModel("models/weapons/w_missile.mdl")
    self:SetModelScale(0.21, 0)
    self:SetMoveType(MOVETYPE_NOCLIP)
    self:SetSolid(SOLID_BBOX)
    self:SetCollisionBounds(Vector(-4, -4, -4), Vector(4, 4, 4))
    self:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
    self:DrawShadow(false)

    local now = CurTime()
    self:SetBirthTime(now)
    self:SetSpawnPos(self:GetPos())
    self:SetSpawnDir(self:GetForward())

    self._birthTime  = now
    self._origin     = self:GetPos()
    self._forward    = self:GetForward()

    local fwd   = self._forward
    local right = fwd:Cross(Vector(0, 0, 1))
    if right:LengthSqr() < 0.001 then
        right = fwd:Cross(Vector(0, 1, 0))
    end
    right:Normalize()
    local up = right:Cross(fwd)
    up:Normalize()
    self._right      = right
    self._up         = up
    self._fixedAngle = self:GetAngles()

    self._vel        = self._forward * SPEED
    self._dropZ      = 0
    self._lastThink  = now

    self:EmitSound(FLAME_LOOP_SND, FLAME_SND_LEVEL, 100, 1)

    timer.Simple(LIFETIME, function()
        if IsValid(self) then self:Remove() end
    end)
end

-- =========================================================================
-- Think
-- =========================================================================
function ENT:Think()
    local now = CurTime()
    local dt  = now - self._lastThink
    self._lastThink = now
    if dt <= 0 then self:NextThink(now) return true end

    local t     = now - self._birthTime
    local phase = t * ORBIT_SPEED

    self._dropZ = self._dropZ - G_ACCEL * dt

    local centre = self._origin
                 + self._forward * (SPEED * t)
                 + Vector(0, 0, self._dropZ * t * 0.5)

    local offset = self._right * (ORBIT_RADIUS_A * math.cos(phase))
                 + self._up    * (ORBIT_RADIUS_B * math.sin(phase))
    local newPos = centre + offset

    local tr = util.TraceLine({
        start  = self:GetPos(),
        endpos = newPos,
        filter = { self, self:GetOwner() },
        mask   = MASK_SHOT,
    })

    if tr.Hit then
        self:Explode(tr.HitPos, tr.HitNormal, tr.Entity)
        return
    end

    self:SetPos(newPos)

    local dropDir = Vector(
        self._forward.x * SPEED,
        self._forward.y * SPEED,
        self._forward.z * SPEED + self._dropZ
    )
    if dropDir:LengthSqr() > 0.001 then
        self:SetAngles(dropDir:GetNormalized():Angle())
    else
        self:SetAngles(self._fixedAngle)
    end

    self:NextThink(now)
    return true
end

-- =========================================================================
-- Touch
-- =========================================================================
function ENT:Touch(other)
    if other == self:GetOwner() then return end
    local tr = util.TraceLine({
        start  = self:GetPos(),
        endpos = self:GetPos() + self:GetForward() * 8,
        filter = { self, self:GetOwner() },
        mask   = MASK_SHOT,
    })
    self:Explode(tr.HitPos, tr.HitNormal, other)
end

-- =========================================================================
-- Explode
-- =========================================================================
function ENT:Explode(hitPos, hitNormal, hitEnt)
    if self._exploded then return end
    self._exploded = true

    self:StopSound(FLAME_LOOP_SND)

    local owner = IsValid(self:GetOwner()) and self:GetOwner() or self
    DoFalloffBlastDamage( self, owner, hitPos, BLAST_RADIUS, DAMAGE )

    local sndIdx = math.random(#IMPACT_SOUNDS)

    -- Roll impact tier: 1=small(40%)  2=medium(40%)  3=large(20%)
    local r = math.random(100)
    local impactTier = (r <= 40) and 1 or (r <= 80) and 2 or 3

    -- Existing dust/decal/sound + new tier flash (cl_init.lua reads tier)
    net.Start("GekkoBushImpact")
        net.WriteVector(hitPos)
        net.WriteVector(hitNormal)
        net.WriteUInt(sndIdx, 8)
        net.WriteUInt(impactTier, 2)
    net.Broadcast()

    -- Projected-light impact flash (bullet_impact_system.lua preset 2)
    net.Start("GekkoBulletImpact")
        net.WriteVector(hitPos)
        net.WriteVector(hitNormal)
        net.WriteUInt(2, 3)
    net.Broadcast()

    if math.random() < GIB_RICO_CHANCE then
        SpawnIgnitedGib(hitPos, hitNormal)
    end

    self:Remove()
end
