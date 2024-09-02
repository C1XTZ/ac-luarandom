local maxSpeed = 320
local maxRpm = 10000
local prevRpm = 0
local outerRadius = 100
local innerRadius = 70
local centerOffset = 30
local offsetAngle = 20
local startAngle = math.rad(-180 - offsetAngle)
local endAngle = math.rad(offsetAngle)
local angleRange = endAngle - startAngle
local centerX, centerY = outerRadius + centerOffset, outerRadius + centerOffset
local rpmLimiterThreshold = 8000

local settings = ac.storage {
    customColor = false,
    rpmColorLimiter = true,
    rpmColor = rgb.colors.orange:clone(),
    speedColor = rgb.colors.aqua:clone(),
    rpmNeedleColor = rgb.colors.red:clone(),
    speedNeedleColor = rgb.colors.red:clone(),
    rpmLimiterColor = rgb.colors.red:clone(),
}

local rpmColorDefault = rgb.colors.orange:clone()
local speedColorDefault = rgb.colors.aqua:clone()
local needleColorDefault = rgb.colors.red:clone()
local limiterColorDefault = rgb.colors.red:clone()

local rpmColor = settings.customColor and settings.rpmColor or rgb.colors.orange:clone()
local speedColor = settings.customColor and settings.speedColor or rgb.colors.aqua:clone()
local rpmNeedleColor = settings.customColor and settings.rpmNeedleColor or rgb.colors.red:clone()
local speedNeedleColor = settings.customColor and settings.speedNeedleColor or rgb.colors.red:clone()
local rpmLimiterColor = settings.customColor and settings.rpmLimiterColor or rgb.colors.red:clone()

local colorFlags = bit.bor(ui.ColorPickerFlags.NoAlpha, ui.ColorPickerFlags.NoSidePreview, ui.ColorPickerFlags.NoDragDrop, ui.ColorPickerFlags.NoLabel, ui.ColorPickerFlags.DisplayRGB, ui.ColorPickerFlags.NoSmallPreview)

local function drawGaugeBackground(radius, color)
    ui.pathArcTo(vec2(centerX, centerY), radius + centerOffset, startAngle - math.rad(2.5), endAngle + math.rad(2.5), 120)
    ui.pathFillConvex(rgb.colors.black)
end

local function drawGaugeMarkings(radius, count, color, isSpeed)
    for i = 0, count do
        local angle = startAngle + (i / count) * angleRange
        local outerX, outerY = centerX + math.cos(angle) * radius, centerY + math.sin(angle) * radius
        local markingColor = color
        if not isSpeed and settings.rpmColorLimiter then
            markingColor = (i / 2 * (maxRpm / 10) >= rpmLimiterThreshold) and rpmLimiterColor or color
        end

        if i % 2 == 0 then
            local innerX = centerX + math.cos(angle) * (radius - 15)
            local innerY = centerY + math.sin(angle) * (radius - 15)

            ui.drawLine(vec2(innerX, innerY), vec2(outerX, outerY), markingColor, 2)

            local textX = centerX + math.cos(angle) * (radius + (isSpeed and 15 or -25))
            local textY = centerY + (isSpeed and 2 or -3) + math.sin(angle) * (radius + (isSpeed and 15 or -25))
            local value = isSpeed and i * 10 or i / 2
            ui.drawText(string.format(isSpeed and "%3d" or "%2d", value), vec2(textX - (isSpeed and 10 or 7), textY - (isSpeed and 10 or 5)), markingColor)
        else
            local innerX = centerX + math.cos(angle) * (radius - 10)
            local innerY = centerY + math.sin(angle) * (radius - 10)
            ui.drawLine(vec2(innerX, innerY), vec2(outerX, outerY), markingColor, 2)
        end
    end
end

local function drawNeedle(value, maxValue, radius, color, width)
    local angle = startAngle + (value / maxValue) * angleRange
    local endX, endY = centerX + math.cos(angle) * radius, centerY + math.sin(angle) * radius
    ui.drawLine(vec2(centerX, centerY), vec2(endX, endY), color, width)
end

