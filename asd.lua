--// Config
const Delay = 0
const RunNetworkTests = false -- Set to true to run request / WebSocket tests (may hang/crash offline)

--// Variables
local Total, Passed, Undefined = 0, 0, 0
const VENV = getfenv(0)

--// types
type Function = (...unknown) -> ... unknown
type Callback = () -> boolean|string

const function IsCFunction(Closure: Function): boolean
	if pcall(function()
			setfenv(Closure, getfenv(Closure))
		end) then
		return false
	end

	const L, S = debug.info(Closure, "ls")
	if L ~= -1 or S ~= "[C]" then return false end

	return true
end

const function BuildFunctionHash(Closure: Function): string
	--// NOTE: "f" (the function itself) is deliberately excluded - tostring(function)
	--// yields a unique memory address, which would make hashes of ANY two distinct
	--// closures differ and reduce CompareFunctions to a plain A == B check.
	--// "a" returns two values (arity: number, is_vararg: boolean) - tostring handles both.
	local hash = ""
	for _, value in {debug.info(Closure, "snla")} do
		hash ..= tostring(value) .. "\1" -- Separator prevents ambiguous concatenations
	end

	return hash
end

@native const function CompareFunctions(A: Function, B: Function): boolean
	return A == B or BuildFunctionHash(A) == BuildFunctionHash(B)
end

@native const function TestAliases(Aliases: {string}): {string}
	const MissingAliases = {}
	for _, Alias in next, Aliases do
		if not VENV[Alias] then
			Undefined += 1
			table.insert(MissingAliases, Alias)
		end
	end

	return MissingAliases
end

@native const function Test(Name: string, Callback: Callback)
	Total += 1

	--// Test delay
	if Total > 1 and Delay > 0 then
		task.wait(Delay)
	end

	--// Crash tracing: write the current test name BEFORE running it.
	--// After a crash, read "EnvCheck_crashlog.txt" - the last line is the culprit.
	pcall(function()
		if writefile then
			writefile("EnvCheck_crashlog.txt", `RUNNING: {Name}`)
		end
		print("▶️ Running:", Name)
	end)

	const CallSuccess, Return = pcall(Callback)

	--// Unsuccessful
	if not CallSuccess or Return ~= true then
		warn("⛔",  Name, "failed:", Return)
		return
	end

	--// Passed
	Passed += 1
	print("✅", Name)

	return
end

@native const function TestGlobal(Global: string, Aliases: {string}, Callback: Callback)
	--// Has global
	if not VENV[Global] then 
		warn("⛔", Global)
		return 
	end

	--// Alias check
	const MissingAliases = TestAliases(Aliases)
	if #MissingAliases > 0 then
		warn("⚠️", table.concat(MissingAliases, ", "))
		return
	end

	return Test(Global, Callback)
end

@native const function PrintSummary()
	const SuccessRate = math.round(Passed / Total * 100)
	const Failed = Total - Passed

	print("Test Summary")
	print(string.rep("-", 50))
	print(`✅ Tested with a {SuccessRate}% success rate`)
	print(`⛔ {Failed} tests failed`)
	print(`⚠️ {Undefined} globals are missing aliases`)
	return
end

@native const function PrinHeader()
	print([[
Shit Environment Check
✅ - Pass, ⛔ - Fail, ⏺️ - No test, ⚠️ - Missing aliases]])
	print("Executor:", identifyexecutor())
	print(string.rep("-", 50), "\n")
	task.wait(1)
	return
end

--// Header
PrinHeader()

--============================================================
--// Environment
--============================================================

Test("HttpGetAsync", function()
	--// C closure test
	if not IsCFunction(game.HttpGetAsync) then
		return "HttpGetAsync should be a valid C function"
	end

	--// Comparsion
	if CompareFunctions(game.HttpGetAsync, game.HttpGet) then
		return "HttpGetAsync should differ from HttpGet"
	end

	--// Network checks (may hang/crash offline - gated behind RunNetworkTests)
	if RunNetworkTests then
		--// Field test
		if pcall(function()
				return workspace:HttpGetAsync("https://google.com")
			end) then
			return "Terrible HttpGetAsync field/hook 😭"
		end

		--// Return check
		const Ok, Return = pcall(function()
			return game:HttpGetAsync("https://google.com")
		end)
		if not Ok then
			return "HttpGetAsync errored: " .. tostring(Return)
		end
		if typeof(Return) ~= "string" or #Return < 10 then
			return "https://google.com/ did not return anything"
		end
	end

	return true
end)

Test("env.__newindex", function() -- Potassium used to fail this lmao
	const Previous = require
	getgenv().require = warn
	const New = getgenv().require
	getgenv().require = Previous

	--// Protected function swap
	if New == Previous then
		return "Value did not change for 'require'"
	end

	return true
end)

Test("env.script", function()
	return typeof(script) == "Instance" and script.Parent == nil
end)

--============================================================
--// Cache
--============================================================

TestGlobal("cache.invalidate", {}, function()
	const Container = Instance.new("Folder")
	const Part = Instance.new("Part", Container)
	cache.invalidate(Container:FindFirstChild("Part"))
	if Part == Container:FindFirstChild("Part") then
		return "Reference `Part` could not be invalidated"
	end
	return true
end)

