net.Receive("GekkoAI_Overheat", function()
    local ent        = net.ReadEntity()
    local overheated = net.ReadBool()

    if not IsValid(ent) then return end

    if overheated then
        -- bright orange steam/smoke bursting from the gun barrel
        local attach = ent:GetAttachment(3)
        if attach then
            local e = EffectData()
            e:SetOrigin(attach.Pos)
            e:SetScale(3)
            e:SetMagnitude(8)
            util.Effect("Steam", e)
            util.Effect("WaterSplash", e)
        end

        -- colored dynamic light flash — red-orange heat glow
        local dlight      = DynamicLight(ent:EntIndex())
        if dlight then
            dlight.Pos        = ent:GetPos() + Vector(0, 0, 120)
            dlight.r          = 255
            dlight.g          = 80
            dlight.b          = 0
            dlight.Brightness = 4
            dlight.Size       = 200
            dlight.Decay      = 800
            dlight.DieTime    = CurTime() + 1.5
        end

        surface.PlaySound("ambient/fire/fire_extinguisher1.wav")
    else
        -- small cool-down vent puff
        local attach = ent:GetAttachment(3)
        if attach then
            local e = EffectData()
            e:SetOrigin(attach.Pos)
            e:SetScale(1)
            e:SetMagnitude(2)
            util.Effect("Steam", e)
        end
    end
end)
