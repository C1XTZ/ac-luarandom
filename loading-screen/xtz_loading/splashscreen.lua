local bgColor = rgbm(0.2, 0.2, 0.2, 1)
local padding = 20
local bgRatio = 0.7

local carDescription, trackDescription, loadingStatus, gameInfoText, lastContentKey
local contentCache = {}

local raceINI = ac.INIConfig.raceConfig()
local weatherfxImpl = ac.INIConfig.load(ac.getFolder(ac.FolderID.ExtCfgUser) .. '\\weather_fx.ini'):get("BASIC", "IMPLEMENTATION", 'Default')
local ppFilter = ac.getPpFilter():gsub("[_%-]", " "):gsub("%.ini$", "")
local patchVersion = ac.getPatchVersionCode()

---@return string|nil
local function getCarDescription()
  if not carDescription then
    local carID = loading.carID()
    if carID == '' then return nil end
    local description = JSON.parse(io.load(ac.getFolder(ac.FolderID.ContentCars) .. '/' .. carID .. '/ui/ui_car.json')).description
    carDescription = string.reggsub(description, [[\t|</?br\s*/?\s*>]], '')
  end
  return carDescription
end

---@return string|nil
local function getTrackDescription()
  if not trackDescription then
    local trackID = loading.trackID()
    if trackID == '' then return nil end
    local path = ac.getFolder(ac.FolderID.ContentTracks) .. '/' .. trackID .. '/ui/'
    local layoutID = loading.trackLayoutID()
    if layoutID ~= '' then path = path .. layoutID .. '/' end
    local description = JSON.parse(io.load(path .. 'ui_track.json')).description
    trackDescription = string.reggsub(description, [[\t|</?br\s*/?\s*>]], '')
  end
  return trackDescription
end