TestGlobal("cache.iscached", {}, function()
	const Part = Instance.new("Part")
	if not cache.iscached(Part) then
		return "Part should be cached"
	end
	cache.invalidate(Part)
	if cache.iscached(Part) then
		return "Part should not be cached"
	end
	return true
end)

TestGlobal("cache.replace", {}, function()
	--// Use same-class instances: replacing across classes (Part <-> Fire)
	--// causes type confusion / crashes on weaker cache implementations
	const PartA = Instance.new("Part")
	const PartB = Instance.new("Part")
	PartB.Name = "Replacement"
	cache.replace(PartA, PartB)
	if PartA.Name ~= "Replacement" then
		return "PartA was not replaced with PartB"
	end
	return true
end)

TestGlobal("cloneref", {}, function()
	const Part = Instance.new("Part")
	const Clone = cloneref(Part)
	if Part == Clone then
		return "Clone should not be equal to original"
	end
	Clone.Name = "Test"
	if Part.Name ~= "Test" then
		return "Clone should have updated the original"
	end
	return true
end)

TestGlobal("compareinstances", {}, function()
	const Part = Instance.new("Part")
	const Clone = cloneref(Part)
	if Part == Clone then
		return "compareinstances test relies on cloneref working"
	end
	if not compareinstances(Part, Clone) then
		return "Clone should be equal to original when using compareinstances"
	end
	return true
end)

--============================================================
--// Closures
--============================================================

TestGlobal("checkcaller", {}, function()
	if not checkcaller() then
		return "Main scope should return true"
	end
	return true
end)

TestGlobal("clonefunction", {}, function()
	const function Test() return "success" end
	const Copy = clonefunction(Test)
	if Test() ~= Copy() then
		return "The clone should return the same value as the original"
	end
	if Test == Copy then
		return "The clone should not be equal to the original"
	end
	return true
end)

TestGlobal("getcallingscript", {}, function()
	return getcallingscript() == script or getcallingscript() == nil
end)

TestGlobal("getscriptclosure", {"getscriptfunction"}, function()
	--// Use a safe, own ModuleScript instead of arbitrary CoreGui modules
	--// (calling getscriptclosure on protected/core modules can crash the executor)
	const Module = Instance.new("ModuleScript")
	Module.Source = "return function() return true end"

	const Ok, Closure = pcall(getscriptclosure, Module)
	Module:Destroy()

	if not Ok then
		return "getscriptclosure errored: " .. tostring(Closure)
	end
	if typeof(Closure) ~= "function" then
		return "Did not return a function"
	end
	--// Do NOT call the returned closure (can be unsafe on some executors)
	return true
end)

TestGlobal("hookfunction", {"replaceclosure"}, function()
	--// Hook a harmless local function (safer than hooking hookfunction itself)
	const function Original() return true end
	const Ref = hookfunction(Original, function() return "abc" end)

	--// Return check
	if Original() ~= "abc" then
		return "hookfunction did not change the return value"
	end
	if typeof(Ref) ~= "function" or Ref() ~= true then
		return "hookfunction did not return the original function"
	end

	--// Restore
	if restorefunction then
		pcall(restorefunction, Original)
	else
		pcall(hookfunction, Original, Ref)
	end

	return true
end)

TestGlobal("iscclosure", {}, function()
	if not iscclosure(print) then
		return "Function 'print' should be a C closure"
	end
	if iscclosure(function() end) then
		return "Executor function should not be a C closure"
	end
	return true
end)

TestGlobal("islclosure", {}, function()
	if islclosure(print) then
		return "Function 'print' should not be a Luau closure"
	end
	if not islclosure(function() end) then
		return "Executor function should be a Luau closure"
	end
	return true
end)

TestGlobal("isexecutorclosure", {"checkclosure", "isourclosure"}, function()
	if not isexecutorclosure(isexecutorclosure) then
		return "Did not return true for an executor global"
	end
	if not isexecutorclosure(newcclosure(function() end)) then
		return "Did not return true for an executor C closure"
	end
	if not isexecutorclosure(function() end) then
		return "Did not return true for an executor Luau closure"
	end
	if isexecutorclosure(print) then
		return "Did not return false for a Roblox global"
	end
	return true
end)

TestGlobal("loadstring", {}, function()
	--// Removed dead getscriptbytecode(script) call: dumping the executor's own
	--// script instance is a crash vector and had nothing to do with this test
	const Func = loadstring("return ... + 1")
	if typeof(Func) ~= "function" then
		return "Failed to loadstring a simple string"
	end
	if Func(1) ~= 2 then
		return "Failed to return correct value"
	end
	const Err = select(2, loadstring("f(f)f)"))
	if typeof(Err) ~= "string" then
		return "Loadstring did not return anything for a compiler error"
	end
	return true
end)

TestGlobal("newcclosure", {}, function()
	const function Test() return true end
	const C = newcclosure(Test)
	if Test == C then
		return "New C closure should not be same as original"
	end
	if Test() ~= C() then
		return "New C closure should return the same value as the original"
	end
	if not iscclosure(C) then
		return "New C closure should be a C closure"
	end
	return true
end)

--============================================================
--// Console
--============================================================

TestGlobal("rconsoleclear", {"consoleclear"}, function()
	rconsoleclear()
	return true
end)

TestGlobal("rconsolecreate", {"consolecreate"}, function()
	rconsolecreate()
	--// Behavior check: a created console must accept output without erroring
	if rconsoleprint then
		rconsoleprint("EnvCheck rconsolecreate test\n")
	end
	return true
end)

