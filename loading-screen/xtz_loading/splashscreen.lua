local windowSize = vec2()
local scaleRatio = 1
local backgroundWidth = 0

local loadingBarAnimColor = rgbm(0, 0, 0, 0.33)
local loadingBarHeight = 20
local loadingBarAnimTimer = 0

local contentWidth = 0
local contentPosition = 0
local contentHeightCache = {}
local contentHeightCached = false
local contentSideStorage = ac.storage('contentSideStorage', 2)
local contentVisibleStorage = ac.storage('contentVisibleStorage', true)
local contentHoveredTimer = 0
local contentFadeSpeed = 10
local contentBlurColor = rgbm(0.5, 0.5, 0.5, 1)
local contentHoveredAlphas = { 0, 0, 0 }

local carInformation, carName, trackInformation, sessionInformation, gameInformation, loadingBarTexture, contentLastState

local raceINI = ac.INIConfig.raceConfig()
local weatherfxImpl = ac.INIConfig.load(ac.getFolder(ac.FolderID.ExtCfgUser) .. '\\weather_fx.ini'):get('BASIC', 'IMPLEMENTATION', 'Default')
local ppFilter = ac.INIConfig.load(ac.getFolder(ac.FolderID.Cfg) .. '\\video.ini'):get('POST_PROCESS', 'FILTER', 'Default'):gsub('[_%-]', ' ')
local cspVersionID = ac.getPatchVersionCode()
local carID = raceINI:get('RACE', 'MODEL', '')
local carData = JSON.parse(io.load(ac.getFolder(ac.FolderID.ContentCars) .. '/' .. carID .. '/ui/ui_car.json'))

local sessionTypeNames = {}
for k, v in pairs(ac.SessionType) do sessionTypeNames[v] = k end

local sessionTypeNumber = tonumber(raceINI:get('SESSION_0', 'TYPE', '-1'))
local sessionTypeName = (sessionTypeNumber == 0) and 'Session' or (sessionTypeNames[sessionTypeNumber] or 'Session')

---@param value number
---@return number
local function scale(value) return math.floor(value * scaleRatio) end

---@param infoType string
---@return string|table|nil
local function getCarInfo(infoType)
  if infoType == 'name' then
    if not carName then
      carName = carData.name
    end
    return carName
  elseif infoType == 'specs' then
    if not carInformation then
      local specs = carData.specs
      if specs then
        local acceleration = 'Unknown'
        if specs.acceleration then
          local time = specs.acceleration:match('([<>]?%d+%.%d+%s?s)')
          if time then acceleration = time end
        end
        carInformation = {
          { '• Power: ' .. (specs.bhp or 'N/A'), '• Torque: ' .. (specs.torque or 'N/A') },
          { '• Weight: ' .. (specs.weight or 'N/A'), '• P/W Ratio: ' .. (specs.pwratio or 'N/A') },
          { '• Top Speed: ' .. (specs.topspeed or 'N/A'), '• 0-100: ' .. acceleration }
        }
      else
        carInformation = string.reggsub(carData.description, [[\t|</?br\s*/?\s*>]], '\n')
      end
    end
    return carInformation
  end
end

---@return table|string
local function getTrackInfo()
  if not trackInformation then
    local trackID = loading.trackID()
    local path = ac.getFolder(ac.FolderID.ContentTracks) .. '/' .. trackID .. '/ui/'
    local layoutID = loading.trackLayoutID()
    if layoutID ~= '' then path = path .. layoutID .. '/' end
    local trackData = JSON.parse(io.load(path .. 'ui_track.json')) or {}
    local description = string.reggsub(trackData.description or '', [[\t|</?br\s*/?\s*>]], '\n')
    local function formatTrackLength(v)
      if not v then return 'Unknown' end
      v = v:lower():gsub('%s+', '')
      local num, unit = v:match('([%d%.]+)(%a*)')
      num = tonumber(num)
      if not num then return 'Unknown' end
      if unit == 'm' or (unit == '' and num > 1000) then
        num = num / 1000
      end
      return string.format('%.3g km', num)
    end
    local length = formatTrackLength(trackData.length)
    local pitboxes = trackData.pitboxes or 'Unknown'
    local country = trackData.country or 'Unknown'
    local city = trackData.city or 'Unknown'
    trackInformation = {
      { '• Country: ' .. country, '• City: ' .. city },
      { '• Length: ' .. length, '• Pitboxes: ' .. pitboxes },
      description ~= '' and ('\n' .. description) or ''
    }
  end
  return trackInformation
