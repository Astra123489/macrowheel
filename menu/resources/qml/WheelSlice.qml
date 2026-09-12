import QtQuick 2.15

Item {
    id: slice
    property double startAngle: 0
    property double sweepAngle: 45
    property double innerRadius: 54
    property double outerRadius: 180
    property string label: ""
    property bool isCategory: false
    property bool hovered: false

    width: outerRadius * 2
    height: outerRadius * 2

    Canvas {
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            
            var centerX = width / 2
            var centerY = height / 2
            var start = startAngle * Math.PI / 180
            var sweep = sweepAngle * Math.PI / 180

            ctx.beginPath()
            ctx.moveTo(centerX, centerY)
            ctx.arc(centerX, centerY, outerRadius, start, start + sweep)
            ctx.lineTo(centerX + innerRadius * Math.cos(start + sweep), 
                      centerY + innerRadius * Math.sin(start + sweep))
            ctx.arc(centerX, centerY, innerRadius, start + sweep, start, true)
            ctx.closePath()

            ctx.fillStyle = isCategory ? (hovered ? "#4a4a5a" : "#3a3a4a") : (hovered ? "#3d3d4d" : "#2d2d3a")
            ctx.fill()
            ctx.strokeStyle = hovered ? "#6a6a7a" : "#4a4a5a"
            ctx.lineWidth = 1
            ctx.stroke()

            // Label
            ctx.save()
            ctx.translate(centerX, centerY)
            ctx.rotate(start + sweep / 2)
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"
            ctx.font = "12px Segoe UI, sans-serif"
            ctx.fillStyle = hovered ? "#ffffff" : "#cccccc"
            ctx.fillText(label, 0, -(outerRadius + innerRadius) / 2)
            ctx.restore()
        }
    }
}