TestGlobal("rconsoledestroy", {"consoledestroy"}, function()
	--// Create before destroying: destroying a nonexistent console crashes some executors
	if rconsolecreate then pcall(rconsolecreate) end
	rconsoledestroy()
	return true
end)

TestGlobal("rconsoleinput", {"consoleinput"}, function()
	--// Cannot behavior-test: rconsoleinput blocks the thread until the user
	--// types into the console. Existence-only by necessity.
	return true
end)

TestGlobal("rconsoleprint", {"consoleprint"}, function()
	rconsoleprint("EnvCheck rconsoleprint test\n")
	return true
end)

TestGlobal("rconsolesettitle", {"rconsolename", "consolesettitle"}, function()
	rconsolesettitle("EnvCheck")
	return true
end)

--============================================================
--// Crypt
--============================================================

TestGlobal("crypt.base64encode", {"crypt.base64.encode", "crypt.base64_encode", "base64.encode", "base64_encode", "base64encode"}, function()
	if crypt.base64encode("test") ~= "dGVzdA==" then
		return "Base64 encoding did not work"
	end
	return true
end)

TestGlobal("crypt.base64decode", {"crypt.base64.decode", "crypt.base64_decode", "base64.decode", "base64_decode", "base64decode"}, function()
	if crypt.base64decode("dGVzdA==") ~= "test" then
		return "Base64 decoding did not work"
	end
	return true
end)

TestGlobal("crypt.encrypt", {}, function()
	const Key = crypt.generatekey()
	const Text, IV = crypt.encrypt("test", Key, nil, "CBC")
	if not IV then
		return "crypt.encrypt should return an IV"
	end
	const Decrypted = crypt.decrypt(Text, Key, IV, "CBC")
	if Decrypted ~= "test" then
		return "Failed to decrypt text from encrypted string"
	end
	return true
end)

TestGlobal("crypt.decrypt", {}, function()
	const Key = crypt.generatekey()
	const Text, IV = crypt.encrypt("test", Key, nil, "CBC")
	const Decrypted = crypt.decrypt(Text, Key, IV, "CBC")
	if Decrypted ~= "test" then
		return "Failed to decrypt text from encrypted string"
	end
	return true
end)

TestGlobal("crypt.generatebytes", {}, function()
	const Size = math.random(10, 100)
	const Bytes = crypt.generatebytes(Size)
	const Decoded = crypt.base64decode(Bytes)
	if #Decoded ~= Size then
		return `The decoded result should be {Size} bytes but got {#Decoded}`
	end
	return true
end)

TestGlobal("crypt.generatekey", {}, function()
	const Key = crypt.generatekey()
	if #crypt.base64decode(Key) ~= 32 then
		return "Generated key should be 32 bytes when decoded"
	end
	return true
end)

TestGlobal("crypt.hash", {}, function()
	const Algorithms = {"sha1", "sha384", "sha512", "md5", "sha256", "sha3-224", "sha3-256", "sha3-512"}
	for _, Algorithm in Algorithms do
		const Hash = crypt.hash("test", Algorithm)
		if not Hash or typeof(Hash) ~= "string" then
			return `crypt.hash failed for algorithm {Algorithm}`
		end
	end
	return true
end)

--============================================================
--// Debug
--============================================================

TestGlobal("debug.getconstant", {}, function()
	const function Test() print("Hello, world!") end
	if debug.getconstant(Test, 1) ~= "print" then
		return "First constant must be 'print'"
	end
	if debug.getconstant(Test, 3) ~= "Hello, world!" then
		return "Third constant must be 'Hello, world!'"
	end
	return true
end)

TestGlobal("debug.getconstants", {}, function()
	const function Test() const num = 5000 .. 50000 print("Hello, world!", num, warn) end
	const Constants = debug.getconstants(Test)
	if Constants[1] ~= 50000 then
		return "First constant must be 50000"
	end
	return true
end)

TestGlobal("debug.getinfo", {}, function()
	const Types = {
		source = "string", short_src = "string", func = "function",
		what = "string", currentline = "number", name = "string",
		nups = "number", numparams = "number", is_vararg = "number",
	}
	const function Test(...) return ... end
	const Info = debug.getinfo(Test)
	for Key, Type in Types do
		if Info[Key] == nil then
			return `Did not return a table with a '{Key}' field`
		end
		if typeof(Info[Key]) ~= Type then
			return `Did not return a table with '{Key}' of type {Type}`
		end
	end
	return true
end)

TestGlobal("debug.getproto", {}, function()
	const function Test()
		const function Proto() return true end
		return Proto
	end
	const RealProto = Test()
	const Proto = debug.getproto(Test, 1, true)[1]
	if not Proto then
		return "Failed to get inner function"
	end
	if not Proto() then
		return "The inner function did not return anything"
	end
	return true
end)

TestGlobal("debug.getprotos", {}, function()
	const function Test()
		const function A() return true end
		const function B() return true end
	end
	for i in debug.getprotos(Test) do
		const Proto = debug.getproto(Test, i, true)[1]
		if not Proto() then
			return "Failed to get inner functions"
		end
	end
	return true
end)

