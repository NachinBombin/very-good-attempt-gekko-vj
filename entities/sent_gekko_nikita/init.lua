AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  -  Gekko Nikita Homing Cruise Missile
--
--  HOMING NOTE:
--    TrackEnt is stored as a plain Lua field (self.TrackEnt),
--    NOT as an NWEntity. NWEntity is for client replication;
--    reading it back server-side on the same entity is unreliable.
--    FireNikita already sets missile.TrackEnt = enemy directly.
--    NWEntity "NikitaTrackEnt" is kept solely so the client
--    can read the target if needed (e.g. HUD sonar).
--
--  VELOCITY NOTE:
--    SetAbsVelocity() REPLACES velocity (no accumulation).
--    Never use SetVelocity() on MOVETYPE_NOCLIP.
-- ============================================================

local SND_EXPLODE   = "ambient/explosions/explode_8.wav"

local CRUISE_SPEED  = 400    -- true u/s, no accumulation
local TURN_SPEED    = 4.5    -- LerpVector t per second
local LIFETIME      = 45
local PROX_RADIUS   = 180
local ENGINE_DELAY  = 0.5
local TARGET_Z_OFFS = 40     -- aim at center-mass of target, not ground

local HULL_MINS = Vector( -8, -8, -8 )
local HULL_MAXS = Vector(  8,  8,  8 )

local function GetAimPos( trackEnt, fallback )
    -- Primary: track live entity at center-mass height
    if IsValid( trackEnt ) then
        local p = trackEnt:GetPos()
        return Vector( p.x, p.y, p.z + TARGET_Z_OFFS )
    end
    -- Fallback: static vector supplied by FireNikita
    if fallback then return fallback end
    return nil
end

function ENT:Initialize()
    self:SetModel( "models/weapons/w_missile_launch.mdl" )
    self:SetModelScale( 7, 0 )
    self:SetMoveType( MOVETYPE_NOCLIP )
    self:SetSolid( SOLID_NONE )
    self:SetCollisionGroup( COLLISION_GROUP_PROJECTILE )

    self.Destroyed    = false
    self.EngineActive = false
    self.SpawnTime    = CurTime()
    self.HealthVal    = 50
    self.Damage       = 0
    self.Radius       = 0
    self._nextDebug   = 0

    -- TrackEnt and FallbackTarget are set by FireNikita AFTER Spawn()+Activate().
    -- Do NOT touch them here.

    -- Launch nudge
    self:SetAbsVelocity( self:GetForward() * 80 )

    local selfRef = self
    timer.Simple( ENGINE_DELAY, function()
        if not IsValid( selfRef ) or selfRef.Destroyed then return end
        selfRef.Damage = math.random( 2500, 4500 )
        selfRef.Radius = math.random( 700,  1024 )
        selfRef.EngineActive = true
        print( "[NikitaDBG] Engine ACTIVE | homing=" .. tostring( IsValid( selfRef.TrackEnt ) )
            .. " target=" .. tostring( selfRef.TrackEnt ) )
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

    -- Resolve aim position from plain Lua field (reliable server-side)
    local aimPos = GetAimPos( self.TrackEnt, self.FallbackTarget )

    local currentDir = self:GetForward()
    local moveDir

    if aimPos then
        -- Proximity detonation
        if ( self:GetPos() - aimPos ):LengthSqr() < PROX_RADIUS * PROX_RADIUS then
            self:MissileDoExplosion() ; return true
        end

        local desiredDir = ( aimPos - self:GetPos() ):GetNormalized()
        moveDir = LerpVector( FrameTime() * TURN_SPEED, currentDir, desiredDir ):GetNormalized()
    else
        moveDir = currentDir
    end

    self:SetAngles( moveDir:Angle() )
    self:SetAbsVelocity( moveDir * CRUISE_SPEED )

    -- Hull collision sweep ahead
    local stepDist = CRUISE_SPEED * FrameTime() + 16
    local tr = util.TraceHull({
        start  = self:GetPos(),
        endpos = self:GetPos() + moveDir * stepDist,
        mins   = HULL_MINS,
        maxs   = HULL_MAXS,
        mask   = MASK_SHOT,
        filter = { self, IsValid( self.NikitaOwner ) and self.NikitaOwner or self },
    })
    if tr.Hit then
        if tr.HitWorld then
            self:MissileDoExplosion() ; return true
        end
        if IsValid( tr.Entity ) and tr.Entity ~= self.NikitaOwner then
            self:MissileDoExplosion() ; return true
        end
    end

    -- Debug ticker
    if CurTime() > self._nextDebug then
        self._nextDebug = CurTime() + 0.5
        print( string.format(
            "[NikitaDBG] homing=%s spd=%.0f ang=%s",
            tostring( IsValid( self.TrackEnt ) ),
            self:GetAbsVelocity():Length(),
            tostring( self:GetAngles() )
        ))
    end

    return true
end

function ENT:Touch( ent )
    if self.Destroyed then return end
    if CurTime() - self.SpawnTime < 0.3 then return end
    if ent == self.NikitaOwner then return end
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
    local owner = IsValid( self.NikitaOwner ) and self.NikitaOwner or self
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
