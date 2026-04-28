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

-- ============================================================
--  JUMP STATE CONSTANTS  (mirror shared.lua)
-- ============================================================
JUMP_NONE    = 0
JUMP_RISING  = 1
JUMP_FALLING = 2
JUMP_LAND    = 3