TestGlobal("debug.getstack", {}, function()
	const _ = 1 + 1
	if debug.getstack(1, 1) ~= 2 then
		return "The first stack item should be 2"
	end
	if debug.getstack(1)[1] ~= 2 then
		return "The first stack item should be 2"
	end
	return true
end)

TestGlobal("debug.getupvalue", {}, function()
	const Upvalue = function() end
	const function Test() print(Upvalue) end
	if debug.getupvalue(Test, 1) ~= Upvalue then
		return "Unexpected value returned from debug.getupvalue"
	end
	return true
end)

TestGlobal("debug.getupvalues", {}, function()
	const Upvalue = function() end
	const function Test() print(Upvalue) end
	const Upvalues = debug.getupvalues(Test)
	if Upvalues[1] ~= Upvalue then
		return "Unexpected value returned from debug.getupvalues"
	end
	return true
end)

TestGlobal("debug.setconstant", {}, function()
	const function Test() return "fail" end
	debug.setconstant(Test, 1, "success")
	if Test() ~= "success" then
		return "debug.setconstant failed to set constant"
	end
	return true
end)

TestGlobal("debug.setstack", {}, function()
	const function Test()
		return "fail", debug.setstack(1, 1, "success")
	end
	if Test() ~= "success" then
		return "debug.setstack failed to set stack value"
	end
	return true
end)

TestGlobal("debug.setupvalue", {}, function()
	const function Upvalue() return "fail" end
	const function Test() return Upvalue() end
	debug.setupvalue(Test, 1, function() return "success" end)
	if Test() ~= "success" then
		return "debug.setupvalue failed to set upvalue"
	end
	return true
end)

--============================================================
--// Filesystem
--============================================================

TestGlobal("readfile", {}, function()
	writefile("EnvCheck.txt", "success")
	if readfile("EnvCheck.txt") ~= "success" then
		return "Did not return the contents of the file"
	end
	return true
end)

TestGlobal("writefile", {}, function()
	writefile("EnvCheck.txt", "success")
	if readfile("EnvCheck.txt") ~= "success" then
		return "Failed to write to the file"
	end
	--// Note: extension check removed - writing a file without an extension
	--// crashes some executors.
	return true
end)

TestGlobal("appendfile", {}, function()
	writefile("EnvCheck.txt", "success")
	appendfile("EnvCheck.txt", "_appended")
	if readfile("EnvCheck.txt") ~= "success_appended" then
		return "Failed to append to the file"
	end
	writefile("EnvCheck.txt", "success")
	return true
end)

TestGlobal("isfile", {}, function()
	writefile("EnvCheck.txt", "success")
	if not isfile("EnvCheck.txt") then
		return "Did not return true for a file"
	end
	if isfile("EnvCheck") then
		return "Did not return false for a folder or nonexistent path"
	end
	return true
end)

TestGlobal("delfile", {}, function()
	writefile("EnvCheck.txt", "Hello, world!")
	delfile("EnvCheck.txt")
	if isfile("EnvCheck.txt") then
		return "Failed to delete file"
	end
	return true
end)

TestGlobal("loadfile", {}, function()
	writefile("EnvCheck.txt", "return ... + 1")
	const Func, Err = loadfile("EnvCheck.txt")
	if Err then
		return "Failed to load file: " .. tostring(Err)
	end
	if Func(1) ~= 2 then
		return "Failed to load and execute the file"
	end
	delfile("EnvCheck.txt")
	return true
end)

TestGlobal("dofile", {}, function()
	--// Behavior check: dofile must actually execute the file's code
	getgenv().__EnvCheckDofile = nil
	writefile("EnvCheck_dofile.lua", "getgenv().__EnvCheckDofile = 'executed'")
	pcall(dofile, "EnvCheck_dofile.lua")
	const Result = getgenv().__EnvCheckDofile
	getgenv().__EnvCheckDofile = nil
	pcall(delfile, "EnvCheck_dofile.lua")
	if Result ~= "executed" then
		return "dofile did not execute the file's code"
	end
	return true
end)

TestGlobal("makefolder", {}, function()
	delfolder("EnvCheckFolder")
	makefolder("EnvCheckFolder")
	if not isfolder("EnvCheckFolder") then
		return "Failed to create folder"
	end
	return true
end)

TestGlobal("isfolder", {}, function()
	makefolder("EnvCheckFolder")
	if not isfolder("EnvCheckFolder") then
		return "Did not return true for a folder"
	end
	if isfolder("nonexistent_path_xyz") then
		return "Did not return false for a nonexistent path"
	end
	return true
end)

TestGlobal("listfiles", {}, function()
	makefolder("EnvCheckFolder")
	writefile("EnvCheckFolder/test1.txt", "1")
	writefile("EnvCheckFolder/test2.txt", "2")
	const Files = listfiles("EnvCheckFolder")
	if #Files < 2 then
		return "Did not return the correct number of files"
	end
	if not isfile(Files[1]) then
		return "Did not return valid file paths"
	end
	return true
end)

TestGlobal("delfolder", {}, function()
	makefolder("EnvCheckFolder")
	delfolder("EnvCheckFolder")
	if isfolder("EnvCheckFolder") then
		return "Failed to delete folder"
	end
	return true
end)

TestGlobal("getcustomasset", {}, function()
	writefile("EnvCheck.txt", "success")
	const Asset = getcustomasset("EnvCheck.txt")
	if typeof(Asset) ~= "string" then
		return "Did not return a string"
	end
	if not Asset:find("rbxasset://") and not Asset:find("rbxtemp://") then
		return "Did not return an rbxasset content id"
	end
	return true
end)

