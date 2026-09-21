local windowSize = vec2()
local scaleRatio = 1
local backgroundWidth = 0

local loadingBarAnimColor = rgbm(0, 0, 0, 0.33)
local loadingBarHeight = 20
local loadingBarAnimTimer = 0

local contentWidth = 0
local contentPosition = 0
local contentTargetPosition = 0
local contentHeightCache = 0
local contentHeightCached = false
local contentSideStorage = ac.storage('contentSideStorage', 2)
local contentVisibleStorage = ac.storage('contentVisibleStorage', true)
local contentFadeSpeed = 8
local contentFadeAmount = 0
local contentBlurColor = rgbm(0.5, 0.5, 0.5, 1)
local contentHoveredAlphas = { 0, 0, 0 }
local contentVisibleAlpha = 1
local contentSizeScale = 1
local contentPadding = 10

local carInformation, carName, trackInformation, sessionInformation, gameInformation, loadingBarTexture, contentLastState

local raceINI = ac.INIConfig.raceConfig()
local weatherfxImpl = ac.INIConfig.load(ac.getFolder(ac.FolderID.ExtCfgUser) .. '\\weather_fx.ini'):get('BASIC', 'IMPLEMENTATION', 'Default')
local ppFilter = ac.INIConfig.load(ac.getFolder(ac.FolderID.Cfg) .. '\\video.ini'):get('POST_PROCESS', 'FILTER', 'Default'):gsub('[_%-]', ' ')
local cspVersionID = ac.getPatchVersionCode()
local carID = raceINI:get('RACE', 'MODEL', '')
local carData = JSON.parse(io.load(ac.getFolder(ac.FolderID.ContentCars) .. '/' .. carID .. '/ui/ui_car.json')) or {}
local sessionTypeNames = {}
for k, v in pairs(ac.SessionType) do
  sessionTypeNames[v] = k
end

local sessionTypeNumber = tonumber(raceINI:get('SESSION_0', 'TYPE', '-1'))
local sessionTypeName = 'Singleplayer ' .. ((sessionTypeNumber == 0) and 'Session' or (sessionTypeNames[sessionTypeNumber] or 'Session'))
local sessionTypeReplay = tonumber(raceINI:get('REPLAY', 'ACTIVE', '0')) == 1

---@param value number
---@return number
local function scale(value) return math.ceil(value * scaleRatio) end

---@param value number
---@return number
local function contentScale(value) return math.ceil(value * scaleRatio * contentSizeScale) end

---@param v vec2
---@return vec2
local function ceilVec2(v) return vec2(math.ceil(v.x), math.ceil(v.y)) end

local htmlCodes = {
  ['&quot;'] = '"',
  ['&apos;'] = "'",
  ['&lt;'] = '<',
  ['&gt;'] = '>',
  ['&amp;'] = '&',
  ['&nbsp;'] = ' ',
  ['&copy;'] = '©',
  ['&reg;'] = '®',
  ['&trade;'] = '™',
  ['&euro;'] = '€',
  ['&pound;'] = '£',
  ['&yen;'] = '¥',
  ['&cent;'] = '¢',
  ['&deg;'] = '°',
  ['&plusmn;'] = '±',
  ['&times;'] = '×',
  ['&divide;'] = '÷',
  ['&ndash;'] = '–',
  ['&mdash;'] = '—',
  ['&lsquo;'] = "'",
  ['&rsquo;'] = "'",
  ['&ldquo;'] = '"',
  ['&rdquo;'] = '"',
  ['&hellip;'] = '…',
  ['&bull;'] = '•',
  ['&middot;'] = '·',
}

---@param n integer
---@return string
local function codepointToUTF8(n)
  if n < 0x80 then return string.char(n) end
  if n < 0x800 then return string.char(0xC0 + math.floor(n / 0x40), 0x80 + n % 0x40) end
  if n < 0x10000 then return string.char(0xE0 + math.floor(n / 0x1000), 0x80 + math.floor(n / 0x40) % 0x40, 0x80 + n % 0x40) end
  if n <= 0x10FFFF then return string.char(0xF0 + math.floor(n / 0x40000), 0x80 + math.floor(n / 0x1000) % 0x40, 0x80 + math.floor(n / 0x40) % 0x40, 0x80 + n % 0x40) end
  return ''
