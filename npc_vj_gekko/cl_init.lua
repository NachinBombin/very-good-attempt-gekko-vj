include("shared.lua")
include("elastic_cl.lua")
include("muzzleflash_system.lua")
include("bullet_impact_system.lua")
-- ============================================================
--  HELPERS
-- ============================================================
local function SetBoneAng(ent, name, ang)
    local id = ent:LookupBone(name)
    if id and id >= 0 then ent:ManipulateBoneAngles(id, ang, false) end
end

local function SetBonePos(ent, name, pos)
    local id = ent:LookupBone(name)
    if id and id >= 0 then ent:ManipulateBonePosition(id, pos, false) end
end
