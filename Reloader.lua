local Reloader = {}
local Log = require "Frame.Log"

local logMsgList = {}
local function LoadFileScript(name)
	if package.preload and package.preload[name] then
		return package.preload[name]()
	elseif next(package.loaders) then
		local err = ""
		for _, func in ipairs(package.loaders) do
			local script = func(name)
			if type(script) == "function" then
				return script, nil
			else
				err = err..script
			end
		end
		return nil, err
	end
end

local function LoadStringScript(src)
	local script, err = loadstring(src)
	if not script then return nil, err end
	return script, nil
end

local function LoadStringToEnv(name, env)
	local script, err = LoadStringScript(name)
	if not script then return nil, err end
	setfenv(script, env)
	local status, result = pcall(script)
	if status ~= true then return nil, result end
	return result, nil
end

local function LoadToEnv(name, env)
	--加载并编译新的脚本内容
	local script, err = LoadFileScript(name)
	if script then
		setfenv(script, env)
		--执行新脚本失败
		local status, result = pcall(script)
		if status ~= true then
			return nil, result
		end
		return result, nil
	else
		return nil, err
	end
end

--判断两个变量是否兼容
local function CheckIsCompatable(old, new)
	if old == nil or new == nil then return true end
	if type(old) == type(new) then return true end
	if type(old) == "number" and type(new) ~= "table" and type(new) ~= "function" then return true end
	if type(old) ~= "function" and type(old) ~= "table" and type(new) =="number" then return true end
	return false
end
--遍历一个table
local TraversalTable, TraversalFunction
local function TraversalByValue(v, visitedData, ignoredVariant)
	if type(v) == "table" then
		TraversalTable(v, visitedData, ignoredVariant)
	elseif type(v) == "function" then
		TraversalFunction(v, visitedData, ignoredVariant)
	end	
end
local function _TraversalTable(t, visitedData, ignoredVariant)
	if ignoredVariant[t] then return end
	if visitedData[t] then return end
	visitedData[t] = true
	if not t.__NeedReload then return end
	for key, value in pairs(t) do
		TraversalByValue(value, visitedData, ignoredVariant)
	end
end
local function _TraversalFunction(f, visitedData, ignoredVariant)
	if ignoredVariant[t] then return end
	if visitedData[f] then return end
	visitedData[f] = true
	for i = 1, math.huge do
		local name, value = debug.getupvalue(f, i)
		if not name then return end
		TraversalByValue(value, visitedData, ignoredVariant)
	end
end
TraversalTable = _TraversalTable
TraversalFunction = _TraversalFunction

--计算和一个table相关的所有upvalue并保存其唯一的id
local CalcUpvalueWithFunction, CalcUpvalueWithTable
local function CalcUpvalueByValue(v, info, ignoredVariant, visitedData)
	if type(v) == "function" then
		CalcUpvalueWithFunction(v, info, ignoredVariant, visitedData)
	elseif type(v) == "table" then
		CalcUpvalueWithTable(v, info, ignoredVariant, visitedData)
	end
end

local function _CalcUpvalueWithTable(t, info, ignoredVariant, visitedData)
	if ignoredVariant[t] then return end
	if not t.__NeedReload then return end
	if visitedData[t] then return end
	visitedData[t] = true
	for key, value in pairs(t) do
		CalcUpvalueByValue(value, info, ignoredVariant, visitedData)
	end
end
local function _CalcUpvalueWithFunction(f, info, ignoredVariant, visitedData)
	if ignoredVariant[t] then return end
	if visitedData[f] then return end
	visitedData[f] = true
	for i = 1, math.huge do
		local name, value = debug.getupvalue(f, i)
		if not name then return end
		local upvalueid = debug.upvalueid(f, i)
		if not info[name] then 
			info[name] = {Cnt = 0, FunctionInfo = {}, UpvalueidInfo = {}, 
			FirstUpvalueid = upvalueid,
			FirstFunction = f,
			FirstFunctionIdx = i,}
		end
		if not info[name].UpvalueidInfo[upvalueid] then
			info[name].Cnt = info[name].Cnt + 1
			info[name].UpvalueidInfo[upvalueid] = true
		end
		info[name].FunctionInfo[f] = {Idx = i, Upvalueid = upvalueid}
		CalcUpvalueByValue(value, info, ignoredVariant, visitedData)
	end
end
CalcUpvalueWithTable = _CalcUpvalueWithTable
CalcUpvalueWithFunction = _CalcUpvalueWithFunction

