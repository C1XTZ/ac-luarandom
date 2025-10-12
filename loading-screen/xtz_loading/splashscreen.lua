local size = vec2()
local bgWidth = 0
local infoWidth = 0
local infoX = 0
local scaleRatio = 1
local bgColor = rgbm(0.33, 0.33, 0.33, 1)
local sweepColor = rgbm(0, 0, 0, 0.33)
local barHeight = 20
local contentCache = {}
local contentStateDone = false
local infoSide = ac.storage('infoSide', 2)
local infoStarted = false
local hoverTimer = 0
local animTimer = 0
local fadeAlpha = { 0, 0, 0 }
local fadeSpeed = 10

local carDescription, carName, trackDescription, loadingStatus, gameInfoText, lastContentState

local raceINI = ac.INIConfig.raceConfig()
local weatherfxImpl = ac.INIConfig.load(ac.getFolder(ac.FolderID.ExtCfgUser) .. '\\weather_fx.ini'):get('BASIC', 'IMPLEMENTATION', 'Default')
local ppFilter = ac.INIConfig.load(ac.getFolder(ac.FolderID.Cfg) .. '\\video.ini'):get('POST_PROCESS', 'FILTER', 'Default'):gsub('[_%-]', ' ')
local patchVersion = ac.getPatchVersionCode()

---@param value number
---@return number
local function scale(value) return math.floor(value * scaleRatio) end

---@param infoType string
---@return string|nil, string|nil, table|nil
local function buildCarInfo(infoType)
  if type(infoType) ~= 'string' then return nil end
  local carID = raceINI:get('RACE', 'MODEL', '')
  if not carName or not carDescription then
    local carData = JSON.parse(io.load(ac.getFolder(ac.FolderID.ContentCars) .. '/' .. carID .. '/ui/ui_car.json'))
    carName = carData.name
    local specs = carData.specs
    if specs then
      local acceleration = 'Unknown'
      if specs.acceleration then
        local time = specs.acceleration:match('([<>]?%d+%.%d+%s?s)')
        if time then acceleration = time end
      end
      carDescription = {
        { '• Power: ' .. (specs.bhp or 'N/A'), '• Torque: ' .. (specs.torque or 'N/A') },
        { '• Weight: ' .. (specs.weight or 'N/A'), '• P/W Ratio: ' .. (specs.pwratio or 'N/A') },
        { '• Top Speed: ' .. (specs.topspeed or 'N/A'), '• 0-100: ' .. acceleration }
      }
    else
      carDescription = string.reggsub(carData.description, [[\t|</?br\s*/?\s*>]], '\n')
    end
  end
  if infoType == 'name' then
    return carName
  elseif infoType == 'description' then
    return carDescription
  end
end

---@return string|nil
local function buildTrackInfo()
  if not trackDescription then
    local trackID = loading.trackID()
    local path = ac.getFolder(ac.FolderID.ContentTracks) .. '/' .. trackID .. '/ui/'
    local layoutID = loading.trackLayoutID()
    if layoutID ~= '' then path = path .. layoutID .. '/' end
    local description = JSON.parse(io.load(path .. 'ui_track.json')).description
    trackDescription = string.reggsub(description, [[\t|</?br\s*/?\s*>]], '\n')
  end
  return trackDescription
end

---@param hints string[]
---@param startIndex number?
---@return table
local function buildSessionInfo(hints, startIndex)
  local result = {}
  local function formatValue(value)
    local lower = value:lower()
    if lower == 'yes' or lower == 'allowed' then return 'Enabled' end
    if lower == 'no' or lower == 'not allowed' then return 'Disabled' end
    local number = tonumber(lower:match('(%d+)'))
    if number and lower:find('%%') then return number == 0 and 'Disabled' or (number .. '%') end
    return value:sub(1, 1):upper() .. value:sub(2)
  end
  local function formatParam(hint)
    if not hint then return '' end
    local label, value = hint:match('^([^:]+):%s*(.*)')
    label = label or hint
    value = value or ''
    label = label:gsub('%-', ' ')
    local words = {}
    for word in label:gmatch('%S+') do
      table.insert(words, word:sub(1, 1):upper() .. word:sub(2):lower())
      if #words == 2 then break end
    end
    label = table.concat(words, ' ')
    if value ~= '' then value = ': ' .. formatValue(value:match('^%s*(.-)%s*$') or value) end
    return label .. value
  end
  for i = startIndex or 1, #hints, 2 do
    table.insert(result, { '• ' .. formatParam(hints[i]), hints[i + 1] and ('• ' .. formatParam(hints[i + 1])) or '' })
  end
  return result
