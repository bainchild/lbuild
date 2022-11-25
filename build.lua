local build_file_handlers = {}
do
	local s,r = pcall(require,'lbuild.handlers')
	if s then
		build_file_handlers=r
	elseif not r:match('.*module \'lbuild.handlers\' not found:\n.*') then
		error(r)
	end
end
local pp = require('preprocess')
local dp = require('dumbParser')
local lfs = require('lfs')
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
	local todo = recurse(dir,nil,function() return true end);
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
local function copy(file,to)
	return write(to,read(file))
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
local function unluau(source)
	source=source:gsub(':%s+[%->%w<>]+(=?)','') -- abc: type
	source=source:gsub(':%s+%b{}','') -- abc: {}
	source=source:gsub(':%s+%([%w<>,%s]*%)%s+%->%s%([%w<>,%s]*%)','') -- abc: ()->()
	source=source:gsub(':%s+%([%w<>,%s]*%)','') -- abc: ()
	source=source:gsub('export%s+type%s+[%w<>]+%s+=%s+%w[^\n]*\n','') -- export type abc = AAA
	source=source:gsub('export%s+type%s+[%w<>]+%s+=%s+{?[^}]+}[^\n]*\n','') -- export type abc = {...}
	source=source:gsub('type%s+[%w<>]+%s+=%s+%w[^\n]*\n','') -- type abc = AAA
	source=source:gsub('type%s+[%w<>]+%s+=%s+{?[^}]+}[^\n]*\n','') -- type abc = {...}
	source=source:gsub('(%s+)([+-*/%^.]+)=(%s+)',function(var,op,other) -- a+=1
		return var..'='..var..op..other
	end)
	return source
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
if (...)=="process" then
	recurse_rmdir("proc")
	recurse_rmdir("temp")
	lfs.mkdir("proc")
	lfs.mkdir("temp")
	local todo = recurse("src",nil,function(f)
		return true
	end)
	for i,v in pairs(todo) do 
		if not v[1] then
			lfs.mkdir('proc/'..v[2]:sub(5))
			lfs.mkdir('temp/'..v[2]:sub(5))
		end
	end
	lfs.chdir("src");
	for i,v in pairs(todo) do
		if v[1] then
			if ((v[2]:sub(-4)==".lua" and read(v[2]:sub(5)):sub(1,4)~="\27Lua") or v[2]:sub(-4)~=".lua") then
				if args['unluau'] then write(v[2]:sub(5),unluau(v[2]:sub(5))) end
				local info,err = pp.processFile(extend({
					pathIn=v[2]:sub(5),
					pathOut='../proc/'..v[2]:sub(5),
					pathMeta='../temp/'..v[2]:sub(5),
					validate=v[2]:sub(-4)==".lua"
				},args))
				if not info then
					lfs.chdir("..");
					recurse_rmdir("proc");
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
					local ast = dp.parse(read('../proc/'..v[2]:sub(5)));
					dp.optimize(ast);
					write('../proc/'..v[2]:sub(5),dp.toLua(ast,true));
				end
			else
				copy(v[2]:sub(5),"../proc/"..v[2]:sub(5))
			end
		end
	end
	lfs.chdir("..");
	if not args["stemp"] then
		recurse_rmdir("temp");
	end
elseif (...)=="build" then
	recurse_rmdir("build")
	local dir = 'src'
	for f in lfs.dir(".") do
		if f=="proc" then
			dir=f;break
		end
	end
	lfs.mkdir("build");
	local todo = recurse(dir,nil,function()
		return true
	end)
	for i,v in pairs(todo) do
		if v[1] then
			local spl = split(v[2],"%.");
			local extension = "."..spl[#spl];
			local found = false
			for regex,handler in pairs(build_file_handlers) do
				if extension:match(regex) then
					if handler(v[2],"build/"..table.concat(split(v[2],"/"),'/',2),args) then
						os.remove("build/"..table.concat(split(v[2],"/"),'/',2));
					end
					found=true;
					break
				end
			end
			if not found then
				copy(v[2],"build/"..table.concat(split(v[2],"/"),'/',2))
			end
		else
			lfs.mkdir("build/"..table.concat(split(v[2],"/"),'/',2))
		end
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
	os.remove("bundle.lua");
	lfs.chdir("build");
	os.execute("lua ../pack.lua main.lua ../bundle.lua");
	lfs.chdir("..");
elseif (...)=="clean" then
	os.remove("./bundle.lua");
	recurse_rmdir("build");
	recurse_rmdir("proc");
	recurse_rmdir("temp");
end
