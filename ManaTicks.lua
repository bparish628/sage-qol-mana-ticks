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

local regen = { phase = "full", since = 0, lastMana = 0, lastTickAt = nil }
local sparks = {}
local druidBar
local activeBars = {}

local function ResetRegen(mana, maxMana, now)
	regen.lastMana = mana
	regen.lastTickAt = nil
	regen.phase = mana >= maxMana and "full" or "ticking"
	regen.since = now
end

local function ApplyManaChange(mana, maxMana, now)
	if mana < regen.lastMana then
		regen.phase = "waiting"
		regen.since = now
	elseif mana > regen.lastMana then
		regen.lastTickAt = now
		if regen.phase ~= "waiting" or now - regen.since >= CONFIG.waitSeconds then
			regen.phase = "ticking"
			regen.since = now
		end
	end
	regen.lastMana = mana
	if mana >= maxMana and regen.phase ~= "waiting" then
		regen.phase = "full"
	end
end

local function ExpireWait(isFull, now)
	if regen.phase ~= "waiting" or now - regen.since < CONFIG.waitSeconds then return end
	if isFull then
		regen.phase = "full"
	else
		regen.phase = "ticking"
		regen.since = regen.lastTickAt or (regen.since + CONFIG.waitSeconds)
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

-- Forever returns mana as a secret value while a druid's form uses another power.
-- Secrets error on comparison or math but can be handed to widgets, which draw them.
local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

local function UpdateDruidBar(mana, maxMana)
	local bar = GetDruidBar()
	bar:SetMinMaxValues(0, maxMana)
	bar:SetValue(mana)
	bar.text:SetFormattedText("%d / %d", mana, maxMana)
end

local function Refresh()
	local mana, maxMana = UnitPower("player", MANA), UnitPowerMax("player", MANA)
	local hasMana = (IsSecret(maxMana) or maxMana > 0) and not UnitIsDeadOrGhost("player")
	local inForm = hasMana and select(2, UnitClass("player")) == "DRUID" and UnitPowerType("player") ~= MANA

	HideSparks()
	activeBars = {}
	if hasMana and not inForm then
		activeBars[1] = PlayerFrame_GetManaBar()
	end
	if inForm then
		-- Shifting costs mana, but the drop may land after mana turns secret, so start the wait here.
		if not (druidBar and druidBar:IsShown()) then
			regen.phase, regen.since = "waiting", GetTime()
		end
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

local logUntil, lastLogTime, lastEventTime = 0, nil, nil

local function LogManaChange(mana, now)
	if now > logUntil or mana == regen.lastMana then return end
	local gap = lastLogTime and string.format("%.2fs after previous", now - lastLogTime) or "first"
	print(string.format("|cff66ccffMana Ticks|r %+d mana, %s", mana - regen.lastMana, gap))
	lastLogTime = now
end

-- Mana is polled because Forever sends no mana update while a druid is in cat or bear form.
local function OnUpdate()
	local now = GetTime()
	local mana, maxMana = UnitPower("player", MANA), UnitPowerMax("player", MANA)
	if druidBar and druidBar:IsShown() then
		UpdateDruidBar(mana, maxMana)
	end
	if IsSecret(mana) or IsSecret(maxMana) then
		-- Ticks can't be seen, so the spark keeps the cadence learned from the last readable ticks.
		ExpireWait(false, now)
	else
		if maxMana > 0 and mana ~= regen.lastMana then
			LogManaChange(mana, now)
			ApplyManaChange(mana, maxMana, now)
		end
		ExpireWait(mana >= maxMana, now)
	end
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
driver:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
driver:SetScript("OnEvent", function(_, event, _, powerToken)
	if event == "UNIT_POWER_UPDATE" then
		if powerToken == "MANA" and GetTime() <= logUntil then
			local now = GetTime()
			local gap = lastEventTime and string.format("%.2fs after previous", now - lastEventTime) or "first"
			print("|cff66ccffMana Ticks|r mana event, " .. gap)
			lastEventTime = now
		end
		return
	end
	if event == "PLAYER_ENTERING_WORLD" then
		local mana, maxMana = UnitPower("player", MANA), UnitPowerMax("player", MANA)
		if not IsSecret(mana) and not IsSecret(maxMana) then ResetRegen(mana, maxMana, GetTime()) end
	end
	Refresh()
end)

-- An error here would repeat every frame, so stop the loop and report it once.
driver:SetScript("OnUpdate", function()
	local ok, err = pcall(OnUpdate)
	if not ok then
		driver:SetScript("OnUpdate", nil)
		HideSparks()
		print("|cff66ccffMana Ticks|r stopped after an error: " .. tostring(err))
	end
end)

SLASH_SAGEQOLMANATICKS1 = "/manaticks"
SlashCmdList.SAGEQOLMANATICKS = function(msg)
	if msg:lower():match("^%s*log") then
		logUntil, lastLogTime, lastEventTime = GetTime() + 30, nil, nil
		local mana, maxMana = UnitPower("player", MANA), UnitPowerMax("player", MANA)
		print(string.format("|cff66ccffMana Ticks|r mana %s, max %s, power type %s, phase %s, frame loop %s.",
			IsSecret(mana) and "hidden" or tostring(mana),
			IsSecret(maxMana) and "hidden" or tostring(maxMana),
			tostring(UnitPowerType("player")), regen.phase,
			driver:GetScript("OnUpdate") and "running" or "stopped"))
		print("|cff66ccffMana Ticks|r logging mana changes and mana events for 30 seconds.")
	else
		print("|cff66ccffMana Ticks|r /manaticks log prints each mana change for 30 seconds.")
	end
end