end

---@param hints string[]
---@param startIndex number?
---@return table
local function getSessionInfo(hints, startIndex)
  if not sessionInformation then
    sessionInformation = {}
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
      local param, value = hint:match('^([^:]+):%s*(.*)')
      param = param or hint
      value = value or ''
      param = param:gsub('%-', ' ')
      local words = {}
      for word in param:gmatch('%S+') do
        table.insert(words, word:sub(1, 1):upper() .. word:sub(2):lower())
        if #words == 2 then break end
      end
      param = table.concat(words, ' ')
      if value ~= '' then value = ': ' .. formatValue(value:match('^%s*(.-)%s*$') or value) end
      return param .. value
    end
    for i = startIndex or 1, #hints, 2 do
      table.insert(sessionInformation, { '• ' .. formatParam(hints[i]), hints[i + 1] and ('• ' .. formatParam(hints[i + 1])) or '' })
    end
  end
  return sessionInformation
end

---@return table
local function getGameInfo()
  if not gameInformation then
    local acVersion, cspVersion = loading.version():match('(.-)%s*&%s*(.*)')
    gameInformation = {
      { '• ' .. acVersion },
      { '• ' .. cspVersion .. ' (' .. cspVersionID .. ')' },
      { '• PP Filter: ' .. ppFilter },
      { '• WeatherFX: ' .. weatherfxImpl },
    }
  end
  return gameInformation
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
      windowSize.x },
    '|')
end

local function buildLayout()
  contentWidth = scale(1920 * 0.3)
  backgroundWidth = windowSize.x - contentWidth
  contentPosition = contentSideStorage:get() == 2 and (windowSize.x - contentWidth) or (contentSideStorage:get() == 1 and (windowSize.x - contentWidth) / 2 or 0)
end

---@param icon ui.Icons
---@param iconPadding number
---@param blockTitle string
---@param blockDetails string|table
local function drawBlock(icon, iconPadding, blockTitle, blockDetails)
  ui.offsetCursorY(scale(15))
  ui.dummy(vec2(64, 64):scale(scaleRatio))
  local iconStartPos, iconEndPos = ui.itemRect()
  ui.drawIcon(icon, iconStartPos + scale(iconPadding), iconEndPos - scale(iconPadding))
  ui.sameLine(0, scale(12))
  ui.pushDWriteFont('@System;Weight=Bold')
  local contentFontSize = scale(20)
  ui.dwriteTextWrapped(blockTitle, contentFontSize)
  local contentWrap = contentWidth - scale(76)
  local singleLineHeight = math.floor(ui.measureDWriteText('Singleline', contentFontSize, contentWrap).y)
  local totalTitleHeight = ui.measureDWriteText(blockTitle, contentFontSize, contentWrap).y
  local extraLines = math.min(2, (totalTitleHeight - singleLineHeight) / singleLineHeight)
  ui.popDWriteFont()
  ui.offsetCursorX(scale(64) + scale(12))
  ui.offsetCursorY(-math.ceil((scale(38) - (extraLines * singleLineHeight))))
  if type(blockDetails) == 'table' then
    local contentHalfWidth = contentWrap / 2 + contentFontSize
    local detailsStartPos = ui.getCursorX()
    for i = 1, #blockDetails do
      local entry = blockDetails[i]
      if type(entry) == 'table' then
        ui.setCursorX(detailsStartPos)
        ui.dwriteText(entry[1], scale(14))
        ui.sameLine(contentHalfWidth, 0)
        ui.dwriteText(entry[2], scale(14))
      else
        ui.setCursorX(detailsStartPos)
        ui.dwriteTextWrapped(entry, scale(14))
      end
    end
  else
    ui.dwriteTextWrapped(blockDetails or 'No description.', scale(14))
  end
