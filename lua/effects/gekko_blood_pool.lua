-- ============================================================
-- lua/effects/gekko_blood_pool.lua
-- Byte-for-byte port of blood_pool.lua from the
-- call_of_duty_modern_warfare_2019_blood_pools_mod.
--
-- Texture provided by Bombin Base:
--   particle/AC/Experimental/vfx_bloodpool_alphatest_v2red
--
-- Differences from the original (prop_ragdoll compensation):
--   1. SetLighting(false) on the pool particle so the texture
--      renders at full brightness instead of being darkened by
--      env lighting / the Gekko's ignite flame.
--   2. Settling check uses physics-object velocity (summed over
--      all bones) instead of ent:GetVelocity(), which always
--      returns zero for manually-created prop_ragdolls.
--   3. ConVars / CL_BLOOD_POOL_ITERATION replaced with constants.
-- ============================================================

-- Mirrors BLOOD_POOL_TEXTURES[BLOOD_COLOR_RED] from the original addon.
local POOL_TEXTURES = {
    "particle/AC/Experimental/vfx_bloodpool_alphatest_v2red",
}

-- ConVar defaults (bloodpool_min_size / bloodpool_max_size / bloodpool_lifetime)
local POOL_MIN_SIZE = 35
local POOL_MAX_SIZE = 60
local POOL_LIFETIME = 180

-- convenience function: is a position solid
local function IsSolid(pos)
    return bit.band(util.PointContents(pos), CONTENTS_SOLID) == CONTENTS_SOLID
end

-- convenience function: gets maximum size of a blood pool at a given pos
-- ensures that blood pools don't appear floating in the air
local function GetMaximumPoolSize(pos, normal, limit)
    local limit = limit or 50

    local fraction = 1

    -- how far down we're allowed to go before failing the check
    local dn_dist = 4

    for size=1,limit,fraction do
        local dir = size
        -- this looks very silly, but it works.
        local spots = {
            pos + Vector(0, dir, 0),
            pos + Vector(dir, 0, 0),
            pos + Vector(dir, dir, 0),
            pos + Vector(dir, -dir, 0),
            pos + Vector(0, -dir, 0),
            pos + Vector(-dir, -dir, 0),
            pos + Vector(-dir, 0, 0),
            pos + Vector(-dir, dir, 0)
        }
    
        for i=1,#spots do
            local spos = spots[i] + Vector(0,0,1)
            local epos = spots[i] + Vector(0,0,-dn_dist)
            
            -- if the startpos is solid we're probably in a wall.
            if not IsSolid(spos) then
                local tr = util.TraceLine({start=spos, endpos=epos, mask=MASK_DEADSOLID})
                
                if not tr.Hit then
                    return (size-fraction)
                end
            end
        end
    end
    
    return limit
end

-- Returns true when the prop_ragdoll's physics objects have settled.
-- ent:GetVelocity() is always 0 for manually-created prop_ragdolls;
-- we must sum the actual phys-object speeds instead.
local function RagdollSettled(ent)
    for i = 0, ent:GetPhysicsObjectCount() - 1 do
        local phys = ent:GetPhysicsObjectNum(i)
        if IsValid(phys) and phys:GetVelocity():LengthSqr() > 1 then
            return false
        end
    end
    return true
end

function EFFECT:Init(data)
    local ent = data:GetEntity()
    if not IsValid(ent) then return end

    local bone  = data:GetAttachment() or 0
    local flags = data:GetFlags() or 0  -- 1: ttt mode, no fading

    if flags == 0 then
        self.LifeTime = CurTime() + POOL_LIFETIME
    end

    self.Entity  = ent
    self.BoneID  = bone
    self.LastPos = ent:GetPos()

    self.BloodTime    = CurTime() + math.random(2, 5)
    self.MaxBloodTime = CurTime() + 20  -- don't loop calculations potentially forever

    -- weird bug: think function happens before all the variables are set
    self.Initialized = true
end

function EFFECT:Think()
    if not self.Initialized then return true end

    if not IsValid(self.Entity) or (self.LifeTime and self.LifeTime < CurTime()) then
        -- todo: make dying blood pools fade
        if self.BloodPool then
            self.BloodPool:SetLifeTime(0)
            self.BloodPool:SetDieTime(0.05)
            self.BloodPool:SetStartSize(0)
            self.BloodPool:SetEndSize(0)
        end
        
        if self.ParticleEmitter and self.ParticleEmitter:IsValid() then
            self.ParticleEmitter:SetNoDraw(true)
            self.ParticleEmitter:Finish()
        end
        
        return false
    end

    local ent = self.Entity
    local pos = ent:GetBonePosition(self.BoneID)

    if not self.BloodPool then
        if not self.ParticleEmitter then
            self.ParticleEmitter = ParticleEmitter(pos, true)
        end

        if CurTime() >= self.BloodTime and CurTime() < self.MaxBloodTime then
            local tr = util.TraceLine({start=pos + Vector(0,0,32), endpos=pos + Vector(0,0,-128), mask=MASK_DEADSOLID})

            -- Use physics-object velocity for prop_ragdolls (ent:GetVelocity() is always 0)
            if tr.Hit and RagdollSettled(ent) then
                -- pull out of the ground a bit
                local pos = tr.HitPos + tr.HitNormal * 0.005
                
                local minsize = POOL_MIN_SIZE
                local maxsize = POOL_MAX_SIZE
                
                if minsize > maxsize then
                    minsize = maxsize
                end
                
                local size = GetMaximumPoolSize(pos, tr.HitNormal, math.random(minsize, maxsize))
                
                -- don't bother unless we can get a decent pool
                if size > 5 then
                    self.StartBleedingTime = CurTime()
                    self.EndSize = size

                    local pos = tr.HitPos
                    local ang = tr.HitNormal:Angle()
                    
                    ang.roll = math.random(0, 360)
                    
                    local maxtime = (self.EndSize/50) * 10

                    local particle = self.ParticleEmitter:Add(table.Random(POOL_TEXTURES), tr.HitPos)
                    particle:SetStartSize(80)
                    particle:SetEndSize(self.EndSize * 4.2)
                    particle:SetDieTime(maxtime * 1.2)
                    particle:SetStartAlpha(0)
                    particle:SetEndAlpha(500)
                    particle:SetPos(pos)
                    particle:SetAngles(ang)
                    -- Force full-brightness render: the Gekko's ignite flame and
                    -- environment lighting darken 3D particles, making the pool
                    -- appear as a shadow instead of red.
                    particle:SetLighting(false)

                    self.BloodPool = particle
                else
                    -- wait a bit before trying again
                    self.BloodTime = CurTime() + 1.0
                end
            end
        end
    else
        if self.ParticleEmitter and IsValid(self.ParticleEmitter) then
            self.ParticleEmitter:Finish()
        end
        
        -- keep the particle alive.
        local maxtime = (self.EndSize/50) * 10
        local timer = maxtime - ((self.StartBleedingTime + maxtime) - CurTime())

        local particle = self.BloodPool
        particle:SetLifeTime(math.min(timer, maxtime))
    end

    return true
end

function EFFECT:Render() end
