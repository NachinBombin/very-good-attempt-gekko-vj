if CLIENT then return end

local TARGET = "npc_helicopter"

-- Damage types helicopters already understand well
local ACCEPTED = {
    [DMG_BLAST] = true,
    [DMG_AIRBOAT] = true
}

-- scale factor for non-accepted damage
local TRANSLATION_SCALE = 0.02  -- 2% of original damage

hook.Add("EntityTakeDamage","HelicopterUniversalDamageTranslator",function(ent,dmg)

    if not IsValid(ent) then return end
    if ent:GetClass() ~= TARGET then return end

    if dmg._heliConverted then return end

    local dtype = dmg:GetDamageType()

    -- if already acceptable damage, do nothing
    if ACCEPTED[dtype] then return end

    local new = DamageInfo()

    new:SetAttacker(IsValid(dmg:GetAttacker()) and dmg:GetAttacker() or game.GetWorld())
    new:SetInflictor(IsValid(dmg:GetInflictor()) and dmg:GetInflictor() or game.GetWorld())

    new:SetDamage(dmg:GetDamage() * TRANSLATION_SCALE)
    new:SetDamageType(DMG_BLAST)

    new:SetDamageForce(dmg:GetDamageForce())
    new:SetDamagePosition(dmg:GetDamagePosition())

    new._heliConverted = true

    ent:TakeDamageInfo(new)

    -- prevent original damage from applying
    dmg:SetDamage(0)

end)