end

local function buildContent()
  local blocks = {}
  local warningTitle, warningDetails = loading.warning()
  if warningTitle then table.insert(blocks, { ui.Icons.Warning, scale(20), 'Warning', warningTitle .. '\n' .. warningDetails }) end
  local serverHints = loading.serverHints()
  local iconPadding = scale(8)
  if #serverHints > 0 then
    table.insert(blocks, { 'splashscreen::logo', iconPadding, raceINI:get('REMOTE', 'SERVER_NAME', ''), getSessionInfo(serverHints, 2) })
  else
    table.insert(blocks, { 'splashscreen::logo', iconPadding, 'Singleplayer ' .. sessionTypeName, getGameInfo() })
  end
  table.insert(blocks, { 'splashscreen::badge', iconPadding, getCarInfo('name'), getCarInfo('specs') })
  table.insert(blocks, { 'splashscreen::track', iconPadding, loading.trackName(), getTrackInfo() })
  if #serverHints > 0 then
    table.insert(blocks, { 'splashscreen::logo', iconPadding, 'Game Information', getGameInfo() })
  end
  for i = 1, #blocks do drawBlock(blocks[i][1], blocks[i][2], blocks[i][3], blocks[i][4]) end
end

---@return number
local function buildContentHeight()
  local zeroPos = vec2()
  ui.pushClipRect(zeroPos, zeroPos)
  ui.setCursor(zeroPos)
  ui.beginGroup(contentWidth)
  buildContent()
  local contentHeight = ui.getCursorY()
  ui.endGroup()
  ui.popClipRect()
  return contentHeight
end

local function drawBackground()
  ui.drawImage('splashscreen::background', 0, windowSize, ui.ImageFit.Fill)
  if contentVisibleStorage:get() and ui.isImageReady('splashscreen::background') then
    ui.beginTextureShade('splashscreen::background')
    ui.beginMIPBias()
    local zeroPos = vec2()
    local contentSide = contentSideStorage:get()
    if contentSide == 2 then
      ui.drawRectFilledMultiColor(zeroPos, vec2(backgroundWidth, windowSize.y), rgbm.colors.transparent, contentBlurColor, contentBlurColor, rgbm.colors.transparent)
      if windowSize.x > backgroundWidth then ui.drawRectFilled(vec2(backgroundWidth, 0), windowSize, contentBlurColor) end
    elseif contentSide == 0 then
      ui.drawRectFilledMultiColor(vec2(contentWidth, 0), vec2(windowSize.x, windowSize.y), contentBlurColor, rgbm.colors.transparent, rgbm.colors.transparent, contentBlurColor)
      if windowSize.x > backgroundWidth then ui.drawRectFilled(zeroPos, vec2(contentWidth, windowSize.y), contentBlurColor) end
    elseif contentSide == 1 then
      ui.drawRectFilled(vec2(contentPosition, 0), vec2(contentPosition + contentWidth, windowSize.y), contentBlurColor)
      ui.drawRectFilledMultiColor(zeroPos, vec2(contentPosition, windowSize.y), rgbm.colors.transparent, contentBlurColor, contentBlurColor, rgbm.colors.transparent)
      ui.drawRectFilledMultiColor(vec2(contentPosition + contentWidth, 0), vec2(windowSize.x, windowSize.y), contentBlurColor, rgbm.colors.transparent, rgbm.colors.transparent, contentBlurColor)
    end
    ui.endTextureShade(zeroPos, windowSize)
    ui.endMIPBias(6, true)
  end
end