--计算新旧upvalue之间的转换关系
local CalcUpvalueTransWithTable, CalcUpvalueTransWithFunction
local function _CalcUpvalueTransWithTable(oldUpvalueInfo, ignoredVariant, transDict, 
	newT, visitedData)
	if ignoredVariant[newT] then return end
	if visitedData[newT] then return end
	if not newT.__NeedReload then return end
	visitedData[newT] = true
	for key, value in pairs(newT) do
		if type(value) == "table" then
			CalcUpvalueTransWithTable(oldUpvalueInfo, ignoredVariant, transDict, 
				value, visitedData)
		elseif type(value) == "function" then
			CalcUpvalueTransWithFunction(oldUpvalueInfo, ignoredVariant, transDict,
				value, visitedData)
		end
	end
end
local function _CalcUpvalueTransWithFunction(oldUpvalueInfo, ignoredVariant, transDict, newF, 
	visitedData)
	if visitedData[newF] then return end
	if ignoredVariant[newF] then return end
	visitedData[newF] = true
	for i = 1, math.huge do
		local name, value = debug.getupvalue(newF, i)
		if not name then return end
		local upvalueid = debug.upvalueid(newF, i)
		local oldFInfo = oldUpvalueInfo[name]
		local targetid = nil
		local targetFunction = nil
		local targetFunctionIdx = nil
		if oldFInfo then
			if oldFInfo.Cnt == 1 then
				targetid = oldFInfo.FirstUpvalueid
				targetFunction = oldFInfo.FirstFunction
				targetFunctionIdx = oldFInfo.FirstFunctionIdx
			else
				if oldF then
					if oldFInfo.FunctionInfo[oldF] then
						targetid = oldFInfo.FunctionInfo[oldF].Upvalueid
						targetFunction = oldFInfo.FirstFunction
						targetFunctionIdx = oldFInfo.FirstFunctionIdx
					end
				end
			end
		else
			--一个全新的名字,产生一个新的upvalueid就好了
			targetid = true
			oldFInfo = {FunctionInfo = {}}
		end
		if targetid then
			transDict[upvalueid] = {TargetFunction = targetFunction, 
									TargetFunctionIdx = targetFunctionIdx,
									FunctionInfo = oldFInfo.FunctionInfo}
		end
		if type(value) == "table" then
			CalcUpvalueTransWithTable(oldUpvalueInfo, ignoredVariant, transDict, 
				value, visitedData)
		elseif type(value) == "function" then
			CalcUpvalueTransWithFunction(oldUpvalueInfo, ignoredVariant, transDict,
				value, visitedData)
		end
	end
end
CalcUpvalueTransWithTable = _CalcUpvalueTransWithTable
CalcUpvalueTransWithFunction = _CalcUpvalueTransWithFunction

local UpdateTable, UpdateFunction
local function _UpdateFunction(oldF, newF, prefix, replaceData, visitedData, transDict, functionReplaceDict, ignoredVariant, oldG, newEnv, depth)
	if ignoredVariant[newF] then return end
	if visitedData[newF] then return end
	visitedData[newF] = true
	--设置新函数的env
	if getfenv(newF) == newEnv then
		setfenv(newF, oldG)
	end
	if oldF then 
		functionReplaceDict[oldF] = newF
		--如果能找到以前的函数,那么还是用以前函数的env
		setfenv(newF, getfenv(oldF)) 
	end
	for i = 1, math.huge do
		local name, value = debug.getupvalue(newF, i)
		if not name then return end
		local transinfo = transDict[debug.upvalueid(newF, i)]
		if not transinfo then
			table.insert(logMsgList, prefix.." can not find the match upvalue "..name)
			return
		end
		local oldValue = nil
		local canreload = true
		if oldF and transinfo.FunctionInfo[oldF] then
			canreload, oldValue = debug.getupvalue(oldF, transinfo.FunctionInfo[oldF].Idx)
			if not CheckIsCompatable(oldValue, value) then
				table.insert(logMsgList, prefix.." upvalue type not match "..name.." old:"..tostring(oldValue).." new:"..tostring(value))
				canreload = false
			end
		end
		if canreload then
			if transinfo.TargetFunction then
				debug.upvaluejoin(newF, i, transinfo.TargetFunction, transinfo.TargetFunctionIdx)
			end
			if type(value) == "function" then
				UpdateFunction(oldValue, value, prefix, replaceData, visitedData, transDict, functionReplaceDict, ignoredVariant, oldG, newEnv, depth + 1)
			elseif type(value) == "table" then
				UpdateTable(oldValue or {}, value, prefix, replaceData, visitedData, transDict, functionReplaceDict, ignoredVariant, oldG, newEnv, depth + 1)
			end
		end
	end
