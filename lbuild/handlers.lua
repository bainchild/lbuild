local lfs = require('lfs');
lfs.chdir("lbuild/LuaAssemblyTools");
local LAT = require('LAT');
lfs.chdir("../..");
local parser = LAT.Lua51.Parser:new()
local function read(file)
	local handle = assert(io.open(file,'rb'))
	local content = handle:read('*a')
	handle:close()
	return content
end
local function write(file,content)
    local handle = assert(io.open(file,'wb'))
    handle:write(content)
    handle:close()
end
return {
    ["%.lasm"]=function(in_,out,args)
        local file = parser:Parse(read(in_),'@'..tostring(in_))
        if args["LASM_stripdebug"] then
            file:StripDebugInfo()
            file.Main.Name="=?"
        end
        if args["LASM_compileto"] then
            local t = assert(LAT.Lua51.PlatformTypes[args["LASM_compileto"]],"'"..tostring(args["LASM_compileto"]).."' is not a valid type to compile to!")
            for i,v in pairs(t) do
                if i~="Description" then
                    file[i]=v
                end
            end
        end
        local byte = file:Compile();
        if not args["LASM_noverify"] then
            assert(loadstring(byte));
        end
        local op = out:sub(1,-6)..".lua";
        if not args["LASM_overwrite"] then
            op=op:sub(1,-5).."_lasm.lua"
        end
        write(op,byte);
        return true; -- remove the original file
    end;
}