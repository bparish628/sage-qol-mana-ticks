local CONFIG = {
	waitSeconds = 5,
	tickSeconds = 2,
	-- A mana event this soon after a mana-costing cast is the cost landing, not a tick.
	spendEchoSeconds = 0.5,
	-- With mana hidden, regen counts as stopped (mana full) after this long without a tick.
	stalledSeconds = 2.5,
	spark = {
		atlas = "ui-castingbar-pip",
		width = 6,
		extraHeight = 6,
		waitColor = { 1, 0.85, 0.4, 0.9 },
		tickColor = { 0.6, 0.9, 1, 0.9 },
	},
	druidBar = {
		height = 10,
		offsetY = -4,
		borderColor = { 0, 0, 0, 1 },
		backgroundColor = { 0, 0, 0, 0.6 },
		font = "GameFontHighlightSmall",
	},
}

local MANA = Enum.PowerType.Mana
local PREFIX = "|cff66ccffMana Ticks|r "

-- waitStart: when the last mana-costing cast landed (start of the five-second rule).
-- lastTickAt: when mana last arrived from regen; ticks follow a fixed two-second clock from it.
-- lastMana: last readable mana, used to tell a tick from a spend when mana isn't hidden.
local regen = { waitStart = nil, lastTickAt = nil, lastMana = nil }
local sparks = {}
local druidBar
local activeBars = {}
local logUntil, lastLogAt = 0, nil

-- Forever returns mana as a secret value while a druid's form uses another power.
-- Secrets error on comparison or math but can be handed to widgets, which draw them.
local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

local function ReadableMana()
	local mana, maxMana = UnitPower("player", MANA), UnitPowerMax("player", MANA)
	if IsSecret(mana) or IsSecret(maxMana) then return nil end
	return mana, maxMana
end

local function CostsMana(spellID)
	if IsSecret(spellID) then return true end
	for _, cost in ipairs(C_Spell.GetSpellPowerCost(spellID) or {}) do
		if cost.type == MANA and not IsSecret(cost.cost) and cost.cost > 0 then return true end
	end
	return false
end

local function Log(text, now)
	if now > logUntil then return end
	local gap = lastLogAt and string.format("%.2fs after previous", now - lastLogAt) or "first"
	print(PREFIX .. text .. ", " .. gap)
	lastLogAt = now
end

local function OnManaSpent(now)
	regen.waitStart = now
	Log("mana spent", now)
end

local function OnManaEvent(now)
	local mana = ReadableMana()
	local isTick
	if mana and regen.lastMana then
		isTick = mana > regen.lastMana
	else
		isTick = not (regen.waitStart and now - regen.waitStart < CONFIG.spendEchoSeconds)
	end
	regen.lastMana = mana
	if isTick then
		regen.lastTickAt = now
		Log(mana and "regen tick" or "regen tick (mana hidden)", now)
	end
end

local function IsWaiting(now)
	return regen.waitStart ~= nil and now - regen.waitStart < CONFIG.waitSeconds
end

local function IsFull(now)
	local mana, maxMana = ReadableMana()
	if mana then return mana >= maxMana end
	local lastActivity = math.max(regen.lastTickAt or 0, (regen.waitStart or 0) + CONFIG.waitSeconds)
	return now - lastActivity > CONFIG.stalledSeconds
end

-- Returns nil when there is nothing to show.
local function SparkProgress(now)
	if IsWaiting(now) then
		return (now - regen.waitStart) / CONFIG.waitSeconds, CONFIG.spark.waitColor
	end
	if IsFull(now) then return nil end
	local anchor = regen.lastTickAt or (regen.waitStart and regen.waitStart + CONFIG.waitSeconds)
	if not anchor then return nil end
	return ((now - anchor) % CONFIG.tickSeconds) / CONFIG.tickSeconds, CONFIG.spark.tickColor
end

local function GetSpark(bar)
	local spark = sparks[bar]
	if not spark then
		spark = bar:CreateTexture(nil, "OVERLAY", nil, 7)
		spark:SetAtlas(CONFIG.spark.atlas)
		spark:SetSize(CONFIG.spark.width, bar:GetHeight() + CONFIG.spark.extraHeight)
		spark:Hide()
		sparks[bar] = spark
	end
	return spark
end

local function PositionSpark(bar, progress, color)
	local spark = GetSpark(bar)
	spark:SetHeight(bar:GetHeight() + CONFIG.spark.extraHeight)
	spark:SetVertexColor(unpack(color))
	spark:ClearAllPoints()
	spark:SetPoint("CENTER", bar, "LEFT", Clamp(progress, 0, 1) * bar:GetWidth(), 0)
	spark:Show()