---@param status ui.ExtraCanvas
---@param dt number
local function drawLoadingBarSweep(status, dt)
  loadingBarAnimTimer = loadingBarAnimTimer + dt
  local sweepDuration, pauseDuration = 2.0, 0.5
  local cycleDuration = sweepDuration + pauseDuration
  local cycleElapsed = loadingBarAnimTimer % cycleDuration
  local showSweepBand = cycleElapsed < sweepDuration
  if showSweepBand then
    local easedProgress = (cycleElapsed / sweepDuration)
    easedProgress = easedProgress * easedProgress * (3 - 2 * easedProgress)
    local progressWidth = status:size().x * loading.progress()
    local sweepBandWidth = progressWidth / 2
    local sweepBandPosition = -sweepBandWidth + easedProgress * (progressWidth + sweepBandWidth)
    local loadingBarY = windowSize.y - status:size().y
    local sweepBandStart = vec2(sweepBandPosition, loadingBarY)
    local sweepBandEnd = vec2(sweepBandPosition + sweepBandWidth, loadingBarY + status:size().y)
    ui.pushClipRect(vec2(0, loadingBarY), vec2(progressWidth + scale(1), windowSize.y))
    ui.drawRectFilledMultiColor(sweepBandStart, sweepBandEnd, rgbm.colors.transparent, loadingBarAnimColor, loadingBarAnimColor, rgbm.colors.transparent)
    ui.popClipRect()
  end
end

---@param dt number
local function drawLoadingBar(dt)
  if not loadingBarTexture or loadingBarTexture:size().x ~= windowSize.x then
    loadingBarTexture = ui.ExtraCanvas(vec2(windowSize.x, scale(loadingBarHeight)))
  end
  loadingBarTexture:clear(rgbm.colors.black):update(function()
    local loadingBarStartPos = ui.getCursor()
    local loadingBarFontSize = scale(16)
    ui.drawLoadingSpinner(loadingBarStartPos, loadingBarStartPos + vec2(20, 20):scale(scaleRatio))
    ui.offsetCursorX(scale(28))
    ui.offsetCursorY(scale(-1))
    ui.dwriteText(loading.status(), loadingBarFontSize)
    ui.sameLine(0, scale(8))
    ui.dwriteText(loading.details(), loadingBarFontSize, rgbm.colors.gray)
    local loadingBarAltText = "Hold ALT to adjust"
    local loadingBarAltFontSize = loadingBarFontSize - scale(2)
    local loadingBarAltWidth = ui.measureDWriteText(loadingBarAltText, loadingBarAltFontSize).x + loadingBarHeight / 2
    ui.setCursor(vec2(windowSize.x - loadingBarAltWidth, -scale(1)))
    ui.dwriteText(loadingBarAltText, loadingBarAltFontSize, rgbm.colors.gray)
  end)
  local loadingBarPosition = vec2(0, windowSize.y - loadingBarTexture:size().y)
  local loadingBarSize = loadingBarTexture:size()
  ui.beginRotation()
  ui.drawImage(loadingBarTexture, loadingBarPosition, loadingBarPosition + loadingBarSize)
  ui.setShadingOffset(-1, 1, 1, 2)
  ui.drawImage(loadingBarTexture, loadingBarPosition, loadingBarPosition + loadingBarSize * vec2(loading.progress(), 1), rgbm.colors.white, vec2(), vec2(loading.progress(), 1), ui.ImageFit.Fill)
  ui.resetShadingOffset()
  drawLoadingBarSweep(loadingBarTexture, dt)
  ui.endRotation(90, 0)
end