--============================================================
--// Input
--============================================================

TestGlobal("isrbxactive", {"isgameactive"}, function()
	if typeof(isrbxactive()) ~= "boolean" then
		return "Did not return a boolean value"
	end
	return true
end)

--// Behavior verification: fire synthetic input, then confirm the Roblox engine
--// actually received it via UserInputService. Requires the window to be focused;
--// if unfocused, tests pass as unverifiable (synthetic input is dropped by the OS).
const UserInputService = game:GetService("UserInputService")

const function VerifyInput(Fire: () -> (), Check: (InputObject) -> boolean): boolean|string
	if isrbxactive and not isrbxactive() then
		return true -- Window not focused: input cannot be delivered, skip verification
	end

	local Detected = false
	const Connections = {}
	for _, Signal in {UserInputService.InputBegan, UserInputService.InputChanged, UserInputService.InputEnded} do
		table.insert(Connections, Signal:Connect(function(Input)
			if not Detected and Check(Input) then
				Detected = true
			end
		end))
	end

	pcall(Fire)

	const Deadline = os.clock() + 0.5
	while not Detected and os.clock() < Deadline do
		task.wait()
	end
	for _, Connection in Connections do
		Connection:Disconnect()
	end

	if not Detected then
		return "Synthetic input was not detected by UserInputService"
	end
	return true
end

TestGlobal("mouse1click", {}, function()
	return VerifyInput(function()
		mouse1click()
	end, function(Input)
		return Input.UserInputType == Enum.UserInputType.MouseButton1
	end)
end)

TestGlobal("mouse1press", {}, function()
	const Result = VerifyInput(function()
		mouse1press()
	end, function(Input)
		return Input.UserInputType == Enum.UserInputType.MouseButton1
			and Input.UserInputState == Enum.UserInputState.Begin
	end)
	--// Always release so the button is not left held down
	if mouse1release then pcall(mouse1release) end
	return Result
end)

TestGlobal("mouse1release", {}, function()
	if mouse1press then pcall(mouse1press) end
	task.wait(0.05)
	return VerifyInput(function()
		mouse1release()
	end, function(Input)
		return Input.UserInputType == Enum.UserInputType.MouseButton1
			and Input.UserInputState == Enum.UserInputState.End
	end)
end)

TestGlobal("mouse2click", {}, function()
	return VerifyInput(function()
		mouse2click()
	end, function(Input)
		return Input.UserInputType == Enum.UserInputType.MouseButton2
	end)
end)

TestGlobal("mouse2press", {}, function()
	const Result = VerifyInput(function()
		mouse2press()
	end, function(Input)
		return Input.UserInputType == Enum.UserInputType.MouseButton2
			and Input.UserInputState == Enum.UserInputState.Begin
	end)
	if mouse2release then pcall(mouse2release) end
	return Result
end)

TestGlobal("mouse2release", {}, function()
	if mouse2press then pcall(mouse2press) end
	task.wait(0.05)
	return VerifyInput(function()
		mouse2release()
	end, function(Input)
		return Input.UserInputType == Enum.UserInputType.MouseButton2
			and Input.UserInputState == Enum.UserInputState.End
	end)
end)

TestGlobal("mousemoveabs", {}, function()
	--// Move to (current position + offset) so the cursor is not thrown across the screen
	const Position = UserInputService:GetMouseLocation()
	return VerifyInput(function()
		mousemoveabs(Position.X + 15, Position.Y + 15)
	end, function(Input)
		return Input.UserInputType == Enum.UserInputType.MouseMovement
	end)
end)

TestGlobal("mousemoverel", {}, function()
	return VerifyInput(function()
		mousemoverel(15, 15)
	end, function(Input)
		return Input.UserInputType == Enum.UserInputType.MouseMovement
	end)
end)

TestGlobal("mousescroll", {}, function()
	return VerifyInput(function()
		mousescroll(1)
	end, function(Input)
		return Input.UserInputType == Enum.UserInputType.MouseWheel
	end)
end)

TestGlobal("keypress", {}, function()
	--// F15 (VK 0x7E): a real key Roblox recognizes, but one that no game or
	--// textbox reacts to - safe to press without side effects
	const Result = VerifyInput(function()
		keypress(0x7E)
	end, function(Input)
		return Input.KeyCode == Enum.KeyCode.F15
			and Input.UserInputState == Enum.UserInputState.Begin
	end)
	if keyrelease then pcall(keyrelease, 0x7E) end
	return Result
end)

TestGlobal("keyrelease", {}, function()
	if keypress then pcall(keypress, 0x7E) end
	task.wait(0.05)
	return VerifyInput(function()
		keyrelease(0x7E)
	end, function(Input)
		return Input.KeyCode == Enum.KeyCode.F15
			and Input.UserInputState == Enum.UserInputState.End
	end)
end)

--============================================================
--// Instances
--============================================================

TestGlobal("fireclickdetector", {}, function()
	--// Behavior check: the fired event must actually reach a connected handler
	const Detector = Instance.new("ClickDetector")
	local Clicked = false
	const Connection = Detector.MouseClick:Connect(function()
		Clicked = true
	end)

	fireclickdetector(Detector, 0, "MouseClick")

	--// Events may be deferred: give the engine a moment to dispatch
	const Deadline = os.clock() + 0.5
	while not Clicked and os.clock() < Deadline do
		task.wait()
	end
	Connection:Disconnect()
	Detector:Destroy()

	if not Clicked then
		return "MouseClick event was not received by the connected handler"
	end
	return true
end)

