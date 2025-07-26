local raceINI = ac.INIConfig.raceConfig()

local carDescription
local function getCarDescription()
  if not carDescription then
    if loading.carID() == '' then return nil end
    local description = JSON.parse(io.load(ac.getFolder(ac.FolderID.ContentCars) .. '/' .. loading.carID() .. '/ui/ui_car.json')).description
    carDescription = string.reggsub(description, [[\t|</?br\s*/?\s*>]], '')
  end
  return carDescription
end

local trackDescription
local function getTrackDescription()
  if not trackDescription then
    if loading.trackID() == '' then return nil end
    local path = ac.getFolder(ac.FolderID.ContentTracks) .. '/' .. loading.trackID() .. '/ui/'
    if loading.trackLayoutID() ~= '' then
      path = path .. loading.trackLayoutID() .. '/'
    end
    print(path .. 'ui_track.json')
    local description = JSON.parse(io.load(path .. 'ui_track.json')).description
    trackDescription = string.reggsub(description, [[\t|</?br\s*/?\s*>]], '')
  end
  return trackDescription
end

local bgColor = rgbm(0.2, 0.2, 0.2, 1)
local loadingStatus ---@type ui.ExtraCanvas

local function drawBlock(icon, iconPadding, title, detailsCallback)
  if title ~= '' then
    ui.offsetCursorY(40)
    ui.dummy(vec2(64, 64))
    local r1, r2 = ui.itemRect()
    ui.drawIcon(icon, r1 + iconPadding, r2 - iconPadding)
    ui.sameLine(0, 12)
    ui.pushDWriteFont('@System;Weight=Bold')
    ui.dwriteText(title, 20)
    ui.popDWriteFont()
    ui.offsetCursorX(64 + 12)
    ui.offsetCursorY(-38)
    ui.dwriteTextWrapped(detailsCallback() or 'No description.', 14)
  end
end

function script.update(dt)
  local size = ui.windowSize()
  local padding = 20

  if not loadingStatus or loadingStatus:size().x ~= size.x then
    loadingStatus = ui.ExtraCanvas(vec2(size.x, padding))
  end

  loadingStatus:clear(rgbm.colors.black):update(function(dt)
    local start = ui.getCursor()
    ui.drawLoadingSpinner(start, start + vec2(20, 20))
    ui.offsetCursorX(28)
    ui.offsetCursorY(-1)
    ui.dwriteText(loading.status(), 16)
    ui.sameLine(0, 8)
    ui.dwriteText(loading.details(), 16, rgbm.colors.gray)
  end)

  local totalRatio = 1
  local bgRatio = 0.7
  local infoRatio = totalRatio - bgRatio

  local bgWidth = size.x * bgRatio
  local infoWidth = size.x * infoRatio
  ui.drawImage('splashscreen::background', 0, vec2(bgWidth, size.y), ui.ImageFit.Fill)
  ui.beginTextureShade('splashscreen::background')
  ui.beginMIPBias()
  ui.drawRectFilledMultiColor(vec2(200, 0), vec2(bgWidth, size.y), rgbm.colors.transparent, bgColor, bgColor, rgbm.colors.transparent)
  if size.x > bgWidth then
    ui.drawRectFilled(vec2(bgWidth, 0), size, bgColor)
  end
  ui.endTextureShade(vec2(0, 0), size)
  ui.endMIPBias(8, true)

  local pos = vec2(0, size.y - padding)
  ui.beginRotation()
  ui.drawImage(loadingStatus, pos, pos + loadingStatus:size())
  ui.setShadingOffset(-1, 1, 1, 1)
  ui.drawImage(loadingStatus, pos, pos + loadingStatus:size() * vec2(loading.progress(), 1), rgbm.colors.white, vec2(), vec2(loading.progress(), 1), ui.ImageFit.Fill)
  ui.resetShadingOffset()
  ui.endRotation(90, 0)

  ui.setCursor(vec2(ui.windowWidth() - infoWidth - padding, size.y * 0.2))
  ui.beginGroup(infoWidth)
  using(function()
    local title, details = loading.warning()
    if title then
      drawBlock(ui.Icons.Warning, padding, 'Warning', function()
        return title .. '\n' .. details
      end)
    end

    if #loading.serverHints() > 0 then
      drawBlock('splashscreen::logo', 8, raceINI:get('REMOTE', 'SERVER_NAME', ''), function()
        return table.concat(table.map(loading.serverHints(), function(item, key)
          if key == 1 then return nil end -- first line is a server name
          return '• %s' % item
        end), '\n')
      end)
    else
      drawBlock('splashscreen::logo', 0, 'Online race', function()
        return loading.version():replace('&', '\n&')
      end)
    end

    drawBlock('splashscreen::badge', 8, loading.carName(), function()
      do
        return table.concat(table.map(loading.carHints(), function(item)
          return '• %s' % item
        end), '\n')
      end
      return getCarDescription()
    end)

    drawBlock('splashscreen::track', 8, loading.trackName(), function()
      return getTrackDescription()
    end)
  end, ui.endGroup)
end