end

local function _UpdateTable(oldTable, newTable, prefix, replaceData, visitedData, transDict, functionReplaceDict, ignoredVariant, oldG, newEnv, depth)
	if ignoredVariant[newTable] then return end
	if depth > 1 and not replaceData and not newTable.__NeedReload then return end
	if visitedData[newTable] then return end
	visitedData[newTable] = true
	for key, value in pairs(newTable) do
		local old = oldTable[key]
		if old == nil then
			if type(value) == "table" then
				UpdateTable({}, value, prefix, replaceData, visitedData, transDict, functionReplaceDict, ignoredVariant, oldG, newEnv, depth + 1)
			elseif type(value) == "function" then
				UpdateFunction(nil, value, prefix, replaceData, visitedData, transDict, functionReplaceDict, ignoredVariant, oldG, newEnv, depth + 1)
			end
			oldTable[key] = value
		elseif not CheckIsCompatable(old, value) then
			table.insert(logMsgList, prefix.." value type not match, key "..key.." old:"..tostring(old).." new:"..tostring(value))
		elseif type(value) == "table" then
			UpdateTable(old, value, prefix, replaceData, visitedData, transDict, functionReplaceDict, ignoredVariant, oldG, newEnv, depth + 1)
		elseif type(value) == "function" then
			UpdateFunction(old, value, prefix, replaceData, visitedData, transDict, functionReplaceDict, ignoredVariant, oldG, newEnv, depth + 1)
			oldTable[key] = value
		else
			if replaceData then
				oldTable[key] = value
			end
		end
	end
end
UpdateTable = _UpdateTable
UpdateFunction = _UpdateFunction

local UpdateFunctionForSimpleReload, UpdateTableForSimpleReload
local function UpdateValueForSimpleReload(value, newEnv, oldG, flagData)
	if type(value) == "table" then
		UpdateTableForSimpleReload(value, newEnv, oldG, flagData)
	elseif type(value) == "function" then
		UpdateFunctionForSimpleReload(value, newEnv, oldG, flagData)
	end
end
local function _UpdateTableForSimpleReload(newTable, newEnv, oldG, flagData)
	if not newTable.__NeedReload then return end
	if flagData[newTable] then return end
	flagData[newTable] = 1
	for key, value in pairs(newTable) do
		UpdateValueForSimpleReload(value, newEnv, oldG, flagData)
	end
end
local function _UpdateFunctionForSimpleReload(func, newEnv, oldG, flagData)
	if flagData[func] then return end
	flagData[func] = 1
	if getfenv(func) == newEnv then
		setfenv(func, oldG)
	end
	for i = 1, math.huge do
		local name, value = debug.getupvalue(func, i)
		if not name then return end
		UpdateValueForSimpleReload(value, newEnv, oldG, flagData)
	end
end
UpdateFunctionForSimpleReload = _UpdateFunctionForSimpleReload
UpdateTableForSimpleReload = _UpdateTableForSimpleReload

