local lfs = require('lfs')
local pp = require('preprocess')
local dp = require('dumbParser')
local function read(a)
	local h = io.open(a,'rb');
	local c = h:read("*a");
	h:close();
	return c
end
local function write(a,b)
	local h = io.open(a,'wb');
	h:write(b);
	h:close();
end
local function recurse(path,todo,cext)
	local todo=todo or {}
	if lfs.attributes(path)==nil then return todo end
	for file in lfs.dir(path) do
		if file~="." and file~=".." then
			local attr = lfs.attributes(path.."/"..file);
			if attr.mode=="file" then
				if (cext and cext(file,attr)) or (cext==nil and file:sub(-4)==".lua") then
					table.insert(todo,{true,path.."/"..file});
				end
			elseif attr.mode=="directory" then
				table.insert(todo,{false,path..'/'..file});
				recurse(path.."/"..file,todo,cext);
			end
		end
	end
	return todo
end
local function recurse_rmdir(dir)
	local todo = recurse(dir);
	for i,v in pairs(todo) do
		if v[1] then
			os.remove(v[2]);
		end
	end
	for i,v in pairs(todo) do
		if not v[1] then
			recurse_rmdir(v[2]);
		end
	end
	lfs.rmdir(dir);
end
local function extend(a,b)
	local n = {}
	for i,v in pairs(a) do n[i]=v end
	for i,v in pairs(b) do n[i]=v end
	return n
end
local function split(a,b)
	local n = {}
	for m in (a..b):gmatch("(.-)"..b) do
		table.insert(n,m)
	end
	return n
end
local function toValue(n)
	if tonumber(n) then
		return tonumber(n)
	end
	if n=="nil" then return nil end
	if n=="true" then return true end
	if n=="false" then return false end
	return n
end
local args = {}
for i,v in pairs(({...})) do
	if i~=1 then
		local sp = split(v,'=')
		if #sp==2 then
			args[sp[1]]=toValue(sp[2]);
		end
	end
end
if (...)=="build" then
	lfs.mkdir("build")
	lfs.mkdir("temp")
	local todo = recurse("src",nil,function(f)
		return true
	end)
	for i,v in pairs(todo) do 
		if not v[1] then
			lfs.mkdir('build/'..v[2]:sub(5))
			lfs.mkdir('temp/'..v[2]:sub(5))
		end
	end
	lfs.chdir("src");
	for i,v in pairs(todo) do
		if v[1] then
			local info,err = pp.processFile(extend({
				pathIn=v[2]:sub(5),
				pathOut='../build/'..v[2]:sub(5),
				pathMeta='../temp/'..v[2]:sub(5),
				validate=v[2]:sub(-4)==".lua"
			},args))
			if not info then
				lfs.chdir("..");
				recurse_rmdir("build");
				if not args["stemp"] then
					recurse_rmdir("temp");
				end
				error(err);
				break
			end
			if info.hasPreprocessorCode then
				print(v[2],'l:'..info.linesOfCode,'b:'..info.processedByteCount)
				for i,v in pairs(info.insertedFiles) do
					print("\tinsert ",v);
				end
			end
			if v[2]:sub(-4)==".lua" then
				local ast = dp.parse(read('../build/'..v[2]:sub(5)));
				dp.optimize(ast);
				write('../build/'..v[2]:sub(5),dp.toLua(ast,true));
			end
		end
	end
	lfs.chdir("..");
	if not args["stemp"] then
		recurse_rmdir("temp");
	end
elseif (...)=="bundle" then
	local found = false
	for f in lfs.dir(".") do
		if f=="build" then
			found=true;break
		end
	end
	if not found then
		print('You have to use `lua build.lua build` first.')
		os.exit(1)
	end
	lfs.chdir("build");
	os.execute("lua ../pack.lua main.lua ../bundle.lua");
	lfs.chdir("..");
elseif (...)=="clean" then
	os.remove("./bundle.lua");
	recurse_rmdir("build");
	recurse_rmdir("temp");
end


