AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  -  Gekko Nikita Missile
--
--  MOVETYPE_NOCLIP: SetVelocity replaces velocity each tick.
--  MOVETYPE_FLY accumulates velocity (adds to current),
--  causing speed to explode to 4700+ u/s within 1 second.
--
--  Target Z is clamped via traceline to the actual ground
--  under the enemy + a fixed offset, preventing nose-dive
--  when the enemy stands on uneven or sloped terrain.
-- ============================================================

local SND_LAUNCH  = "buttons/button17.wav"
local SND_EXPLODE = "ambient/explosions/explode_8.wav"

local CRUISE_SPEED     = 380      -- u/s, constant
local MAX_TURN_RATE    = 55       -- degrees per second max turn
local LIFETIME         = 45      -- seconds before self-destruct
local PROXIMITY_RADIUS = 180     -- detonation proximity
local ENGINE_DELAY     = 0.5     -- seconds before steering activates
local TARGET_Z_OFFSET  = 80      -- height above ground to aim at

-- Resolve a safe aim position above the ground under an entity.
-- Falls back to entity pos + TARGET_Z_OFFSET if trace fails.
local function SafeAimPos( ent )
    local top = ent:GetPos() + Vector( 0, 0, 100 )
    local tr  = util.TraceLine({
        start  = top,
        endpos = top - Vector( 0, 0, 1000 ),
        mask   = MASK_SOLID_BRUSHONLY,
        filter = ent,
    })
    local groundZ = tr.Hit and tr.HitPos.z or ent:GetPos().z
    local pos     = ent:GetPos()
    return Vector( pos.x, pos.y, groundZ + TARGET_Z_OFFSET )
end

function ENT:Initialize()
    self:SetModel( "models/weapons/w_missile_launch.mdl" )
    -- MOVETYPE_NOCLIP: SetVelocity fully replaces velocity every tick.
    -- MOVETYPE_FLY has physics accumulation - SetVelocity ADDS each tick.
    self:SetMoveType( MOVETYPE_NOCLIP )
    self:SetSolid( SOLID_NONE )  -- noclip needs SOLID_NONE
    self:SetCollisionGroup( COLLISION_GROUP_PROJECTILE )

    self.Destroyed    = false
    self.EngineActive = false
    self.SpawnTime    = CurTime()
    self.HealthVal    = 50
    self.Damage       = 0
    self.Radius       = 0
    self._nextDebug   = 0
    -- TrackEnt / Target / Owner assigned post-Spawn via timer.Simple(0)
    -- in FireNikita. Initialize() sees them as nil -- expected.

    self:SetVelocity( self:GetForward() * 120 )
    sound.Play( SND_LAUNCH, self:GetPos(), 511, 60 )

    local selfRef = self
    timer.Simple( ENGINE_DELAY, function()
        if not IsValid( selfRef ) or selfRef.Destroyed then return end
        selfRef.Damage = math.random( 2500, 4500 )
        selfRef.Radius = math.random( 700,  1024 )
        selfRef.EngineActive = true
        print( "[NikitaDBG] Engine ACTIVE | TrackEnt=" .. tostring( selfRef.TrackEnt )
            .. " | Target=" .. tostring( selfRef.Target ) )
    end )

    self:NextThink( CurTime() )
end

