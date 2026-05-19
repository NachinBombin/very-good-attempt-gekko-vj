-- init.lua  (SERVER)
-- M242 Bushmaster 25mm round.
-- Physics / movement / damage / orbit: UNCHANGED from original.
-- Impact visual replaced with GAU-style: networked decal + dust puff +
-- bullet-impact sounds + 0.9% ignited-gib ricochet.

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

util.AddNetworkString("GekkoBushImpact")
-- GekkoBulletImpact is kept registered by the bullet_impact_system if present;
-- Bushmaster no longer sends it, but we don't remove its registration.
util.AddNetworkString("GekkoBulletImpact")

-- =========================================================================
-- Configuration  (physics/damage UNCHANGED)
-- =========================================================================
local SPEED          = 3950
local ORBIT_RADIUS_A = 4
local ORBIT_RADIUS_B = 3
local ORBIT_SPEED    = 4.5
local LIFETIME       = 12
local DAMAGE         = 35
local BLAST_RADIUS   = 7

local FLAME_LOOP_SND  = "gekko/brushmaster_25mm/shellwhiz.wav"
local FLAME_SND_LEVEL = 20

-- ─── Impact sounds (same list as GAU bullet) ─────────────────────────────────
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
for _, s in ipairs(IMPACT_SOUNDS) do util.PrecacheSound(s) end

local GIB_RICO_CHANCE = 0.009
local GIB_MODEL       = "models/gibs/wood_gib01e.mdl"
util.PrecacheModel(GIB_MODEL)

-- ─── Ignited gib (mirrors ent_ac47_m134_bullet/init.lua exactly) ─────────────
local function SpawnIgnitedGib(hitPos, hitNormal)
    local gib = ents.Create("prop_physics")
    if not IsValid(gib) then return end

    gib:SetModel(GIB_MODEL)
    gib:SetPos(hitPos + hitNormal * 3)
    gib:SetAngles(Angle(
        math.random(0, 360),
        math.random(0, 360),
        math.random(0, 360)
    ))
    gib:Spawn()
    gib:Activate()

    local phys = gib:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()

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
        phys:SetAngleVelocity(Vector(
            math.Rand(-400, 400),
            math.Rand(-400, 400),
            math.Rand(-400, 400)
        ))
    end

    gib:Ignite(0, 0)
end

-- =========================================================================
-- Initialize  (UNCHANGED)
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

    self:EmitSound(FLAME_LOOP_SND, FLAME_SND_LEVEL, 100, 1)

    timer.Simple(LIFETIME, function()
        if IsValid(self) then self:Remove() end
    end)
end

-- =========================================================================
-- Think  (UNCHANGED)
-- =========================================================================
function ENT:Think()
    local t     = CurTime() - self._birthTime
    local phase = t * ORBIT_SPEED

    local centre = self._origin + self._forward * (SPEED * t)
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
    self:SetAngles(self._fixedAngle)
    self:NextThink(CurTime())
    return true
end

-- =========================================================================
-- Touch  (UNCHANGED)
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
-- Explode  — physics/damage UNCHANGED; visuals replaced with GAU impact FX
-- =========================================================================
function ENT:Explode(hitPos, hitNormal, hitEnt)
    if self._exploded then return end
    self._exploded = true

    self:StopSound(FLAME_LOOP_SND)

    -- ─ Damage (UNCHANGED) ─
    local dmg = DamageInfo()
    dmg:SetDamage(DAMAGE)
    dmg:SetAttacker(IsValid(self:GetOwner()) and self:GetOwner() or self)
    dmg:SetInflictor(self)
    dmg:SetDamageType(DMG_BLAST)
    dmg:SetDamagePosition(hitPos)
    dmg:SetDamageForce(hitNormal * -DAMAGE * 50)

    util.BlastDamage(
        self,
        IsValid(self:GetOwner()) and self:GetOwner() or self,
        hitPos, BLAST_RADIUS, DAMAGE
    )

    -- ─ GAU-style impact broadcast ─
    local sndIdx = math.random(#IMPACT_SOUNDS)
    net.Start("GekkoBushImpact")
        net.WriteVector(hitPos)
        net.WriteVector(hitNormal)
        net.WriteUInt(sndIdx, 8)
    net.Broadcast()

    -- ─ 0.9% ignited gib ricochet (server-only, same as GAU) ─
    if math.random() < GIB_RICO_CHANCE then
        SpawnIgnitedGib(hitPos, hitNormal)
    end

    self:Remove()
end
