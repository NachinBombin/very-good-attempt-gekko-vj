-- Standalone ragdoll utility for bombin_smacker. No dependency on hydrasasasas.

local function CreateRagdoll( ent, force, forcepos )
    force = force or Vector( 0, 0, 0 )
    forcepos = forcepos or ent:LocalToWorld( ent:OBBCenter() )

    local model = ent:GetModel()
    if not util.IsValidRagdoll( model ) then return nil end

    local ragdoll = ents.Create( "prop_ragdoll" )
    ragdoll:SetModel( model )
    ragdoll:SetPos( ent:GetPos() )
    ragdoll:SetAngles( ent:GetAngles() )
    ragdoll:Spawn()

    if not ragdoll:IsValid() then return nil end

    ragdoll:SetCollisionGroup( COLLISION_GROUP_INTERACTIVE_DEBRIS )

    local entvel
    local entphys = ent:GetPhysicsObject()
    if entphys:IsValid() then
        entvel = entphys:GetVelocity()
    else
        entvel = ent:GetVelocity()
    end

    for i = 1, ragdoll:GetPhysicsObjectCount() do
        local bone = ragdoll:GetPhysicsObjectNum( i )
        if IsValid( bone ) then
            local bonepos, boneang = ent:GetBonePosition( ragdoll:TranslatePhysBoneToBone( i ) )
            bone:SetPos( bonepos )
            bone:SetAngles( boneang )
            bone:ApplyForceOffset( force, forcepos )
            bone:AddVelocity( entvel )
        end
    end

    ragdoll:Fire( "FadeAndRemove", "", 30 )
    ragdoll:SetSkin( ent:GetSkin() )
    ragdoll:SetColor( ent:GetColor() )
    ragdoll:SetMaterial( ent:GetMaterial() )
    if ent:IsOnFire() then ragdoll:Ignite( math.Rand( 8, 10 ), 0 ) end

    return ragdoll
end

local function FakeDeath( ent, attacker, inflictor )
    if ent:IsNPC() then
        gamemode.Call( "OnNPCKilled", ent, attacker, inflictor )
        ent:Remove()
        return
    end
    if ent:IsPlayer() then
        gamemode.Call( "PlayerDeath", ent, inflictor, attacker )
        ent:KillSilent()
    end
end

function Bombin_KillAndLeaveUsableRagdoll( entity, direction, position, attacker, inflictor )
    CreateRagdoll( entity, direction, position )
    FakeDeath( entity, attacker, inflictor )
end