---@param dt number
local function drawHoverRegions(dt)
  local altHeld = ac.isKeyDown(ui.KeyIndex.Menu)
  local regionFadeAmount = math.min(1, contentFadeSpeed * dt)
  if altHeld then
    contentHoveredTimer = ui.mouseDelta():length() > 0 and 2 or math.max(0, contentHoveredTimer - dt)
  else
    if contentHoveredTimer > 0 then contentHoveredTimer = math.max(0, contentHoveredTimer - dt) end
  end
  if not altHeld then
    local regionsAllHidden = true
    for i = 1, 3 do
      local regionAlpha = contentHoveredAlphas[i]
      regionAlpha = regionAlpha + (0 - regionAlpha) * regionFadeAmount
      contentHoveredAlphas[i] = regionAlpha
      if regionAlpha > 0.001 then regionsAllHidden = false end
    end
    if regionsAllHidden then return end
  end
  local regionWidth = windowSize.x / 3
  local regionsBottom = windowSize.y - loadingBarHeight
  local contentSide = contentSideStorage:get()
  local contentVisible = contentVisibleStorage:get()
  local hoveredRegionIndex
  if altHeld then
    for i = 0, 2 do
      local startX, endX = i * regionWidth, (i + 1) * regionWidth
      if ui.rectHovered(vec2(startX, 0), vec2(endX, regionsBottom)) then
        hoveredRegionIndex = i
        if ui.mouseClicked(ui.MouseButton.Left) then
          if i == contentSide then
            contentVisibleStorage:set(not contentVisible)
          else
            contentSideStorage:set(i)
            if not contentVisible then contentVisibleStorage:set(true) end
            buildLayout()
          end
          contentHeightCached = false
        end
      end
    end
  end
  for i = 0, 2 do
    local targetAlpha = (hoveredRegionIndex == i and contentHoveredTimer > 0 and 1 or 0)
    local regionAlpha = contentHoveredAlphas[i + 1] + (targetAlpha - contentHoveredAlphas[i + 1]) * regionFadeAmount
    contentHoveredAlphas[i + 1] = regionAlpha
    if regionAlpha <= 0.001 then goto continue end
    local visualWidth = contentWidth + scale(25)
    local visualX = (i == 2 and (windowSize.x - visualWidth)) or (i == 1 and (windowSize.x - visualWidth) / 2 or 0)
    local startPos, endPos = vec2(visualX, 0), vec2(visualX + visualWidth, regionsBottom)
    local text = 'Double Click to '
    local color
    if i == contentSide and contentVisible then
      color, text = rgbm(0, 0, 0, 0.5 * regionAlpha), text .. 'hide'
    elseif contentVisible then
      color, text = rgbm(1, 1, 1, 0.05 * regionAlpha), text .. 'move'
    else
      color, text = rgbm(1, 1, 1, 0.05 * regionAlpha), text .. 'show'
    end
    ui.drawRectFilled(startPos, endPos, color)
    ui.pushDWriteFont('@System;Weight=Bold')
    local fontSize = scale(20)
    local textSize = ui.measureDWriteText(text, fontSize)
    ui.dwriteDrawText(text, fontSize, vec2(visualX + (contentWidth - textSize.x) / 2, regionsBottom / 2), rgbm(1, 1, 1, 0.9 * regionAlpha))
    ui.popDWriteFont()
    ::continue::
  end
end

local function drawContent()
  if not contentVisibleStorage:get() then return end
  local contentState = buildContentState()
  if not contentHeightCached or contentState ~= contentLastState then
    contentHeightCache[contentState] = buildContentHeight()
    contentLastState = contentState
    contentHeightCached = true
  end
  local startY = math.max(scale(20), (windowSize.y - contentHeightCache[contentState]) / 2)
  ui.setCursor(vec2(contentPosition, startY))
  ui.beginGroup(contentWidth)
  buildContent()
  ui.endGroup()
end

---@param dt number
function script.update(dt)
  local currentWindowSize = ui.windowSize()
  if not windowSize or windowSize ~= currentWindowSize then
    windowSize = currentWindowSize
    scaleRatio = windowSize.y / 1080
    buildLayout()
    contentHeightCached = false
  end
  drawBackground()
  drawLoadingBar(dt)
  drawContent()
  drawHoverRegions(dt)
end