end

local function HideSparks()
	for _, spark in pairs(sparks) do spark:Hide() end
end

local function GetDruidBar()
	if druidBar then return druidBar end
	local cfg = CONFIG.druidBar
	local manaBar = PlayerFrame_GetManaBar()
	druidBar = CreateFrame("StatusBar", nil, PlayerFrame, "BackdropTemplate")
	druidBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	local color = PowerBarColor["MANA"]
	druidBar:SetStatusBarColor(color.r, color.g, color.b)
	druidBar:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		edgeSize = 1,
	})
	druidBar:SetBackdropColor(unpack(cfg.backgroundColor))
	druidBar:SetBackdropBorderColor(unpack(cfg.borderColor))
	druidBar:SetHeight(cfg.height)
	druidBar:SetPoint("TOPLEFT", manaBar, "BOTTOMLEFT", 0, cfg.offsetY)
	druidBar:SetPoint("TOPRIGHT", manaBar, "BOTTOMRIGHT", 0, cfg.offsetY)
	druidBar.text = druidBar:CreateFontString(nil, "OVERLAY", cfg.font)
	druidBar.text:SetPoint("CENTER")
	druidBar:Hide()
	return druidBar
end

-- Called on mana events rather than every frame, so the bar steps on ticks
-- instead of following the client's smoothed value.
local function UpdateDruidBar()
	if not (druidBar and druidBar:IsShown()) then return end
	local mana, maxMana = UnitPower("player", MANA), UnitPowerMax("player", MANA)
	druidBar:SetMinMaxValues(0, maxMana)
	druidBar:SetValue(mana)
	druidBar.text:SetFormattedText("%d / %d", mana, maxMana)
end

local function Refresh()
	local maxMana = UnitPowerMax("player", MANA)
	local hasMana = (IsSecret(maxMana) or maxMana > 0) and not UnitIsDeadOrGhost("player")
	local inForm = hasMana and select(2, UnitClass("player")) == "DRUID" and UnitPowerType("player") ~= MANA

	HideSparks()
	activeBars = {}
	if hasMana and not inForm then
		activeBars[1] = PlayerFrame_GetManaBar()
	end
	if inForm then
		GetDruidBar():Show()
		UpdateDruidBar()
		activeBars[1] = druidBar
	elseif druidBar then
		druidBar:Hide()
	end
end

local function OnUpdate()
	local progress, color = SparkProgress(GetTime())
	for _, bar in ipairs(activeBars) do
		if progress then
			PositionSpark(bar, progress, color)
		elseif sparks[bar] then
			sparks[bar]:Hide()
		end
	end
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("PLAYER_DEAD")
driver:RegisterEvent("PLAYER_ALIVE")
driver:RegisterEvent("PLAYER_UNGHOST")
driver:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
driver:RegisterUnitEvent("UNIT_MAXPOWER", "player")
driver:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
driver:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
driver:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
driver:SetScript("OnEvent", function(_, event, ...)
	local now = GetTime()
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		local _, _, spellID = ...
		if CostsMana(spellID) then OnManaSpent(now) end
	elseif event == "UNIT_POWER_UPDATE" then
		local _, powerToken = ...
		if powerToken == "MANA" then
			OnManaEvent(now)
			UpdateDruidBar()
		end
	else
		if event == "PLAYER_ENTERING_WORLD" then
			regen.waitStart, regen.lastTickAt, regen.lastMana = nil, nil, ReadableMana()
		end
		Refresh()
	end
end)

-- An error here would repeat every frame, so stop the loop and report it once.
driver:SetScript("OnUpdate", function()
	local ok, err = pcall(OnUpdate)
	if not ok then
		driver:SetScript("OnUpdate", nil)
		HideSparks()
		print(PREFIX .. "stopped after an error: " .. tostring(err))
	end
end)

SLASH_SAGEQOLMANATICKS1 = "/manaticks"
SlashCmdList.SAGEQOLMANATICKS = function(msg)
	if msg:lower():match("^%s*log") then
		logUntil, lastLogAt = GetTime() + 30, nil
		local mana, maxMana = UnitPower("player", MANA), UnitPowerMax("player", MANA)
		print(string.format("%smana %s, max %s, power type %s, frame loop %s. Logging for 30 seconds.", PREFIX,
			IsSecret(mana) and "hidden" or tostring(mana),
			IsSecret(maxMana) and "hidden" or tostring(maxMana),
			tostring(UnitPowerType("player")),
			driver:GetScript("OnUpdate") and "running" or "stopped"))
	else
		print(PREFIX .. "/manaticks log prints mana spends and regen ticks for 30 seconds.")
	end
end