end

---@return table
local function buildGameInfo()
  if not gameInfoText then
    local version = loading.version()
    local acVersion, cspVersion = version:match('(.-)%s*&%s*(.*)')
    gameInfoText = {
      { '• ' .. (acVersion or version) },
      { '• ' .. (cspVersion or '') .. ' (' .. patchVersion .. ')' },
      { '• PP Filter: ' .. ppFilter },
      { '• WeatherFX: ' .. weatherfxImpl },
    }
  end
  return gameInfoText
end

---@return string
local function buildContentState()
  local title, details = loading.warning()
  return table.concat({
      title or '',
      #loading.serverHints(),
      loading.carName(),
      loading.trackName(),
      loading.version(),
      size.x },
    '|')
end

local function buildLayout()
  infoWidth = scale(1920 * 0.3)
  bgWidth = size.x - infoWidth
  infoX = infoSide:get() == 2 and (size.x - infoWidth) or (infoSide:get() == 1 and (size.x - infoWidth) / 2 or 0)
end

---@param icon ui.Icons
---@param iconPadding number
---@param title string
---@param details string|table
local function drawBlock(icon, iconPadding, title, details)
  ui.offsetCursorY(scale(15))
  ui.dummy(vec2(64, 64):scale(scaleRatio))
  local r1, r2 = ui.itemRect()
  ui.drawIcon(icon, r1 + scale(iconPadding), r2 - scale(iconPadding))
  ui.sameLine(0, scale(12))
  ui.pushDWriteFont('@System;Weight=Bold')
  local infoFontSize = scale(20)
  ui.dwriteTextWrapped(title, infoFontSize)
  local infoWrap = infoWidth - scale(76)
  local singleLineHeight = math.floor(ui.measureDWriteText('Singleline', infoFontSize, infoWrap).y)
  local totalTitleHeight = ui.measureDWriteText(title, infoFontSize, infoWrap).y
  local extraLines = math.min(2, (totalTitleHeight - singleLineHeight) / singleLineHeight)
  ui.popDWriteFont()
  ui.offsetCursorX(scale(64) + scale(12))
  ui.offsetCursorY(-math.ceil((scale(38) - (extraLines * singleLineHeight))))
  if type(details) == 'table' then
    local halfWidth = infoWrap / 2 + infoFontSize
    local startX = ui.getCursorX()
    for i = 1, #details do
      ui.setCursorX(startX)
      ui.dwriteText(details[i][1], scale(14))
      ui.sameLine(halfWidth, 0)
      ui.dwriteText(details[i][2], scale(14))
    end
  else
    ui.dwriteTextWrapped(details or 'No description.', scale(14))
  end
end

local function buildContent()
  local blocks = {}
  local title, details = loading.warning()
  if title then table.insert(blocks, { ui.Icons.Warning, scale(20), 'Warning', title .. '\n' .. details }) end
  local serverHints = loading.serverHints()
  local iconPadding = scale(8)
  if #serverHints > 0 then
    table.insert(blocks, { 'splashscreen::logo', iconPadding, raceINI:get('REMOTE', 'SERVER_NAME', ''), buildSessionInfo(serverHints, 2) })
  else
    table.insert(blocks, { 'splashscreen::logo', iconPadding, 'Singleplayer Session', buildGameInfo() })
  end
  table.insert(blocks, { 'splashscreen::badge', iconPadding, buildCarInfo('name'), buildCarInfo('description') })
  table.insert(blocks, { 'splashscreen::track', iconPadding, loading.trackName(), buildTrackInfo() })
  if #serverHints > 0 then
    table.insert(blocks, { 'splashscreen::logo', iconPadding, 'Game Information', buildGameInfo() })
  end
  for i = 1, #blocks do drawBlock(blocks[i][1], blocks[i][2], blocks[i][3], blocks[i][4]) end
