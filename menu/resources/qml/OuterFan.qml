import QtQuick 2.15

Item {
    id: fan
    property double anchorAngle: 0
    property double fanSpan: 90
    property int commandCount: 0
    property double innerRadius: 198
    property double outerRadius: 324
    property variant commands: []

    width: outerRadius * 2
    height: outerRadius * 2

    Canvas {
        anchors.fill: parent
        onPaint: {
            if (commandCount === 0) return
            
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            
            var centerX = width / 2
            var centerY = height / 2
            var startAngle = (anchorAngle - fanSpan / 2) * Math.PI / 180
            var commandAngle = (commandCount > 1) ? (fanSpan * Math.PI / 180) / (commandCount - 1) : 0

            for (var i = 0; i < commandCount; i++) {
                var angle = startAngle + i * commandAngle
                var sweep = 20 * Math.PI / 180

                ctx.beginPath()
                ctx.moveTo(centerX, centerY)
                ctx.arc(centerX, centerY, outerRadius, angle - sweep/2, angle + sweep/2)
                ctx.lineTo(centerX + innerRadius * Math.cos(angle + sweep/2), 
                          centerY + innerRadius * Math.sin(angle + sweep/2))
                ctx.arc(centerX, centerY, innerRadius, angle + sweep/2, angle - sweep/2, true)
                ctx.closePath()

                ctx.fillStyle = "#3a3a4a"
                ctx.fill()
                ctx.strokeStyle = "#4a4a5a"
                ctx.lineWidth = 1
                ctx.stroke()

                // Label
                ctx.save()
                ctx.translate(centerX, centerY)
                ctx.rotate(angle)
                ctx.textAlign = "center"
                ctx.textBaseline = "middle"
                ctx.font = "11px Segoe UI, sans-serif"
                ctx.fillStyle = "#ffffff"
                ctx.fillText(commands[i].label, 0, -(innerRadius + outerRadius) / 2)
                ctx.restore()
            }
        }
    }
}