---@param size vec2
---@return string
local function getContentKey(size)
  local title, details = loading.warning()
  return string.format('%s|%d|%s|%s|%s|%d', title or '', #loading.serverHints(), loading.carName(), loading.trackName(), loading.version(), size.x)
end

---@param icon ui.Icons
---@param iconPadding number
---@param title string
---@param details string
local function drawBlock(icon, iconPadding, title, details)
  if title == '' then return end
  ui.offsetCursorY(30)
  ui.dummy(vec2(64, 64))
  local r1, r2 = ui.itemRect()
  ui.drawIcon(icon, r1 + iconPadding, r2 - iconPadding)
  ui.sameLine(0, 12)
  ui.pushDWriteFont('@System;Weight=Bold')
  ui.dwriteText(title, 20)
  ui.popDWriteFont()
  ui.offsetCursorX(64 + 12)
  ui.offsetCursorY(-38)
  ui.dwriteTextWrapped(details or 'No description.', 14)
end

---@param hints string[]
---@param startIndex number?
---@return string
local function formatHints(hints, startIndex)
  local result = {}
  for i = startIndex or 1, #hints do result[#result + 1] = '• ' .. hints[i] end
  return table.concat(result, '\n')
end

---@return string
local function buildGameInfo()
  if not gameInfoText then
    gameInfoText = table.concat({ '• ' .. loading.version():replace('&', '\n•') .. ' (' .. patchVersion .. ')', '• PP Filter: ' .. ppFilter, '• Weather FX: ' .. weatherfxImpl }, '\n')
  end
  return gameInfoText
end

local function generateContent()
  local blocks = {}
  local title, details = loading.warning()
  if title then blocks[#blocks + 1] = { ui.Icons.Warning, 20, 'Warning', title .. '\n' .. details } end
  local serverHints = loading.serverHints()
  if #serverHints > 0 then
    blocks[#blocks + 1] = { 'splashscreen::logo', 8, raceINI:get('REMOTE', 'SERVER_NAME', ''), formatHints(serverHints, 2) }
  else
    blocks[#blocks + 1] = { 'splashscreen::logo', 8, 'Singleplayer Session', buildGameInfo() }
  end
  local carHints = loading.carHints()
  blocks[#blocks + 1] = { 'splashscreen::badge', 8, loading.carName(), #carHints > 0 and formatHints(carHints) or getCarDescription() }
  blocks[#blocks + 1] = { 'splashscreen::track', 8, loading.trackName(), getTrackDescription() }
  if #serverHints > 0 then
    blocks[#blocks + 1] = { 'splashscreen::logo', 8, 'Game Information', buildGameInfo() }
  end
  for i = 1, #blocks do drawBlock(blocks[i][1], blocks[i][2], blocks[i][3], blocks[i][4]) end
end

---@param infoWidth number
---@return number
local function measureContentHeight(infoWidth)
  ui.pushClipRect(vec2(-1000, -1000), vec2(-999, -999))
  ui.setCursor(vec2(0, 0))
  ui.beginGroup(infoWidth)
  generateContent()
  local height = ui.getCursorY()
  ui.endGroup()
  ui.popClipRect()
  return height
end

---@param size vec2
---@param bgWidth number
---@param infoWidth number
local function drawBackground(size, bgWidth, infoWidth)
  ui.drawImage('splashscreen::background', 0, size, ui.ImageFit.Fill)
  ui.beginTextureShade('splashscreen::background')
  ui.beginMIPBias()
  ui.drawRectFilledMultiColor(vec2(infoWidth, 0), vec2(bgWidth, size.y), rgbm.colors.transparent, bgColor, bgColor, rgbm.colors.transparent)
  if size.x > bgWidth then ui.drawRectFilled(vec2(bgWidth, 0), size, bgColor) end
  ui.endTextureShade(vec2(0, 0), size)
  ui.endMIPBias(8, true)
end

---@param size vec2
---@param padding number
local function drawLoadingBar(size, padding)
  if not loadingStatus or loadingStatus:size().x ~= size.x then loadingStatus = ui.ExtraCanvas(vec2(size.x, padding)) end
  loadingStatus:clear(rgbm.colors.black):update(function()
    local start = ui.getCursor()
    ui.drawLoadingSpinner(start, start + vec2(20, 20))
    ui.offsetCursorX(28)
    ui.offsetCursorY(-1)
    ui.dwriteText(loading.status(), 16)
    ui.sameLine(0, 8)
    ui.dwriteText(loading.details(), 16, rgbm.colors.gray)
  end)
  local pos = vec2(0, size.y - padding)
  ui.beginRotation()
  ui.drawImage(loadingStatus, pos, pos + loadingStatus:size())
  ui.setShadingOffset(-1, 1, 1, 1)
  ui.drawImage(loadingStatus, pos, pos + loadingStatus:size() * vec2(loading.progress(), 1), rgbm.colors.white, vec2(), vec2(loading.progress(), 1), ui.ImageFit.Fill)
  ui.resetShadingOffset()
  ui.endRotation(90, 0)
end

---@param size vec2
---@param infoWidth number
---@param padding number
local function drawContent(size, infoWidth, padding)
  local contentKey = getContentKey(size)
  if not contentCache[contentKey] then
    contentCache[contentKey] = measureContentHeight(infoWidth)
    if lastContentKey and lastContentKey ~= contentKey then contentCache[lastContentKey] = nil end
    lastContentKey = contentKey
  end
  local startY = math.max(20, (size.y - contentCache[contentKey]) / 2)
  ui.setCursor(vec2(size.x - infoWidth - padding / 2, startY))
  ui.beginGroup(infoWidth)
  generateContent()
  ui.endGroup()
end

function script.update()
  local size = ui.windowSize()
  local bgWidth = size.x * bgRatio
  local infoWidth = size.x * (1 - bgRatio)
  drawBackground(size, bgWidth, infoWidth)
  drawLoadingBar(size, padding)
  drawContent(size, infoWidth, padding)
end
