@@"build.lua"
@@LOG("info","%s - %s@%s, built on %s",@file,!(build.branch),!(build.hash),!(build.build_date))
local abc = require('bytecode')
local cba = require('lasmgenerated')
assert(abc==cba,'no way')
return abc