end

---@return number
local function buildContentHeight()
  local emptyVec2 = vec2()
  ui.pushClipRect(emptyVec2, emptyVec2)
  ui.setCursor(emptyVec2)
  ui.beginGroup(infoWidth)
  buildContent()
  local height = ui.getCursorY()
  ui.endGroup()
  ui.popClipRect()
  return height
end

local function drawBackground()
  ui.drawImage('splashscreen::background', 0, size, ui.ImageFit.Fill)
  ui.beginTextureShade('splashscreen::background')
  ui.beginMIPBias()
  local startPos = vec2()
  if infoSide:get() == 2 then
    ui.drawRectFilledMultiColor(startPos, vec2(bgWidth, size.y), rgbm.colors.transparent, bgColor, bgColor, rgbm.colors.transparent)
    if size.x > bgWidth then ui.drawRectFilled(vec2(bgWidth, 0), size, bgColor) end
  elseif infoSide:get() == 0 then
    ui.drawRectFilledMultiColor(vec2(infoWidth, 0), vec2(size.x, size.y), bgColor, rgbm.colors.transparent, rgbm.colors.transparent, bgColor)
    if size.x > bgWidth then ui.drawRectFilled(startPos, vec2(infoWidth, size.y), bgColor) end
  elseif infoSide:get() == 1 then
    ui.drawRectFilled(vec2(infoX, 0), vec2(infoX + infoWidth, size.y), bgColor)
    ui.drawRectFilledMultiColor(startPos, vec2(infoX, size.y), rgbm.colors.transparent, bgColor, bgColor, rgbm.colors.transparent)
    ui.drawRectFilledMultiColor(vec2(infoX + infoWidth, 0), vec2(size.x, size.y), bgColor, rgbm.colors.transparent, rgbm.colors.transparent, bgColor)
  end
  ui.endTextureShade(startPos, size)
  ui.endMIPBias(8, true)
end

---@param status ui.ExtraCanvas
---@param dt number
local function drawLoadingBarSweep(status, dt)
  animTimer = animTimer + dt
  local sweepDuration, pauseDuration = 2.0, 0.5
  local cycleDuration = sweepDuration + pauseDuration
  local elapsed = animTimer % cycleDuration
  local showSweep = elapsed < sweepDuration

  if showSweep then
    local eased = (elapsed / sweepDuration)
    eased = eased * eased * (3 - 2 * eased)
    local progressWidth = status:size().x * loading.progress()
    local bandWidth = progressWidth / 2
    local sweepPosition = -bandWidth + eased * (progressWidth + bandWidth)

    local barY = size.y - status:size().y
    local bandStart = vec2(sweepPosition, barY)
    local bandEnd = vec2(sweepPosition + bandWidth, barY + status:size().y)

    ui.pushClipRect(vec2(0, barY), vec2(progressWidth + scale(1), size.y))
    ui.drawRectFilledMultiColor(bandStart, bandEnd, rgbm.colors.transparent, sweepColor, sweepColor, rgbm.colors.transparent)
    ui.popClipRect()
  end
end