local function DoReload(oldEnv, newEnv, oldTable, newTable, replaceData, prefix, functionReplaceDict, oldG, firstIgnored, isSimpleReload)
	if isSimpleReload  and not replaceData then
		local flagData = {}
		for key, value in pairs(newEnv) do
			if type(value) == "function" and oldEnv[key] 
				and type(oldEnv[key]) == "function" then
				functionReplaceDict[oldEnv[key]] = value
			end
			UpdateValueForSimpleReload(value, newEnv, oldG, flagData)
			oldEnv[key] = value
		end
		if type(oldTable) == "table" and type(newTable) == "table" then
			for key, value in pairs(newTable) do
				if type(value) == "function" and oldTable[key]
					and type(oldTable[key]) == "function" then
					functionReplaceDict[oldTable[key]] = value
				end
				UpdateValueForSimpleReload(value, newEnv, oldG, flagData)
				oldTable[key] = value
			end
		end
		return
	end
	local oldVisitedTable = {}
	local newVisitedTable = {} 
	local ignoredVariant = {}
	local oldUpvalueInfo = {}
	for key, _ in pairs(firstIgnored) do
		ignoredVariant[key] = true
	end
	--最开始先遍历一次oldTable和newTable,把两个table中相同的变量设置为ignore
	--因为可能会require同样的东西,或者引用了其他模块中的一个函数
	--oldtable只遍历在newTable中出现的东西
	for key, value in pairs(oldEnv) do
		if newEnv[key] ~= nil then
			TraversalByValue(value, oldVisitedTable, ignoredVariant)
		end
	end
	if type(oldTable) == "table" then
		for key, value in pairs(oldTable) do
			TraversalByValue(value, oldVisitedTable, ignoredVariant)
		end
	end
	for _, value in pairs(newEnv) do
		TraversalByValue(value, newVisitedTable, ignoredVariant)
	end
	if type(newTable) == "table" then
		for _, value in pairs(newTable) do
			TraversalByValue(value, newVisitedTable, ignoredVariant)
		end
	end
	--计算newTable和oldTable中互相重合的变量,这些变量并不需要更新
	for key, value in pairs(newVisitedTable) do
		if oldVisitedTable[key] ~= nil then
			ignoredVariant[key] = true
		end
	end

	--oldtable会比较特殊一点,它只需要记录在newtable中存在的function或者key
	local flagData = {}
	if type(oldTable) == "table" then
		for key, value in pairs(oldTable) do
			CalcUpvalueByValue(value, oldUpvalueInfo, ignoredVariant, flagData)
		end
	end
	for key, value in pairs(oldEnv) do
		if newEnv[key] ~= nil then
			CalcUpvalueByValue(value, oldUpvalueInfo, ignoredVariant, flagData)
		end
	end
	--计算新旧upvalueid之间的转换关系
	local newUpvalueidToOldUpvalueid = {}
	flagData = {}
	for _, value in pairs(newEnv) do
		if type(value) == "table" then
			CalcUpvalueTransWithTable(oldUpvalueInfo, ignoredVariant, newUpvalueidToOldUpvalueid,
				value, flagData)
		elseif type(value) == "function" then
			CalcUpvalueTransWithFunction(oldUpvalueInfo, ignoredVariant, newUpvalueidToOldUpvalueid,
				value, flagData)
		end
	end
	if type(newTable) == "table" then
		for _, value in pairs(newTable) do
			if type(value) == "table" then
				CalcUpvalueTransWithTable(oldUpvalueInfo, ignoredVariant, newUpvalueidToOldUpvalueid,
					value, flagData)
			elseif type(value) == "function" then
				CalcUpvalueTransWithFunction(oldUpvalueInfo, ignoredVariant, newUpvalueidToOldUpvalueid,
					value, flagData)
			end
		end
	end
	--开始执行实际的更新工作了
	flagData = {}
	if type(oldTable) == "table" then
		UpdateTable(oldTable, newTable, prefix, replaceData, flagData, newUpvalueidToOldUpvalueid, functionReplaceDict, ignoredVariant, oldG, newEnv, 1)
	end
	UpdateTable(oldEnv, newEnv, prefix, replaceData, flagData, newUpvalueidToOldUpvalueid, functionReplaceDict, ignoredVariant, oldG, newEnv, 1)
end

local _IgnoreModules = {
	"^.*Reloader$",
	"Frame.UEStruct",
	"table",
	"string",
	"coroutine",
	"debug",
	"libtdrlua",
	"os",
	"io",
	"_G",
	"socket.*",
	"package.*",
	"math",
	".*dkjson$",
	"ThirdParty.*",
}

local function CheckNameInIgnoreModules(name)
	for _, p in ipairs(_IgnoreModules) do
		if string.match(name, p) then return true end
	end
end

local envGlobal = {}
local functionReplaceDict = {}
function Reloader.Begin()
	logMsgList = {}
	functionReplaceDict = {}
	--在module的顶层,不能使用setmetatable,setfenv等有副作用的函数
	envGlobal = {}
	setmetatable(envGlobal, {__index = _G})
	envGlobal["setmetatable"] = false
	envGlobal["setfenv"] = false
end

function Reloader.DoReloadForRequire(name, useString, isSimpleReload)
	if CheckNameInIgnoreModules(name) then
		return
	end
	if not package.loaded[name] then return end
	local env = {}
	setmetatable(env, {__index = envGlobal})
	local result, msg
	if useString then
		result, msg = LoadStringToEnv(useString, env)
	else
		result, msg = LoadToEnv(name, env)
	end
	--取消掉env的metatable
	setmetatable(env, nil)
	local replaceData = env.__ReloadAll or false
	if msg then
		table.insert(logMsgList, msg)
	else
		DoReload(_G, env, package.loaded[name], result, 
			replaceData, name, functionReplaceDict, 
			package.loaded._G, {}, isSimpleReload)
	end