function ENT:Think()
    self:NextThink( CurTime() )
    if self.Destroyed then return true end

    if CurTime() - self.SpawnTime > LIFETIME then
        self:MissileDoExplosion() ; return true
    end

    if not self.EngineActive then return true end

    -- Resolve aim position
    -- Use SafeAimPos for live tracking so Z is always above ground.
    -- Static Target fallback is already set safely by FireNikita.
    local aimPos
    if IsValid( self.TrackEnt ) then
        aimPos = SafeAimPos( self.TrackEnt )
    elseif self.Target then
        aimPos = self.Target
    end

    if aimPos then
        -- Proximity detonation
        if ( self:GetPos() - aimPos ):Length() < PROXIMITY_RADIUS then
            self:MissileDoExplosion() ; return true
        end

        -- Clamped turn rate steering.
        -- math.NormalizeAngle ensures we always take the shortest arc.
        local wantAngle = ( aimPos - self:GetPos() ):GetNormalized():Angle()
        local curAngle  = self:GetAngles()
        local maxDelta  = MAX_TURN_RATE * FrameTime()

        local function ClampAngleDelta( cur, want )
            local diff = math.NormalizeAngle( want - cur )
            return cur + math.Clamp( diff, -maxDelta, maxDelta )
        end

        self:SetAngles( Angle(
            ClampAngleDelta( curAngle.p, wantAngle.p ),
            ClampAngleDelta( curAngle.y, wantAngle.y ),
            0
        ))
    end

    -- Full velocity replacement every tick. Safe with MOVETYPE_NOCLIP.
    self:SetVelocity( self:GetForward() * CRUISE_SPEED )

    -- Touch detection (SOLID_NONE skips engine touch, so we trace manually)
    local tr = util.TraceLine({
        start  = self:GetPos(),
        endpos = self:GetPos() + self:GetForward() * ( CRUISE_SPEED * FrameTime() + 16 ),
        mask   = MASK_SHOT,
        filter = { self, IsValid( self.Owner ) and self.Owner or self },
    })
    if tr.Hit and IsValid( tr.Entity ) and tr.Entity ~= self.Owner then
        self:MissileDoExplosion() ; return true
    end
    if tr.HitWorld then
        self:MissileDoExplosion() ; return true
    end

    -- Debug print every 0.5s
    if CurTime() > self._nextDebug then
        self._nextDebug = CurTime() + 0.5
        print( string.format(
            "[NikitaDBG] aimPos=%s trackValid=%s ang=%s spd=%.0f",
            tostring( aimPos ),
            tostring( IsValid( self.TrackEnt ) ),
            tostring( self:GetAngles() ),
            self:GetVelocity():Length()
        ))
    end

    return true
end

function ENT:Touch( ent )
    -- Kept as secondary safety net even with SOLID_NONE
    if self.Destroyed then return end
    if CurTime() - self.SpawnTime < 0.3 then return end
    if ent == self.Owner then return end
    self:MissileDoExplosion()
end

function ENT:OnTakeDamage( dmginfo )
    if self.Destroyed then return end
    self.HealthVal = self.HealthVal - dmginfo:GetDamage()
    if self.HealthVal <= 0 then self:MissileDoExplosion() end
end

function ENT:MissileDoExplosion()
    if self.Destroyed then return end
    self.Destroyed = true
    self:StopParticles()
    local pos   = self:GetPos()
    local dmg   = self.Damage > 0 and self.Damage or 1200
    local rad   = self.Radius > 0 and self.Radius or 700
    local owner = IsValid( self.Owner ) and self.Owner or self
    sound.Play( SND_EXPLODE, pos, 100, 100 )
    util.ScreenShake( pos, 16, 200, 1, 3000 )
    local ed = EffectData() ; ed:SetOrigin( pos ) ; util.Effect( "Explosion", ed )
    local pe = ents.Create( "env_physexplosion" )
    if IsValid( pe ) then
        pe:SetPos( pos )
        pe:SetKeyValue( "Magnitude",  tostring( math.floor( dmg * 5 ) ) )
        pe:SetKeyValue( "radius",     tostring( rad ) )
        pe:SetKeyValue( "spawnflags", "19" )
        pe:Spawn() ; pe:Activate()
        pe:Fire( "Explode", "", 0 ) ; pe:Fire( "Kill", "", 0.5 )
    end
    util.BlastDamage( self, owner, pos + Vector( 0, 0, 50 ), rad, dmg )
    self:Remove()
end

function ENT:OnRemove()
    self.Destroyed = true
    self:StopParticles()
end