---@param dt number
local function drawLoadingBar(dt)
  if not loadingStatus or loadingStatus:size().x ~= size.x then
    loadingStatus = ui.ExtraCanvas(vec2(size.x, scale(barHeight)))
  end
  loadingStatus:clear(rgbm.colors.black):update(function()
    local cursorStart = ui.getCursor()
    local fontSize = scale(16)
    ui.drawLoadingSpinner(cursorStart, cursorStart + vec2(20, 20):scale(scaleRatio))
    ui.offsetCursorX(scale(28))
    ui.offsetCursorY(scale(-1))
    ui.dwriteText(loading.status(), fontSize)
    ui.sameLine(0, scale(8))
    ui.dwriteText(loading.details(), fontSize, rgbm.colors.gray)
    local altText = "Hold ALT to move Info panel"
    local altFontSize = fontSize - scale(2)
    local altTextWidth = ui.measureDWriteText(altText, altFontSize).x + barHeight / 2
    ui.setCursor(vec2(size.x - altTextWidth, -scale(1)))
    ui.dwriteText(altText, altFontSize, rgbm.colors.gray)
  end)
  local barPosition = vec2(0, size.y - loadingStatus:size().y)
  local barSize = loadingStatus:size()
  ui.beginRotation()
  ui.drawImage(loadingStatus, barPosition, barPosition + barSize)
  ui.setShadingOffset(-1, 1, 1, 2)
  ui.drawImage(loadingStatus, barPosition, barPosition + barSize * vec2(loading.progress(), 1), rgbm.colors.white, vec2(), vec2(loading.progress(), 1), ui.ImageFit.Fill)
  ui.resetShadingOffset()
  drawLoadingBarSweep(loadingStatus, dt)
  ui.endRotation(90, 0)
end


---@param dt number
local function drawHoverRegions(dt)
  if not ac.isKeyDown(ui.KeyIndex.Menu) then return end
  local mouseDelta = ui.mouseDelta()
  hoverTimer = mouseDelta:length() > 0 and 2 or math.max(0, hoverTimer - dt)
  local thirdWidth = size.x / 3
  local hoveredThird = nil
  for i = 0, 2 do
    if i ~= infoSide:get() then
      local rectStart = vec2(i * thirdWidth, 0)
      local rectEnd = vec2((i + 1) * thirdWidth, size.y - barHeight)
      if ui.rectHovered(rectStart, rectEnd) then
        hoveredThird = i
        if infoStarted and ui.mouseClicked(ui.MouseButton.Left) then
          infoSide:set(i)
          buildLayout()
        end
      end
      fadeAlpha[i + 1] = fadeAlpha[i + 1] + ((hoveredThird == i and hoverTimer > 0 and 1 or 0) - fadeAlpha[i + 1]) * math.min(1, fadeSpeed * dt)
      if fadeAlpha[i + 1] > 0 then
        local visualWidth = infoWidth + scale(25)
        local visualX = i == 2 and (size.x - visualWidth) or (i == 1 and (size.x - visualWidth) / 2 or 0)
        local visualStart = vec2(visualX, 0)
        local visualEnd = vec2(visualX + visualWidth, size.y - barHeight)
        ui.drawRectFilled(visualStart, visualEnd, rgbm(1, 1, 1, 0.05 * fadeAlpha[i + 1]))
        ui.pushDWriteFont('@System;Weight=Bold')
        local text = 'Double Click to move'
        local textFontSize = scale(20)
        local textSize = ui.measureDWriteText(text, textFontSize)
        ui.dwriteDrawText(text, textFontSize, vec2(visualX + (infoWidth - textSize.x) / 2, (size.y - barHeight) / 2), rgbm(1, 1, 1, 0.33 * fadeAlpha[i + 1]))
        ui.popDWriteFont()
      end
    end
  end
  infoStarted = true
end

local function drawContent()
  local contentState = buildContentState()
  if not contentStateDone or contentState ~= lastContentState then
    contentCache[contentState] = buildContentHeight()
    lastContentState = contentState
    contentStateDone = true
  end
  local startY = math.max(scale(20), (size.y - contentCache[contentState]) / 2)
  ui.setCursor(vec2(infoX, startY))
  ui.beginGroup(infoWidth)
  buildContent()
  ui.endGroup()
end

---@param dt number
function script.update(dt)
  local newSize = ui.windowSize()
  if not size or size ~= newSize then
    size = newSize
    scaleRatio = size.y / 1080
    buildLayout()
    contentStateDone = false
  end
  drawBackground()
  drawLoadingBar(dt)
  drawContent()
  drawHoverRegions(dt)
end
