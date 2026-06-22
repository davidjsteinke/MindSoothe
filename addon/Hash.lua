-- FNV-1a 32-bit hash for ToxFilter.
-- Identical to the Python implementation in scripts/build-rules.sh; the
-- self-test below catches any divergence at addon load time.

local _, ns = ...

assert(bit and bit.bxor, ns.Const.PREFIX .. "WoW 'bit' library not available")

local bxor = bit.bxor
local string_byte = string.byte

local FNV_OFFSET = 2166136261
local FNV_PRIME  = 16777619
local MOD32      = 4294967296

-- Lua 5.1 numbers are doubles; (2^32 - 1) * 16777619 exceeds 2^53 so a direct
-- multiply silently loses precision. Split-multiply keeps every intermediate
-- product within the 53-bit safe range, then masks to 32 bits.
local function mul32(hash)
    local low  = hash % 65536
    local high = (hash - low) / 65536
    local low_part  = low * FNV_PRIME
    local high_part = (high * FNV_PRIME) % 65536
    return (high_part * 65536 + low_part) % MOD32
end

local function fnv1a(s)
    local hash = FNV_OFFSET
    for i = 1, #s do
        hash = bxor(hash, string_byte(s, i))
        hash = mul32(hash)
    end
    return hash
end

assert(fnv1a("")     == 2166136261, ns.Const.PREFIX .. "FNV1a self-test failed: empty string")
assert(fnv1a("a")    == 3826002220, ns.Const.PREFIX .. "FNV1a self-test failed: 'a'")
assert(fnv1a("test") == 2949673445, ns.Const.PREFIX .. "FNV1a self-test failed: 'test'")

ns.Hash = {
    fnv1a = fnv1a,
    HASH_VERSION = "fnv1a-32",
}