function script.windowMainSettings(dt)
    if ui.checkbox('Custom Colors', settings.customColor) then
        settings.customColor = not settings.customColor
        if not settings.customColor then
            rpmColor = rpmColorDefault:clone()
            speedColor = speedColorDefault:clone()
            rpmNeedleColor = needleColorDefault:clone()
            speedNeedleColor = needleColorDefault:clone()
            rpmLimiterColor = limiterColorDefault:clone()
        else
            rpmColor = settings.rpmColor
            speedColor = settings.speedColor
            rpmNeedleColor = settings.rpmNeedleColor
            speedNeedleColor = settings.speedNeedleColor
            rpmLimiterColor = settings.rpmLimiterColor
        end
    end

    ui.sameLine()
    if ui.checkbox('Colored RPM Limiter', settings.rpmColorLimiter) then
        settings.rpmColorLimiter = not settings.rpmColorLimiter
    end

    if settings.customColor then
        ui.text('\t')
        ui.sameLine()
        ui.text('KMH Color')
        ui.sameLine()
        ui.setCursorX(276)
        ui.text('KMH Needle Color')
        ui.text('\t')
        ui.sameLine()
        local kmhColorChange = ui.colorPicker('KMH Color Picker', speedColor, colorFlags)
        if kmhColorChange then settings.speedColor = speedColor end
        ui.sameLine()
        local speedNeedleColorChange = ui.colorPicker('KMH Needle Color Picker', speedNeedleColor, colorFlags)
        if speedNeedleColorChange then settings.speedNeedleColor = speedNeedleColor end

        ui.text('\t')
        ui.sameLine()
        if ui.button('Reset KMH Color') then
            speedColor = speedColorDefault:clone()
            settings.speedColor = speedColorDefault:clone()
        end
        ui.sameLine()
        ui.setCursorX(276)
        if ui.button('Reset KMH Needle Color') then
            speedNeedleColor = needleColorDefault:clone()
            settings.speedNeedleColor = needleColorDefault:clone()
        end

        ui.text('\t')
        ui.sameLine()
        ui.text('RPM Color')
        ui.sameLine()
        ui.setCursorX(276)
        ui.text('RPM Needle Color')
        if settings.rpmColorLimiter then
            ui.sameLine()
            ui.setCursorX(507)
            ui.text('Limiter Color')
        end
        ui.text('\t')
        ui.sameLine()
        local rpmColorChange = ui.colorPicker('RPM Color Picker', rpmColor, colorFlags)
        if rpmColorChange then settings.rpmColor = rpmColor end
        ui.sameLine()
        local rpmNeedleColorChange = ui.colorPicker('RPM Needle Color Picker', rpmNeedleColor, colorFlags)
        if rpmNeedleColorChange then settings.rpmNeedleColor = rpmNeedleColor end
        if settings.rpmColorLimiter then
            ui.sameLine()
            local limiterColorChange = ui.colorPicker('Limiter Color Picker', rpmLimiterColor, colorFlags)
            if limiterColorChange then settings.rpmLimiterColor = rpmLimiterColor end
        end

        ui.text('\t')
        ui.sameLine()
        if ui.button('Reset RPM Color') then
            rpmColor = rpmColorDefault:clone()
            settings.rpmColor = rpmColorDefault:clone()
        end
        ui.sameLine()
        ui.setCursorX(276)
        if ui.button('Reset RPM Needle Color') then
            rpmNeedleColor = limiterColorDefault:clone()
            settings.rpmNeedleColor = limiterColorDefault:clone()
        end
        if settings.rpmColorLimiter then
            ui.sameLine()
            ui.setCursorX(507)
            if ui.button('Reset Limiter Color') then
                rpmLimiterColor = limiterColorDefault:clone()
                settings.rpmLimiterColor = limiterColorDefault:clone()
            end
        end
    end
end

function script.windowMain(dt)
    local car = ac.getCar(0)
    local rpm = math.min(car.rpm, maxRpm)
    local speed = math.min(car.speedKmh, maxSpeed)
    local gear = car.gear == -1 and "R" or car.gear == 0 and "N" or tostring(car.gear)

    -- Draw Outer Gauge
    drawGaugeBackground(outerRadius, speedColor)
    drawGaugeMarkings(outerRadius, 32, speedColor, true)
    drawNeedle(speed, maxSpeed, outerRadius, speedNeedleColor, 3.5)

    -- Draw Inner Gauge
    drawGaugeBackground(innerRadius - 25, rpmColor)
    drawGaugeMarkings(innerRadius, 20, rpmColor, false)

    -- Smooth RPM value for needle
    local smoothedRpm = math.lerp(prevRpm, rpm, 0.1)
    drawNeedle(smoothedRpm, maxRpm, innerRadius, rpmNeedleColor, 3)
    prevRpm = smoothedRpm

    -- Draw Center Displays
    local rpmColorTxt = settings.rpmColorLimiter and (rpm >= rpmLimiterThreshold and rpmLimiterColor or rpmColor) or rpmColor
    ui.drawCircleFilled(vec2(centerX, centerY), 30, rgb.colors.black, 120)
    ui.drawText(gear, vec2(centerX - 4, centerY - 20), rgb.colors.white)
    ui.drawText(string.format("%5d", rpm), vec2(centerX - 18, centerY - 7), rpmColorTxt)
    ui.drawText(string.format("%3d", speed), vec2(centerX - 11, centerY + 6), speedColor)
end