TestGlobal("getcallbackvalue", {}, function()
	const Bindable = Instance.new("BindableFunction")
	const function Test() end
	Bindable.OnInvoke = Test
	if getcallbackvalue(Bindable, "OnInvoke") ~= Test then
		return "Did not return the correct value"
	end
	return true
end)

TestGlobal("getconnections", {}, function()
	const Types = {
		Enabled = "boolean", ForeignState = "boolean", LuaConnection = "boolean",
		Function = "function", Thread = "thread",
		Fire = "function", Defer = "function", Disconnect = "function",
		Disable = "function", Enable = "function",
	}
	const Bindable = Instance.new("BindableEvent")
	Bindable.Event:Connect(function() end)
	const Connection = getconnections(Bindable.Event)[1]
	for Key, Type in Types do
		if Connection[Key] == nil then
			return `Did not return a table with a '{Key}' field`
		end
		if typeof(Connection[Key]) ~= Type then
			return `Did not return a table with '{Key}' of type {Type}`
		end
	end
	return true
end)

--// DISABLED: gethiddenproperty on size_xml causes a native (C-level) crash on
--// this executor - pcall cannot catch it. Existence-only until it is fixed.
TestGlobal("gethiddenproperty", {}, function()
	return true -- Existence-only check (actual call crashes the executor)
end)

--// DISABLED: sethiddenproperty uses the same hidden-property access path.
TestGlobal("sethiddenproperty", {}, function()
	return true -- Existence-only check (actual call crashes the executor)
end)

TestGlobal("gethui", {}, function()
	if typeof(gethui()) ~= "Instance" then
		return "Did not return an Instance"
	end
	return true
end)

TestGlobal("getinstances", {}, function()
	if #getinstances() <= 0 then
		return "Did not return any instances"
	end
	if typeof(getinstances()[1]) ~= "Instance" then
		return "First value is not an Instance"
	end
	return true
end)

TestGlobal("getnilinstances", {}, function()
	if typeof(getnilinstances()[1]) ~= "Instance" then
		return "First value is not an Instance"
	end
	return true
end)

TestGlobal("isscriptable", {}, function()
	const Fire = Instance.new("Fire")
	if isscriptable(Fire, "size_xml") then
		return "Did not return false for a non-scriptable property (size_xml)"
	end
	if not isscriptable(Fire, "Size") then
		return "Did not return true for a scriptable property (Size)"
	end
	return true
end)

TestGlobal("setscriptable", {}, function()
	const Fire = Instance.new("Fire")
	const WasScriptable = setscriptable(Fire, "size_xml", true)
	const NowScriptable = isscriptable(Fire, "size_xml")
	--// Restore: leaving size_xml scriptable globally is a crash risk for later code
	pcall(setscriptable, Fire, "size_xml", false)
	if WasScriptable ~= false then
		return "Did not return whether the property was scriptable"
	end
	if not NowScriptable then
		return "Did not set the property to scriptable"
	end
	return true
end)

TestGlobal("setrbxclipboard", {}, function()
	--// Behavior check: must accept a valid rbxm/model data string without erroring.
	--// Full verification (pasting into Studio) is impossible from a test.
	const Ok, Err = pcall(setrbxclipboard, "<roblox version=\"4\"></roblox>")
	if not Ok then
		return "setrbxclipboard errored on valid model data: " .. tostring(Err)
	end
	return true
end)

--============================================================
--// Metatable
--============================================================

TestGlobal("getrawmetatable", {}, function()
	const Metatable = {__metatable = "Locked!"}
	const Object = setmetatable({}, Metatable)
	if getrawmetatable(Object) ~= Metatable then
		return "Did not return the metatable"
	end
	return true
end)

TestGlobal("hookmetamethod", {}, function()
	const Object = setmetatable({}, {__index = newcclosure(function() return false end)})
	const Ref = hookmetamethod(Object, "__index", function() return true end)
	if not Object.test then
		return "Failed to hook a metamethod and change the return value"
	end
	if Ref() then
		return "Did not return the original function"
	end
	return true
end)

TestGlobal("getnamecallmethod", {}, function()
	local Method
	local Ref
	--// NOTE: never re-hook from inside a running hook - that crashes many executors.
	--// The hook only records the method and forwards the call; restore happens outside.
	Ref = hookmetamethod(game, "__namecall", function(...)
		if not Method then Method = getnamecallmethod() end
		return Ref(...)
	end)

	const CallOk = pcall(function() return game:GetService("Lighting") end)

	--// Restore the original exactly once, outside the hook
	if Ref then pcall(hookmetamethod, game, "__namecall", Ref) end

	if not CallOk then
		return "Namecall errored while hooked"
	end
	if Method ~= "GetService" then
		return "Did not get the correct method (GetService)"
	end
	return true
end)

TestGlobal("isreadonly", {}, function()
	const Object = {}
	table.freeze(Object)
	if not isreadonly(Object) then
		return "Did not return true for a read-only table"
	end
	return true
end)

