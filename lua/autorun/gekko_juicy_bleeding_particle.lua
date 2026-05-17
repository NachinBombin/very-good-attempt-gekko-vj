-- ============================================================
-- FILE: lua/autorun/gekko_juicy_bleeding_particle.lua
-- PURPOSE: Particle precaching & ConVar registration
-- SCOPE: Shared (Autorun)
-- NOTE: PCF files were copied byte-for-byte from of_simple_bleeding.
--       The internal particle system names inside the PCF binaries are
--       still the ORIGINAL names (of_simple_bleeding_*). The Lua MUST
--       reference those exact names or GMod finds no system and emits nothing.
-- ============================================================

game.AddParticles("particles/gekko_juicy_bleeding.pcf")
game.AddParticles("particles/gekko_juicy_bleeding_darker.pcf")

-- These names MUST match what is stored inside the PCF binaries exactly.
PrecacheParticleSystem("of_simple_bleeding_spray")
PrecacheParticleSystem("of_simple_bleeding_spray_b")
PrecacheParticleSystem("of_simple_bleeding_darker_spray")
PrecacheParticleSystem("of_simple_bleeding_darker_spray_b")

CreateConVar("gekko_juicy_bleeding_enabled",  "1",   {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "")
CreateConVar("gekko_juicy_bleeding_player",   "0",   {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "")
CreateConVar("gekko_juicy_bleeding_maxactive","40",  {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "", 10, 500)
CreateConVar("gekko_juicy_bleeding_cooldown", "0.2", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "", 0, 1)
CreateConVar("gekko_juicy_bleeding_debug",    "0",   {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "")
CreateConVar("gekko_juicy_bleeding_darker",   "0",   {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "")
