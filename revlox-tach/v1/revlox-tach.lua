local maxSpeed = 320
local maxrpm = 10000

local outerRadius = 100
local innerRadius = 70
local centerOffset = 30
local centerX, centerY = outerRadius + centerOffset, outerRadius + centerOffset

local offsetAngle = 20
local startAngle = math.rad(-180 - offsetAngle)
local endAngle = math.rad(offsetAngle)
local angleRange = endAngle - startAngle

function script.windowMain(dt)
    local rpm = math.clamp(ac.getCar(0).rpm, 0, 10000)
    local rpmColor = rpm >= 8000 and rgb.colors.red or rgb.colors.orange
    local speed = math.clamp(ac.getCar(0).speedKmh, 0, 320)
    local gear = ac.getCar(0).gear == -1 and "R" or ac.getCar(0).gear == 0 and "N" or tostring(ac.getCar(0).gear)

    -- Draw KMH gauge background
    ui.pathArcTo(vec2(centerX, centerY), outerRadius + centerOffset, math.rad(-180 - offsetAngle - 5), math.rad(offsetAngle + 5), 120)
    ui.pathFillConvex(rgb.colors.black)

    -- Draw KMH markings (outer ring)
    for i = 0, 32 do
        local angle = startAngle + (i / 32) * angleRange
        local outerX = centerX + math.cos(angle) * outerRadius
        local outerY = centerY + math.sin(angle) * outerRadius

        -- Draw main marking (longer, numbered)
        if i % 2 == 0 then
            local innerX = centerX + math.cos(angle) * (outerRadius - 15)
            local innerY = centerY + math.sin(angle) * (outerRadius - 15)

            ui.drawLine(vec2(innerX, innerY), vec2(outerX, outerY), rgb.colors.aqua, 2)

            local textX = centerX + math.cos(angle) * (outerRadius + 15)
            local textY = centerY + math.sin(angle) * (outerRadius + 10)

            ui.drawText(tostring(i / 2 * 20), vec2(textX - 10, textY - 10), rgb.colors.aqua)

            -- Draw markings inbetween (shorter, not numbered)
        else
            local innerX = centerX + math.cos(angle) * (outerRadius - 10)
            local innerY = centerY + math.sin(angle) * (outerRadius - 10)

            ui.drawLine(vec2(innerX, innerY), vec2(outerX, outerY), rgb.colors.aqua, 2)
        end
    end

    -- Draw speed needle
    local speedAngle = startAngle + (speed / maxSpeed) * angleRange
    local speedEndX = centerX + math.cos(speedAngle) * outerRadius
    local speedEndY = centerY + math.sin(speedAngle) * outerRadius
    ui.drawLine(vec2(centerX, centerY), vec2(speedEndX, speedEndY), rgb.colors.red, 3.5)

    -- Draw RPM gauge background (to hide kmh needle in the rpm gauge)
    ui.pathArcTo(vec2(centerX, centerY), innerRadius + 5, math.rad(-180 - offsetAngle - 5), math.rad(offsetAngle + 5), 120)
    ui.pathFillConvex(rgb.colors.black)

    -- Draw RPM markings (inner ring)
    for i = 0, 20 do
        local angle = startAngle + (i / 20) * angleRange
        local outerX = centerX + math.cos(angle) * innerRadius
        local outerY = centerY + math.sin(angle) * innerRadius
        local color = i / 2 >= 8 and rgb.colors.red or rgb.colors.orange

        -- Draw main marking (longer, numbered)
        if i % 2 == 0 then
            local innerX = centerX + math.cos(angle) * (innerRadius - 15)
            local innerY = centerY + math.sin(angle) * (innerRadius - 15)

            ui.drawLine(vec2(innerX, innerY), vec2(outerX, outerY), color, 2)

            local textX = centerX + math.cos(angle) * (innerRadius - 25)
            local textY = centerY + math.sin(angle) * (innerRadius - 20)

            ui.drawText(tostring(i / 2), vec2(textX - 5, textY - 5), color)

            -- Draw markings inbetween (shorter, not numbered)
        else
            local innerX = centerX + math.cos(angle) * (innerRadius - 10)
            local innerY = centerY + math.sin(angle) * (innerRadius - 10)

            ui.drawLine(vec2(innerX, innerY), vec2(outerX, outerY), color, 2)
        end
    end

    -- Draw RPM needle
    local rpmAngle = startAngle + (rpm / maxrpm) * angleRange
    local rpmEndX = centerX + math.cos(rpmAngle) * innerRadius
    local rpmEndY = centerY + math.sin(rpmAngle) * innerRadius
    ui.drawLine(vec2(centerX, centerY), vec2(rpmEndX, rpmEndY), rgb.colors.red, 3)

    -- Draw center cap
    ui.drawCircleFilled(vec2(centerX, centerY), 5, rgbm(0.1, 0.1, 0.1, 1))

    ui.drawText(gear, vec2(centerX - 4, centerY + 10), rgb.colors.white)
    ui.drawText(string.format("%05d", rpm), vec2(centerX - 18, centerY + 23), rpmColor)
    ui.drawText(string.format("%03d", speed), vec2(centerX - 11, centerY + 35), rgb.colors.aqua)
end
