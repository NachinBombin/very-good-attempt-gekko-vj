

/*
Thanks a lot to tetabonita for the following code.
*/

-- Creates a ragdoll for the given ent, and applies the given force to all of its limbs as though it were shot at forcepos
local function CreateRagdoll( ent, force, forcepos )

	-- We don't necessarily need these paramaters, so default to something if they aren't given
	force = force or Vector( 0, 0, 0 )
	forcepos = forcepos or ent:LocalToWorld( ent:OBBCenter() )

	-- Get  the model and make sure it's a ragdoll
	local model = ent:GetModel()
	if not util.IsValidRagdoll( model ) then return nil end
	
	-- Create the ragdoll
	local ragdoll = ents.Create( "prop_ragdoll" )
	
	ragdoll:SetModel( model )
	ragdoll:SetPos( ent:GetPos() )
	ragdoll:SetAngles( ent:GetAngles() )
	ragdoll:Spawn()
	
	-- It didn't work, give up
	if not ragdoll:IsValid() then return nil end
	
	-- Change the collision group to whatever you want
	ragdoll:SetCollisionGroup( COLLISION_GROUP_INTERACTIVE_DEBRIS )

	-- We add the velocity of the ent to each of the bones
	local entvel
	local entphys = ent:GetPhysicsObject()
	if entphys:IsValid() then
		entvel = entphys:GetVelocity()
	else
		entvel = ent:GetVelocity()
	end

	-- Setup the bones
	for i=1, ragdoll:GetPhysicsObjectCount() do -- There should be less than 128 bones for any ragdoll
	
		-- This is the physics object of one of the ragdoll's bones
		local bone = ragdoll:GetPhysicsObjectNum( i )
		
		if IsValid( bone ) then
		
			-- This gets the position and angles of the entity bone corresponding to the above physics bone
			local bonepos, boneang = ent:GetBonePosition( ragdoll:TranslatePhysBoneToBone( i ) )
	
			-- All we need to do is set the bones position and angle
			bone:SetPos( bonepos )
			bone:SetAngles( boneang )
			
			-- Apply the correct force to each bone
			bone:ApplyForceOffset( force, forcepos )
			bone:AddVelocity( entvel )
			
		end

	end
	
	ragdoll:Fire( "FadeAndRemove", "", 30 )
	
	-- Inherit everything we can from the entity
	ragdoll:SetSkin( ent:GetSkin() )
	ragdoll:SetColor( ent:GetColor() )
	ragdoll:SetMaterial( ent:GetMaterial() )
	if ent:IsOnFire() then ragdoll:Ignite( math.Rand( 8, 10 ), 0 ) end
	
	return ragdoll
	
end


-- This function appears to kill the entity, but without creating a ragdoll
local function FakeDeath( ent, attacker, inflictor )

	-- Force call a bunch of gamemode hooks (probably bad, oh well)
	
	if ent:IsNPC() then
	
		gamemode.Call( "OnNPCKilled", ent, attacker, inflictor )
		ent:Remove()
		
		return
		
	end
		
	if ent:IsPlayer() then
	
		/*if ent == attacker then
			attacker:AddFrags( -1 )
		else
			attacker:AddFrags( 1 )
		end*/

		gamemode.Call( "PlayerDeath", ent, inflictor, attacker )
		
		-- This still gives a suicide message, even though it's supposed to be 'silent'.
		-- Instead of finding a better way to do this, I'm just going to ignore that fact and blame garry. :D
		ent:KillSilent()
		
	end
	
end

function KillAndLeaveUsableRagdoll(entity, direction, position, attacker, inflictor)
	CreateRagdoll( entity, direction, position )
	FakeDeath( entity, attacker, inflictor )
end

-- This console command will remove and ragdoll whatever entity you are looking at and send it flying as if it were shot.
local function TestRagdoll( plr, cmd, args )

	local tr = util.TraceLine( util.GetPlayerTrace( plr ) )
	
	if tr.HitNonWorld then 
		CreateRagdoll( tr.Entity, tr.Normal * 1000, tr.HitPos )
		FakeDeath( tr.Entity, plr, plr:GetActiveWeapon() )
	end
	
end

--concommand.Add( "TestRagdoll", TestRagdoll )