 local matRefract	= Material( "refract_ring" ) 
 local matRefract2 = Material( "effects/strider_bulge_dudv" )
 /*--------------------------------------------------------- 
	this is pretty much super explosion from GMDM.
 ---------------------------------------------------------*/ 
 function EFFECT:Init( data ) 
	self.Entity:SetPos( data:GetOrigin())
 	 
 	self.Refract = 0 
 	 
 	self.Size = 32 
 	 
 	self.Entity:SetRenderBounds( Vector()*-512, Vector()*512 ) 
 	 
 end 
   
   
 /*--------------------------------------------------------- 
    THINK 
    Returning false makes the entity die 
 ---------------------------------------------------------*/ 
 function EFFECT:Think( ) 
   
 	self.Refract = self.Refract + 2.0 * FrameTime() 
 	self.Size = 800 * self.Refract^(0.2) 
 	 
 	if ( self.Refract >= 1 ) then return false end 
 	 
 	return true 
 	 
 end 
   
   
 /*--------------------------------------------------------- 
    Draw the effect 
 ---------------------------------------------------------*/ 
 function EFFECT:Render() 
   
 	local Distance = EyePos():Distance( self.Entity:GetPos() ) 
 	local Pos = self.Entity:GetPos() + (EyePos()-self.Entity:GetPos()):GetNormal() * Distance * (self.Refract^(0.3)) * 0.8 
   
 	matRefract:SetMaterialFloat( "$refractamount", math.sin( self.Refract * math.pi ) * 0.1 ) 
 	render.SetMaterial( matRefract ) 
 	render.UpdateRefractTexture() 
 	render.DrawSprite( Pos, self.Size, self.Size )
	
	matRefract2:SetMaterialFloat( "$refractamount", math.sin( self.Refract * math.pi ) * 0.1 ) 
	render.SetMaterial( matRefract2 ) 
 	render.UpdateRefractTexture() 
 	render.DrawSprite( Pos, 40, 40 ) 
   
 end  
 