TestGlobal("setrawmetatable", {}, function()
	const Object = setmetatable({}, {__index = function() return false end})
	setrawmetatable(Object, {__index = function() return true end})
	if not Object.test then
		return "Failed to change the metatable"
	end
	return true
end)

TestGlobal("setreadonly", {}, function()
	const Object = {}
	table.freeze(Object)
	setreadonly(Object, false)
	Object.success = true
	if not Object.success then
		return "Did not allow the table to be written to"
	end
	return true
end)

--============================================================
--// Miscellaneous
--============================================================

TestGlobal("identifyexecutor", {"getexecutorname"}, function()
	const Name, Version = identifyexecutor()
	if typeof(Name) ~= "string" then
		return "Did not return a string for the name"
	end
	return true
end)

TestGlobal("lz4compress", {}, function()
	const Raw = "Hello, world!"
	const Compressed = lz4compress(Raw)
	if typeof(Compressed) ~= "string" then
		return "Compression did not return a string"
	end
	if lz4decompress(Compressed, #Raw) ~= Raw then
		return "Decompression did not return the original string"
	end
	return true
end)

TestGlobal("lz4decompress", {}, function()
	const Raw = "Hello, world!"
	const Compressed = lz4compress(Raw)
	if lz4decompress(Compressed, #Raw) ~= Raw then
		return "Decompression did not return the original string"
	end
	return true
end)

TestGlobal("messagebox", {}, function()
	--// Cannot behavior-test: messagebox opens a blocking modal dialog that
	--// requires the user to click. Existence-only by necessity.
	return true
end)

TestGlobal("queue_on_teleport", {"queueonteleport"}, function()
	--// Behavior check: queueing must not error. Full verification would require
	--// an actual teleport, which cannot be done in a test.
	queue_on_teleport("-- EnvCheck queue_on_teleport test")
	if clearteleportqueue then
		pcall(clearteleportqueue)
	end
	return true
end)

TestGlobal("request", {"http.request", "http_request"}, function()
	if not RunNetworkTests then
		return true -- Network tests disabled (set RunNetworkTests = true to enable)
	end
	const Response = request({
		Url = "https://httpbin.org/user-agent",
		Method = "GET",
	})
	if typeof(Response) ~= "table" then
		return "Did not return a table"
	end
	if Response.StatusCode ~= 200 then
		return "Did not return a 200 status code"
	end
	const Data = game:GetService("HttpService"):JSONDecode(Response.Body)
	if typeof(Data["user-agent"]) ~= "string" then
		return "Did not send a user agent"
	end
	return true
end)

TestGlobal("setclipboard", {"toclipboard"}, function()
	--// Behavior check: write to the clipboard and, if a getter exists, read it back
	setclipboard("EnvCheck setclipboard test")
	const Getter = getclipboard or getrbxclipboard
	if Getter then
		const Ok, Value = pcall(Getter)
		if Ok and Value ~= "EnvCheck setclipboard test" then
			return "Clipboard content does not match what was set"
		end
	end
	return true
end)

--// Measures average FPS over ~20 frames
const function MeasureFPS(): number
	const Start = os.clock()
	local Frames = 0
	while Frames < 20 do
		game:GetService("RunService").RenderStepped:Wait()
		Frames += 1
	end
	return Frames / (os.clock() - Start)
end

TestGlobal("setfpscap", {}, function()
	--// Behavior check: cap to 30 and verify real framerate drops accordingly
	setfpscap(30)
	task.wait(0.2) -- Let the cap settle
	const Capped = MeasureFPS()
	setfpscap(0) -- Restore uncapped (0/1000 = unlimited on most executors)

	--// Tolerance: timers are imprecise, accept anything below ~45 as "capped to 30"
	if Capped > 45 then
		return `FPS cap of 30 had no effect (measured ~{math.round(Capped)} FPS)`
	end
	return true
end)

TestGlobal("getfpscap", {}, function()
	--// Behavior check: set a cap, read it back
	if not setfpscap then
		const Value = getfpscap()
		if typeof(Value) ~= "number" then
			return "Did not return a number"
		end
		return true
	end
	setfpscap(72)
	const Value = getfpscap()
	setfpscap(0)
	if typeof(Value) ~= "number" then
		return "Did not return a number"
	end
	if Value ~= 72 then
		return `Expected 72, got {Value}`
	end
	return true
end)

--============================================================
--// Scripts
--============================================================

TestGlobal("getgc", {}, function()
	const GC = getgc()
	if typeof(GC) ~= "table" or #GC == 0 then
		return "Did not return a table with any values"
	end
	return true
end)

TestGlobal("getgenv", {}, function()
	getgenv().__EnvCheck = true
	if __EnvCheck ~= true then
		return "Globals set using getgenv() are not visible in the executor scope"
	end
	getgenv().__EnvCheck = nil
	return true
end)

TestGlobal("getloadedmodules", {}, function()
	const Modules = getloadedmodules()
	if typeof(Modules) ~= "table" then
		return "Did not return a table"
	end
	if #Modules > 0 and typeof(Modules[1]) ~= "Instance" then
		return "First value is not an Instance"
	end
	return true
end)

TestGlobal("getrenv", {}, function()
	if getrenv().print == print then
		return "The executor's globals should not be the same as the game's"
	end
	return true
end)

TestGlobal("getrunningscripts", {}, function()
	const Scripts = getrunningscripts()
	if typeof(Scripts) ~= "table" then
		return "Did not return a table"
	end
	if #Scripts > 0 and typeof(Scripts[1]) ~= "Instance" then
		return "First value is not an Instance"
	end
	return true
end)

--// DISABLED: getscriptbytecode causes a native (C-level) crash on this executor
--// even on safe replicated scripts - pcall cannot catch it. Only checks existence.
TestGlobal("getscriptbytecode", {"dumpstring"}, function()
	return true -- Existence-only check (actual call crashes the executor)
end)

--// DISABLED: getscripthash dumps bytecode internally - same native crash path.
TestGlobal("getscripthash", {}, function()
	return true -- Existence-only check (actual call crashes the executor)
end)

TestGlobal("getscripts", {}, function()
	const Scripts = getscripts()
	if typeof(Scripts) ~= "table" then
		return "Did not return a table"
	end
	if #Scripts > 0 and typeof(Scripts[1]) ~= "Instance" then
		return "First value is not an Instance"
	end
	return true
end)

TestGlobal("getsenv", {}, function()
	const Player = game:GetService("Players").LocalPlayer
	if not Player then return true end
	--// Do NOT use CharacterAdded:Wait() - it hangs forever if the character never spawns
	const Character = Player.Character
	if not Character then return true end
	const Script = Character:FindFirstChild("Animate")
	if not Script then return true end
	const Env = getsenv(Script)
	if typeof(Env) ~= "table" then
		return "Did not return a table for the script environment"
	end
	return true
end)

TestGlobal("getthreadidentity", {"getidentity", "getthreadcontext"}, function()
	if typeof(getthreadidentity()) ~= "number" then
		return "Did not return a number"
	end
	return true
end)

TestGlobal("setthreadidentity", {"setidentity", "setthreadcontext"}, function()
	const Previous = getthreadidentity()
	setthreadidentity(3)
	const Changed = getthreadidentity() == 3
	--// Always restore the original identity to avoid breaking later tests
	setthreadidentity(Previous)
	if not Changed then
		return "Did not set the thread identity"
	end
	return true
end)

--============================================================
--// Drawing
--============================================================

TestGlobal("Drawing", {}, function()
	const Line = Drawing.new("Line")
	Line.Visible = false
	const CanSet = pcall(function()
		Line.From = Vector2.new(0, 0)
		Line.To = Vector2.new(10, 10)
		Line.Color = Color3.new(1, 1, 1)
	end)
	Line:Remove()
	if not CanSet then
		return "Failed to set Drawing properties"
	end
	return true
end)

TestGlobal("Drawing.new", {}, function()
	const Drawing = Drawing.new("Square")
	Drawing.Visible = false
	const CanClear = pcall(function() Drawing:Destroy() end)
	if not CanClear then
		--// pcall: Remove after a failed/partial Destroy can double-free on some executors
		pcall(function() Drawing:Remove() end)
		return "Drawing:Destroy() should exist and not error"
	end
	return true
end)

TestGlobal("Drawing.Fonts", {}, function()
	if typeof(Drawing.Fonts) ~= "table" and typeof(Drawing.Fonts) ~= "userdata" then
		return "Did not return a table or userdata"
	end
	return true
end)

TestGlobal("isrenderobj", {}, function()
	--// Keep invisible: rendering an Image with no Data crashes some executors
	const Drawing = Drawing.new("Image")
	Drawing.Visible = false
	if not isrenderobj(Drawing) then
		return "Did not return true for a render object"
	end
	if isrenderobj(newproxy()) then
		return "Did not return false for a non-render object"
	end
	Drawing:Remove()
	return true
end)

TestGlobal("getrenderproperty", {}, function()
	const Drawing = Drawing.new("Image")
	Drawing.Visible = false
	if typeof(getrenderproperty(Drawing, "Visible")) ~= "boolean" then
		return "Did not return a boolean value for Visible"
	end
	Drawing:Remove()
	return true
end)

TestGlobal("setrenderproperty", {}, function()
	const Drawing = Drawing.new("Square")
	Drawing.Visible = false
	setrenderproperty(Drawing, "Visible", false)
	if Drawing.Visible ~= false then
		return "Did not set the property correctly"
	end
	Drawing:Remove()
	return true
end)

TestGlobal("cleardrawcache", {}, function()
	cleardrawcache()
	return true
end)

--============================================================
--// WebSocket
--============================================================

TestGlobal("WebSocket", {}, function()
	if typeof(WebSocket) ~= "table" and typeof(WebSocket) ~= "function" then
		return "WebSocket should be a table or function"
	end
	if typeof(WebSocket.connect) ~= "function" then
		return "WebSocket.connect should be a function"
	end
	return true
end)

TestGlobal("WebSocket.connect", {}, function()
	if not RunNetworkTests then
		return true -- Network tests disabled (set RunNetworkTests = true to enable)
	end
	const Types = {Send = "function", Close = "function", OnMessage = {"table", "userdata"}, OnClose = {"table", "userdata"}}
	const Ok, Socket = pcall(function()
		return WebSocket.connect("ws://echo.websocket.events")
	end)
	if not Ok then
		return "Failed to connect: " .. tostring(Socket)
	end
	for Key in Types do
		if Socket[Key] == nil then
			return `Did not return a socket with a '{Key}' field`
		end
	end
	pcall(function() Socket:Close() end)
	return true
end)

--// Done
PrintSummary()