end

function Reloader.DoReloadForEntity(name, scriptPath, entityEnv, useString, isSimpleReload)
	local env = {}
	setmetatable(env, {__index = entityEnv})
	entityEnv["setmetatable"] = false
	entityEnv["setfenv"] = false
	--scriptPath = string.gsub(scriptPath, "/", ".")
	local result, msg
	if useString then
		result, msg = LoadStringToEnv(useString, env)
	else
		result, msg = LoadToEnv(scriptPath, env)
	end
	setmetatable(env, nil)
	entityEnv["setmetatable"] = setmetatable
	entityEnv["setfenv"] = setfenv
	local firstIgnored = {
			[entityEnv._Scene] = true,
			[entityEnv._Global] = true,
			[entityEnv._TriggerEvent] = true,
	}
	if msg then
		table.insert(logMsgList, msg)
	else
		local oldResult = true
		if name then oldResult = entityEnv[name] end
		DoReload(entityEnv, env, oldResult, result, 
			false, scriptPath, functionReplaceDict, 
			entityEnv, firstIgnored, isSimpleReload)
	end
end

function Reloader.End()
	--最后执行一次遍历,替换外面的一些旧的函数
	local visitedData = {}
	local q = {_G, }
	local nowLen = 1
	while nowLen >= 1 do
		local m = q[nowLen]
		q[nowLen] = nil
		if not visitedData[m] then
			visitedData[m] = true
			if type(m) == "table" then
				for key, value in pairs(m) do
					table.insert(q, value)
					if type(value) == "function" and functionReplaceDict[value] then
						m[key] = functionReplaceDict[value]
					end
				end
				local mt = getmetatable(m)
				if mt then
					table.insert(q, mt)
				end
			elseif type(m) == "function" then
				for i = 1, math.huge do
					local name, value = debug.getupvalue(m, i)
					if not name then break end
					table.insert(q, value)
					if type(value) == "function" and functionReplaceDict[value] then
						debug.setupvalue(m, i, functionReplaceDict[value])
					end
				end
			elseif type(m) == "userdata" then
				local mt = getmetatable(m)
				if mt then
					table.insert(q, mt)
				end
			end
		end
		nowLen = #q
	end
	return logMsgList
end

local function TraversalEntityForReload(entityObject, name, useString, isSimpleReload)
	local env = entityObject:GetDataCache()
	local entityScriptPath = env.__ScriptFile
	if entityScriptPath then
		if entityScriptPath == name or name == nil then
			Reloader.DoReloadForEntity(nil, entityScriptPath, env, useString, isSimpleReload)
		end
	end
	if env.__CompScriptFile then
		for k, v in pairs(env.__CompScriptFile) do
			if v == name or name == nil then
				Reloader.DoReloadForEntity(k, v, env, useString, isSimpleReload)
			end
		end
	end
	for key, v in pairs(entityObject._EntityChildList) do
		TraversalEntityForReload(v, name, useString, isSimpleReload)
	end
end

function Reloader.MyReload(name, useString, isSimpleReload)
	Reloader.Begin()
	if name then
		Reloader.DoReloadForRequire(name, useString, isSimpleReload)
	else
		for key, _ in pairs(package.loaded) do
			Reloader.DoReloadForRequire(key, nil, isSimpleReload)
		end
		local DataCacheService = require "Frame.DataCacheService"
		local entityService = DataCacheService.GetEntityService()
		for _, entityObject in pairs(entityService._EntityRootMap) do
			TraversalEntityForReload(entityObject, nil, nil, isSimpleReload)
		end
	end
	Reloader.End()
	--Log.Warn(DumpTable(logMsgList))
	return logMsgList
end
function Reloader.MyReloadEntity(name, useString, isSimpleReload)
	Reloader.Begin()
	local DataCacheService = require "Frame.DataCacheService"
	local entityService = DataCacheService.GetEntityService()
	for _, entityObject in pairs(entityService._EntityRootMap) do
		TraversalEntityForReload(entityObject, name, useString, isSimpleReload)
	end
	Reloader.End()
	return logMsgList
end
return Reloader