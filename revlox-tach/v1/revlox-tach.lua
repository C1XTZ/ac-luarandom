local maxSpeed = 320
local prevRpm = 0
local outerRadius = 100
local innerRadius = 70
local centerOffset = 30
local markingShort = 10
local markingLong = 15
local offsetAngle = 20
local startAngle = math.rad(-180 - offsetAngle)
local endAngle = math.rad(offsetAngle)
local angleRange = endAngle - startAngle
local centerX, centerY = outerRadius + centerOffset, outerRadius + centerOffset
local arcSegments = 50

local settings = ac.storage {
    customColor = false,
    rpmColorLimiter = true,
    rpmColor = rgb.colors.orange:clone(),
    speedColor = rgb.colors.aqua:clone(),
    rpmNeedleColor = rgb.colors.red:clone(),
    speedNeedleColor = rgb.colors.red:clone(),
    rpmLimiterColor = rgb.colors.red:clone(),
    manualOverwrite = false,
    maxSpeed = 320,
    maxRpm = 8000,
    rpmLimiter = 7000,
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
    ui.pathArcTo(vec2(centerX, centerY), radius + centerOffset, startAngle - math.rad(2.5), endAngle + math.rad(2.5), arcSegments)
    ui.pathFillConvex(rgb.colors.black)
end

local function drawGaugeMarkings(radius, color, isSpeed, maxRpm, rpmLimiterStart)
    if isSpeed then
        local count = maxSpeed / 10
        for i = 0, count do
            local angle = startAngle + (i / count) * angleRange
            local outerX, outerY = centerX + math.cos(angle) * radius, centerY + math.sin(angle) * radius

            if i % 2 == 0 then
                local innerX = centerX + math.cos(angle) * (radius - markingLong)
                local innerY = centerY + math.sin(angle) * (radius - markingLong)
                ui.beginOutline()
                ui.drawLine(vec2(innerX, innerY), vec2(outerX, outerY), color, 3)
                ui.endOutline(rgb.colors.black, 3)

                local textX = centerX + math.cos(angle) * (radius + 15)
                local textY = centerY + 2 + math.sin(angle) * (radius + 15)
                local value = i * 10
                ui.drawText(string.format("%3d", value), vec2(textX - 10, textY - 10), color)
            else
                local innerX = centerX + math.cos(angle) * (radius - markingShort)
                local innerY = centerY + math.sin(angle) * (radius - markingShort)
                ui.beginOutline()
                ui.drawLine(vec2(innerX, innerY), vec2(outerX, outerY), color, 2)
                ui.endOutline(rgb.colors.black, 3)
            end
        end
    else
        local count = math.floor(maxRpm / 1000)
        local limiterStartAngle = startAngle + (rpmLimiterStart / maxRpm) * angleRange
        local innerRadius = radius - markingShort
        local fillColor = settings.rpmColorLimiter and rpmLimiterColor or rpmColor

        ui.pathArcTo(vec2(centerX, centerY), radius, limiterStartAngle, endAngle, arcSegments)
        ui.pathArcTo(vec2(centerX, centerY), innerRadius, endAngle, limiterStartAngle, arcSegments)
        ui.pathFillConvex(fillColor)
        --this hides the messed up inner side of the path, i dont care anymore
        ui.drawCircleFilled(vec2(centerX, centerY), innerRadius + 1, rgb.colors.black, arcSegments)

        for i = 0, count * 2 do
            local rpm = (i / 2) * 1000
            local angle = startAngle + (rpm / maxRpm) * angleRange
            local outerX, outerY = centerX + math.cos(angle) * radius, centerY + math.sin(angle) * radius
            local markingColor = settings.rpmColorLimiter and rpm >= rpmLimiterStart and rpmLimiterColor or color

            if i % 2 == 0 then
                local innerX = centerX + math.cos(angle) * (radius - markingLong)
                local innerY = centerY + math.sin(angle) * (radius - markingLong)
                ui.beginOutline()
                ui.drawLine(vec2(innerX, innerY), vec2(outerX, outerY), markingColor, 3)
                ui.endOutline(rgb.colors.black, 3)

                local textX = centerX + math.cos(angle) * (radius - 25)
                local textY = centerY - 3 + math.sin(angle) * (radius - 25)
                local value = rpm / 1000
                ui.drawText(string.format("%2d", value), vec2(textX - 7, textY - 5), markingColor)
            else
                local innerX = centerX + math.cos(angle) * (radius - markingShort)
                local innerY = centerY + math.sin(angle) * (radius - markingShort)
                ui.beginOutline()
                ui.drawLine(vec2(innerX, innerY), vec2(outerX, outerY), markingColor, 2)
                ui.endOutline(rgb.colors.black, 3)
            end
        end
    end
end

local function drawNeedle(value, maxValue, radius, color, width)
    local angle = startAngle + (value / maxValue) * angleRange
    local endX, endY = centerX + math.cos(angle) * radius, centerY + math.sin(angle) * radius
    ui.drawLine(vec2(centerX, centerY), vec2(endX, endY), color, width)
end

function roundToNearestStep(value, step, minVal, maxVal)
    value = math.max(minVal, math.min(value, maxVal))
    return math.floor((value + step / 2) / step) * step
end

function script.windowMainSettings(dt)
    ui.text('Color Settings')
    ui.separator()
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

    ui.text('\nOverwrite Settings')
    ui.separator()
    if ui.checkbox('Gauge Overwrite', settings.manualOverwrite) then settings.manualOverwrite = not settings.manualOverwrite end
    if settings.manualOverwrite then
        settings.maxSpeed, speedChange = ui.slider('##MaxSpeed', settings.maxSpeed, 40, 500, 'Max Speed: %.f km/h')
        if speedChange then
            settings.maxSpeed = roundToNearestStep(settings.maxSpeed, 20, 40, 500)
        end
        ui.sameLine()
        settings.maxRpm, rpmChange = ui.slider('##MaxRPM', settings.maxRpm, 1000, 30000, 'Max RPM: %.0f')
        if rpmChange then
            settings.maxRpm = roundToNearestStep(settings.maxRpm, 1000, 1000, 30000)
            settings.rpmLimiter = math.round((settings.maxRpm * 0.8) / 1000) * 1000
        end

        settings.rpmLimiter, limiterChange = ui.slider('##RPMLimiter', settings.rpmLimiter, 0, settings.maxRpm - 500, 'RPM Limiter: %.0f')
        if limiterChange then
            settings.rpmLimiter = roundToNearestStep(settings.rpmLimiter, 500, 0, settings.maxRpm - 500)
        end
        ui.sameLine()
        if ui.button('                Reset Gauges                ') then
            settings.maxSpeed = 320
            settings.maxRpm = math.ceil(ac.getCar(0).rpmLimiter / 1000) * 1000
            settings.rpmLimiter = math.round((settings.maxRpm * 0.8) / 1000) * 1000
        end
    end
end

function script.windowMain(dt)
    local car = ac.getCar(0)
    maxSpeed = settings.manualOverwrite and settings.maxSpeed or 320
    local maxRpm = settings.manualOverwrite and settings.maxRpm or math.ceil(car.rpmLimiter / 1000) * 1000
    local rpmLimiterStart = settings.manualOverwrite and settings.rpmLimiter or math.round((maxRpm * 0.8) / 1000) * 1000
    local rpm = car.rpm
    local speed = math.min(car.speedKmh, settings.manualOverwrite and settings.maxSpeed or maxSpeed)
    local gear = car.gear == -1 and "R" or car.gear == 0 and "N" or tostring(car.gear)

    -- Draw Outer Gauge (Speed)
    drawGaugeBackground(outerRadius, speedColor)
    drawGaugeMarkings(outerRadius, speedColor, true)
    drawNeedle(speed, maxSpeed, outerRadius, speedNeedleColor, 3.5)

    -- Draw Inner Gauge (RPM)
    drawGaugeBackground(innerRadius - 25, rpmColor)
    drawGaugeMarkings(innerRadius, rpmColor, false, maxRpm, rpmLimiterStart)

    -- Smooth RPM value for needle
    local smoothedRpm = math.lerp(prevRpm, math.min(rpm, maxRpm), 0.1)
    drawNeedle(smoothedRpm, maxRpm, innerRadius, rpmNeedleColor, 3)
    prevRpm = smoothedRpm

    -- Draw Center Displays
    local rpmColorTxt = settings.rpmColorLimiter and (rpm >= rpmLimiterStart and rpmLimiterColor or rpmColor) or rpmColor
    ui.drawCircleFilled(vec2(centerX, centerY), 30, rgb.colors.black, arcSegments)
    ui.drawText(gear, vec2(centerX - 4, centerY - 20), rgb.colors.white)
    ui.drawText(string.format("%5d", rpm), vec2(centerX - 18, centerY - 7), rpmColorTxt)
    ui.drawText(string.format("%3d", speed), vec2(centerX - 11, centerY + 6), speedColor)
end
