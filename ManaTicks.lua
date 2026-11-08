local CONFIG = {
	waitSeconds = 5,
	tickSeconds = 2,
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

local regen = { phase = "full", since = 0, lastMana = 0, lastTick = nil }
local sparks = {}
local druidBar
local activeBars = {}

local function ResetRegen(mana, maxMana, now)
	regen.lastMana = mana
	regen.lastTick = nil
	regen.phase = mana >= maxMana and "full" or "ticking"
	regen.since = now
end

local function ApplyManaChange(mana, maxMana, now)
	if mana < regen.lastMana then
		regen.phase = "waiting"
		regen.since = now
		regen.lastTick = nil
	elseif mana > regen.lastMana then
		if regen.phase == "waiting" and now - regen.since < CONFIG.waitSeconds then
			regen.lastTick = now
		else
			regen.phase = "ticking"
			regen.since = now
		end
	end
	regen.lastMana = mana
	if mana >= maxMana and regen.phase ~= "waiting" then
		regen.phase = "full"
	end
end

local function ExpireWait(mana, maxMana, now)
	if regen.phase ~= "waiting" or now - regen.since < CONFIG.waitSeconds then return end
	if mana >= maxMana then
		regen.phase = "full"
	else
		regen.phase = "ticking"
		regen.since = regen.lastTick or (regen.since + CONFIG.waitSeconds)
	end
end

-- Returns nil when there is nothing to show.
local function SparkProgress(now)
	if regen.phase == "waiting" then
		return (now - regen.since) / CONFIG.waitSeconds, CONFIG.spark.waitColor
	elseif regen.phase == "ticking" then
		return ((now - regen.since) % CONFIG.tickSeconds) / CONFIG.tickSeconds, CONFIG.spark.tickColor
	end
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

local function UpdateDruidBar(mana, maxMana)
	local bar = GetDruidBar()
	bar:SetMinMaxValues(0, math.max(maxMana, 1))
	bar:SetValue(mana)
	bar.text:SetFormattedText("%d / %d", mana, maxMana)
end

local function Refresh()
	local maxMana = UnitPowerMax("player", MANA)
	local mana = UnitPower("player", MANA)
	local hasMana = maxMana > 0 and not UnitIsDeadOrGhost("player")
	local inForm = hasMana and select(2, UnitClass("player")) == "DRUID" and UnitPowerType("player") ~= MANA

	HideSparks()
	activeBars = {}
	if hasMana and not inForm then
		activeBars[1] = PlayerFrame_GetManaBar()
	end
	if inForm then
		UpdateDruidBar(mana, maxMana)
		GetDruidBar():Show()
		activeBars[1] = druidBar
	elseif druidBar then
		druidBar:Hide()
	end
	if not hasMana then
		regen.phase = "full"
	end
end

local logUntil, lastLogTime = 0, nil

local function LogManaChange(mana, now)
	if now > logUntil or mana == regen.lastMana then return end
	local gap = lastLogTime and string.format("%.2fs after previous", now - lastLogTime) or "first"
	print(string.format("|cff66ccffMana Ticks|r %+d mana, %s", mana - regen.lastMana, gap))
	lastLogTime = now
end

-- Mana is polled because Forever did not send a mana update while a druid was in cat or bear form.
local function OnUpdate()
	local now = GetTime()
	local mana, maxMana = UnitPower("player", MANA), UnitPowerMax("player", MANA)
	if maxMana > 0 and mana ~= regen.lastMana then
		LogManaChange(mana, now)
		ApplyManaChange(mana, maxMana, now)
		if druidBar and druidBar:IsShown() then
			UpdateDruidBar(mana, maxMana)
		end
	end
	ExpireWait(mana, maxMana, now)
	local progress, color = SparkProgress(now)
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
driver:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" then
		ResetRegen(UnitPower("player", MANA), UnitPowerMax("player", MANA), GetTime())
		Refresh()
	else
		Refresh()
	end
end)
driver:SetScript("OnUpdate", OnUpdate)

SLASH_SAGEQOLMANATICKS1 = "/manaticks"
SlashCmdList.SAGEQOLMANATICKS = function(msg)
	if msg:lower():match("^%s*log") then
		logUntil, lastLogTime = GetTime() + 30, nil
		print("|cff66ccffMana Ticks|r logging mana changes for 30 seconds.")
	else
		print("|cff66ccffMana Ticks|r /manaticks log prints each mana change for 30 seconds.")
	end
end