end

local function decodeHTML(str)
  return (
    string
      .reggsub(str, [[\t|</?br\s*/?\s*>]], '\n')
      :gsub('&#[xX](%x+);', function(n)
        return codepointToUTF8(tonumber(n, 16) --[[@as integer]])
      end)
      :gsub('&#(%d+);', function(n)
        return codepointToUTF8(tonumber(n) --[[@as integer]])
      end)
      :gsub('&[^;]+;', htmlCodes)
  )
end

---@param infoType string
---@return string|table|nil
local function getCarInfo(infoType)
  if infoType == 'name' then
    if not carName then carName = carData.name or loading.carName() end
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
          { '• Top Speed: ' .. (specs.topspeed or 'N/A'), '• 0-100: ' .. acceleration },
        }
      else
        carInformation = decodeHTML(carData.description or 'No description.')
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
    description = decodeHTML(description)
    local function formatTrackLength(v)
      if not v then return 'Unknown' end
      v = v:lower():gsub('%s+', '')
      local num, unit = v:match('([%d%.]+)(%a*)')
      num = tonumber(num)
      if not num then return 'Unknown' end
      if unit == 'm' or (unit == '' and num > 1000) then num = num / 1000 end
      return string.format('%.3g km', num)
    end
    local length = formatTrackLength(trackData.length)
    local pitboxes = trackData.pitboxes or 'Unknown'
    local country = trackData.country or 'Unknown'
    local city = trackData.city or 'Unknown'
    trackInformation = {
      { '• Country: ' .. country, '• City: ' .. city },
      { '• Length: ' .. length, '• Pitboxes: ' .. pitboxes },
      description ~= '' and ('\n' .. description) or '',
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
      if param:lower() ~= 'abs' then
        local words = {}
        for word in param:gmatch('%S+') do
          table.insert(words, word:sub(1, 1):upper() .. word:sub(2):lower())
          if #words == 2 then break end
        end
        param = table.concat(words, ' ')
      end
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
    local version = loading.version()
    local acVersion, cspVersion = version:match('(.-)%s*&%s*(.*)')
    gameInformation = { { '• ' .. (acVersion or version) } }
    if cspVersion then table.insert(gameInformation, { '• ' .. cspVersion .. ' (' .. cspVersionID .. ')' }) end
    table.insert(gameInformation, { '• PP Filter: ' .. ppFilter })
    table.insert(gameInformation, { '• WeatherFX: ' .. weatherfxImpl })
  end
  return gameInformation
end

---@return string
local function buildContentState()
  local title, details = loading.warning()
  local serverHints = loading.serverHints()
  return table.concat({
    title or '',
    details or '',
    table.concat(serverHints, '\31'),
    loading.carName(),
    loading.trackName(),
    loading.version(),
    windowSize.x,
    windowSize.y,
  }, '|')
end

local function buildLayout()
  local rawContentWidth = 1920 * 0.3 * scaleRatio
  local contentSide = contentSideStorage:get()
  local rawLeft
  local rawRight

  if contentSide == 2 then
    rawLeft = windowSize.x - rawContentWidth
    rawRight = windowSize.x
  elseif contentSide == 1 then
    rawLeft = (windowSize.x - rawContentWidth) / 2
    rawRight = rawLeft + rawContentWidth
  else
    rawLeft = 0
    rawRight = rawContentWidth
  end

  local left = math.ceil(rawLeft)
  local right = math.ceil(rawRight)
  contentWidth = right - left
  contentTargetPosition = left
  backgroundWidth = windowSize.x - contentWidth

  if contentPosition == 0 then contentPosition = contentTargetPosition end
end

---@param icon ui.Icons
---@param blockTitle string
---@param blockDetails string|table
local function drawBlock(icon, blockTitle, blockDetails)
  ui.offsetCursorY(contentScale(15))
  local blockStartY = ui.getCursorY()
  local iconSize = contentScale(64)
  local iconStartPos = vec2(ui.getCursorX(), blockStartY)
  local iconEndPos = vec2(iconStartPos.x + iconSize, iconStartPos.y + iconSize)
  ui.dummy(vec2(iconSize, iconSize))
  ui.drawIcon(icon, ceilVec2(iconStartPos), ceilVec2(iconEndPos))
  ui.sameLine(0, contentScale(12))
  local titleStartX = ui.getCursorX()
  local titleStartY = ui.getCursorY()
  ui.pushDWriteFont('@System;Weight=Bold')
  local contentTitleFontSize = contentScale(20)
  local contentDetailsFontSize = contentScale(14)
  local contentWrap = contentWidth - scale(contentPadding * 2) - contentScale(76)
  ui.dwriteTextWrapped(blockTitle, contentTitleFontSize)
  local titleHeight = math.ceil(ui.measureDWriteText(blockTitle, contentTitleFontSize, contentWrap).y)
  ui.popDWriteFont()
  local detailsStartX = math.ceil(titleStartX)
  local detailsStartY = math.ceil(titleStartY + titleHeight + contentScale(6))
  ui.setCursorX(detailsStartX)
  ui.setCursorY(detailsStartY)

  if type(blockDetails) == 'table' then
    local contentHalfWidth = math.ceil(contentWrap / 2 + contentTitleFontSize)
    for i = 1, #blockDetails do
      local entry = blockDetails[i]
      if type(entry) == 'table' then
        ui.setCursorX(detailsStartX)
        ui.dwriteText(entry[1], contentDetailsFontSize)
        if entry[2] then
          ui.sameLine(contentHalfWidth, 0)
          ui.dwriteText(entry[2], contentDetailsFontSize)
        end
      else
        ui.setCursorX(detailsStartX)
        ui.dwriteTextWrapped(entry, contentDetailsFontSize)
      end
    end
  else
    ui.dwriteTextWrapped(blockDetails or 'No description.', contentDetailsFontSize)
  end

  local contentEndY = math.ceil(ui.getCursorY())
  local iconEndY = math.ceil(blockStartY + iconSize)
  ui.setCursorY(math.max(contentEndY, iconEndY))
end

local function buildContent()
  local blocks = {}
  local warningTitle, warningDetails = loading.warning()
  if warningTitle then table.insert(blocks, { ui.Icons.Warning, 'Warning', warningTitle .. '\n' .. (warningDetails or '') }) end
  local serverHints = loading.serverHints()
  if #serverHints > 0 then
    table.insert(blocks, { 'splashscreen::logo', raceINI:get('REMOTE', 'SERVER_NAME', ''), getSessionInfo(serverHints, 2) })
  else
    table.insert(blocks, { 'splashscreen::logo', sessionTypeReplay and 'Loading Replay' or sessionTypeName, getGameInfo() })
  end
  table.insert(blocks, { 'splashscreen::badge', getCarInfo('name'), getCarInfo('specs') })
  table.insert(blocks, { 'splashscreen::track', loading.trackName(), getTrackInfo() })
  if #serverHints > 0 then table.insert(blocks, { 'splashscreen::logo', 'Game Information', getGameInfo() }) end
  for i = 1, #blocks do
    drawBlock(blocks[i][1], blocks[i][2], blocks[i][3])
  end
end

---@return number
local function buildContentHeight()
  local zeroPos = vec2()
  ui.pushClipRect(zeroPos, zeroPos)
  ui.setCursor(zeroPos)
  ui.beginGroup(contentWidth - scale(contentPadding * 2))
  buildContent()
  local contentHeight = math.ceil(ui.getCursorY())
  ui.endGroup()
  ui.popClipRect()
  return contentHeight
end

local function calculateContentScale()
  contentSizeScale = 1
  local maxHeight = windowSize.y - scale(40)
  local contentHeight = buildContentHeight()

  if contentHeight > maxHeight then
    contentSizeScale = maxHeight / contentHeight
    contentHeight = buildContentHeight()

    if contentHeight > maxHeight then contentSizeScale = contentSizeScale * maxHeight / contentHeight end
  end
end

local function drawBackground()
  ui.drawImage('splashscreen::background', 0, windowSize, ui.ImageFit.Fill)

  if contentVisibleAlpha > 0 and ui.isImageReady('splashscreen::background') then
    ui.pushStyleVar(ui.StyleVar.Alpha, contentVisibleAlpha)
    ui.beginTextureShade('splashscreen::background')
    ui.beginMIPBias()

    local zeroPos = vec2()
    local contentSide = contentSideStorage:get()

    if contentSide == 2 then
      local contentStartX = backgroundWidth
      local contentEndX = windowSize.x
      ui.drawRectFilledMultiColor(zeroPos, vec2(math.ceil(contentStartX), math.ceil(windowSize.y)), rgbm.colors.transparent, contentBlurColor, contentBlurColor, rgbm.colors.transparent)
      if windowSize.x > contentStartX then ui.drawRectFilled(vec2(math.ceil(contentStartX), 0), vec2(math.ceil(contentEndX), math.ceil(windowSize.y)), contentBlurColor) end
    elseif contentSide == 0 then
      local contentStartX = 0
      local contentEndX = contentWidth
      ui.drawRectFilledMultiColor(vec2(math.ceil(contentStartX), 0), vec2(math.ceil(windowSize.x), math.ceil(windowSize.y)), contentBlurColor, rgbm.colors.transparent, rgbm.colors.transparent, contentBlurColor)
      if windowSize.x > contentEndX then ui.drawRectFilled(vec2(math.ceil(contentStartX), 0), vec2(math.ceil(contentEndX), math.ceil(windowSize.y)), contentBlurColor) end
    elseif contentSide == 1 then
      local contentStartX = contentPosition
      local contentEndX = contentPosition + contentWidth
      ui.drawRectFilled(vec2(math.ceil(contentStartX), 0), vec2(math.ceil(contentEndX), math.ceil(windowSize.y)), contentBlurColor)
      ui.drawRectFilledMultiColor(zeroPos, vec2(math.ceil(contentStartX), math.ceil(windowSize.y)), rgbm.colors.transparent, contentBlurColor, contentBlurColor, rgbm.colors.transparent)
      ui.drawRectFilledMultiColor(vec2(math.ceil(contentEndX), 0), vec2(math.ceil(windowSize.x), math.ceil(windowSize.y)), contentBlurColor, rgbm.colors.transparent, rgbm.colors.transparent, contentBlurColor)
    end

    ui.endTextureShade(zeroPos, windowSize)
    ui.endMIPBias(6, true)
    ui.popStyleVar()
  end
end

---@param loadingBarSatus ui.ExtraCanvas
---@param dt number
local function drawLoadingBarSweep(loadingBarSatus, dt)
  loadingBarAnimTimer = loadingBarAnimTimer + dt
  local sweepDuration, pauseDuration = 2.0, 0.5
  local cycleDuration = sweepDuration + pauseDuration
  local cycleElapsed = loadingBarAnimTimer % cycleDuration
  local showSweepBand = cycleElapsed < sweepDuration

  if showSweepBand then
    local easedProgress = cycleElapsed / sweepDuration
    easedProgress = easedProgress * easedProgress * (3 - 2 * easedProgress)
    local progressWidth = math.ceil(loadingBarSatus:size().x * loading.progress())
    local sweepBandWidth = math.ceil(progressWidth / 2)
    local sweepBandPosition = math.ceil(-sweepBandWidth + easedProgress * (progressWidth + sweepBandWidth))
    local loadingBarStartY = math.ceil(windowSize.y - loadingBarSatus:size().y)
    local sweepBandStart = vec2(math.ceil(sweepBandPosition), loadingBarStartY)
    local sweepBandEnd = vec2(math.ceil(sweepBandPosition + sweepBandWidth), math.ceil(loadingBarStartY + loadingBarSatus:size().y))

    ui.pushClipRect(vec2(0, loadingBarStartY), vec2(math.ceil(progressWidth + scale(1)), math.ceil(windowSize.y)))
    ui.drawRectFilledMultiColor(sweepBandStart, sweepBandEnd, rgbm.colors.transparent, loadingBarAnimColor, loadingBarAnimColor, rgbm.colors.transparent)
    ui.popClipRect()
  end
end

---@param dt number
local function drawLoadingBar(dt)
  local loadingBarWidth = math.ceil(windowSize.x)
  local loadingBarSize = vec2(loadingBarWidth, scale(loadingBarHeight))

  if not loadingBarTexture or loadingBarTexture:size().x ~= loadingBarWidth or loadingBarTexture:size().y ~= loadingBarSize.y then loadingBarTexture = ui.ExtraCanvas(ceilVec2(loadingBarSize)) end

  loadingBarTexture:clear(rgbm.colors.black):update(function()
    local loadingBarStartPos = ceilVec2(ui.getCursor())
    local loadingBarFontSize = scale(16)

    ui.drawLoadingSpinner(loadingBarStartPos, vec2(math.ceil(20 * scaleRatio), math.ceil(20 * scaleRatio)))

    ui.offsetCursorX(scale(28))
    ui.offsetCursorY(-scale(2))

    local status = loading.status()
    local textStart = ceilVec2(ui.getCursor())
    ui.dwriteText(status, loadingBarFontSize)

    local statusWidth = math.ceil(ui.measureDWriteText(status, loadingBarFontSize).x)

    ui.setCursor(vec2(math.ceil(textStart.x + statusWidth + scale(8)), math.ceil(textStart.y)))

    ui.dwriteText(loading.details(), loadingBarFontSize, rgbm.colors.gray)

    local loadingBarAltText = 'Hold ALT to adjust'
    local loadingBarAltFontSize = scale(16) - scale(2)
    local loadingBarAltWidth = math.ceil(ui.measureDWriteText(loadingBarAltText, loadingBarAltFontSize).x + loadingBarHeight / 2)
    local loadingBarAltStartX = math.ceil(windowSize.x - loadingBarAltWidth)

    ui.setCursor(vec2(loadingBarAltStartX, -scale(1)))

    ui.dwriteText(loadingBarAltText, loadingBarAltFontSize, rgbm.colors.gray)
  end)

  local loadingBarPosition = vec2(0, math.ceil(windowSize.y - loadingBarTexture:size().y))
  local loadingBarActualSize = loadingBarTexture:size()

  ui.beginRotation()

  ui.drawImage(loadingBarTexture, loadingBarPosition, vec2(math.ceil(loadingBarPosition.x + loadingBarActualSize.x), math.ceil(loadingBarPosition.y + loadingBarActualSize.y)))

  ui.setShadingOffset(-1, 1, 1, 2)

  local progress = loading.progress()
  local progressEndX = math.ceil(loadingBarPosition.x + loadingBarActualSize.x * progress)

  ui.drawImage(loadingBarTexture, loadingBarPosition, vec2(progressEndX, math.ceil(loadingBarPosition.y + loadingBarActualSize.y)), rgbm.colors.white, vec2(), vec2(progress, 1), ui.ImageFit.Fill)

  ui.resetShadingOffset()
  drawLoadingBarSweep(loadingBarTexture, dt)
  ui.endRotation(90, 0)
end

local function drawHoverRegions()
  local altHeld = ac.isKeyDown(ui.KeyIndex.Menu)

  if not altHeld then
    local regionsAllHidden = true

    for i = 1, 3 do
      local regionAlpha = contentHoveredAlphas[i]
      regionAlpha = regionAlpha + (0 - regionAlpha) * contentFadeAmount
      contentHoveredAlphas[i] = regionAlpha
      if regionAlpha > 0 then regionsAllHidden = false end
    end

    if regionsAllHidden then return end
  end

  local regionWidth = windowSize.x / 3
  local regionsBottom = windowSize.y - scale(loadingBarHeight)
  local contentSide = contentSideStorage:get()
  local contentVisible = contentVisibleStorage:get()
  local hoveredRegionIndex

  if altHeld then
    for i = 0, 2 do
      local startX = i * regionWidth
      local endX = (i + 1) * regionWidth

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
    local targetAlpha = (hoveredRegionIndex == i and altHeld and 1 or 0)
    local regionAlpha = contentHoveredAlphas[i + 1] + (targetAlpha - contentHoveredAlphas[i + 1]) * contentFadeAmount
    contentHoveredAlphas[i + 1] = regionAlpha

    if regionAlpha <= 0 then goto continue end

    ui.pushStyleVar(ui.StyleVar.Alpha, regionAlpha)

    local visualWidth = contentWidth + scale(64)
    local visualX = (i == 2 and (windowSize.x - visualWidth)) or (i == 1 and (windowSize.x - visualWidth) / 2 or 0)
    local visualStartX = math.ceil(visualX)
    local visualEndX = math.ceil(visualX + visualWidth)
    local startPos = vec2(visualStartX, 0)
    local endPos = vec2(visualEndX, math.ceil(regionsBottom))

    local text = 'Click to '
    local color

    if i == contentSide and contentVisible then
      color, text = rgbm(0, 0, 0, 0.5), text .. 'hide'
    elseif contentVisible then
      color, text = rgbm(1, 1, 1, 0.05), text .. 'move'
    else
      color, text = rgbm(1, 1, 1, 0.05), text .. 'show'
    end

    ui.drawRectFilled(startPos, endPos, color)
    ui.pushDWriteFont('@System;Weight=Bold')

    local fontSize = scale(24)
    local textSize = ui.measureDWriteText(text, fontSize)
    local textX = visualX + (visualWidth - textSize.x) / 2
    local textY = regionsBottom / 2

    ui.dwriteDrawText(text, fontSize, vec2(math.ceil(textX), math.ceil(textY)), rgbm(1, 1, 1, 0.9))

    ui.popDWriteFont()
    ui.popStyleVar()

    ::continue::
  end
end

local function drawContent()
  local targetAlpha = contentVisibleStorage:get() and 1 or 0
  contentVisibleAlpha = contentVisibleAlpha + (targetAlpha - contentVisibleAlpha) * contentFadeAmount

  if contentVisibleAlpha <= 0 then return end

  local contentState = buildContentState()

  if not contentHeightCached or contentState ~= contentLastState then
    calculateContentScale()
    contentHeightCache = buildContentHeight()
    contentLastState = contentState
    contentHeightCached = true
  end

  local startY = math.ceil(math.max(scale(20), (windowSize.y - contentHeightCache) / 2))

  ui.pushStyleVar(ui.StyleVar.Alpha, contentVisibleAlpha)
  ui.setCursor(vec2(math.ceil(contentPosition + scale(contentPadding)), startY))
  ui.beginGroup(contentWidth - scale(contentPadding * 2))
  buildContent()
  ui.endGroup()
  ui.popStyleVar()
end

---@param dt number
function script.update(dt)
  local currentWindowSize = ceilVec2(ui.windowSize())

  if windowSize ~= currentWindowSize then
    windowSize = currentWindowSize
    scaleRatio = windowSize.y / 1080
    buildLayout()
    contentHeightCached = false
  end

  contentFadeAmount = math.min(1, contentFadeSpeed * dt)
  contentPosition = math.ceil(contentPosition + (contentTargetPosition - contentPosition) * contentFadeAmount)

  drawBackground()
  drawLoadingBar(dt)
  drawContent()
  drawHoverRegions()
end
