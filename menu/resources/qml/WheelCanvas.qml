import QtQuick 2.15

// Visual wheel surface.
//
// `wheelGeometry` is injected as a QML context property from main.cpp.
// All geometry, hit-testing and command dispatch live in C++; this component
// only draws and forwards pointer position.
//
// The Canvas is intentionally vector-only: no blur, no glow, no shadows
// (spec section 10).
Item {
    id: wheelCanvas
    anchors.fill: parent

    // Last known pointer position in canvas coordinates. The overlay opens
    // centred on the cursor, so this starts in the middle.
    property real lastX: width / 2
    property real lastY: height / 2

    Component.onCompleted: wheelGeometry.setViewportSize(width, height)
    onWidthChanged:    wheelGeometry.setViewportSize(width, height)
    onHeightChanged:   wheelGeometry.setViewportSize(width, height)

    // Called by Main.qml when the hotkey is released.
    // Returns true when the wheel should close (command executed, or the
    // release cancelled the selection).
    function commit() {
        return wheelGeometry.activateAt(lastX, lastY)
    }

    function cancel() {
        wheelGeometry.cancelSelection()
    }

    // -----------------------------------------------------------------------
    // Drawing
    // -----------------------------------------------------------------------
    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            var cx = width / 2
            var cy = height / 2
            var R = wheelGeometry.wheelRadius
            var innerR = R * 0.30
            var fanInner = R * 1.10
            var fanOuter = R * 1.80

            // Base disc
            ctx.beginPath()
            ctx.arc(cx, cy, R, 0, Math.PI * 2)
            ctx.fillStyle = "#1e1e2e"
            ctx.fill()
            ctx.strokeStyle = "#4a4a5a"
            ctx.lineWidth = 1
            ctx.stroke()

            // Inner ring: always 8 equal slots (spec section 8.1).
            var inner = wheelGeometry.innerSlices
            var slotSweep = 2 * Math.PI / 8
            for (var i = 0; i < inner.length; i++) {
                var s = inner[i]
                var c = s.labelAngleDeg * Math.PI / 180
                var a0 = c - slotSweep / 2
                var a1 = c + slotSweep / 2
                var hovered = (s.sliceId === wheelGeometry.hoveredSliceId)

                ctx.beginPath()
                ctx.arc(cx, cy, R, a0, a1)
                ctx.arc(cx, cy, innerR, a1, a0, true)
                ctx.closePath()
                ctx.fillStyle = hovered ? "#4a4a5a"
                                        : (s.isCategory ? "#3a3a4a" : "#2d2d3a")
                ctx.fill()
                ctx.strokeStyle = "#4a4a5a"
                ctx.stroke()

                ctx.save()
                ctx.translate(cx, cy)
                ctx.rotate(c)
                ctx.textAlign = "center"
                ctx.textBaseline = "middle"
                ctx.font = "12px sans-serif"
                ctx.fillStyle = hovered ? "#ffffff" : "#cccccc"
                ctx.fillText(s.label, 0, -(innerR + R) / 2)
                ctx.restore()
            }

            // Outer fan (responsive partial ring, spec section 9.1).
            if (wheelGeometry.hasOuterFan) {
                var outer = wheelGeometry.outerFan
                var outerSweep = 20 * Math.PI / 180
                for (var j = 0; j < outer.length; j++) {
                    var o = outer[j]
                    var oc = o.labelAngleDeg * Math.PI / 180
                    var b0 = oc - outerSweep / 2
                    var b1 = oc + outerSweep / 2
                    var oh = (o.sliceId === wheelGeometry.hoveredSliceId)

                    ctx.beginPath()
                    ctx.arc(cx, cy, fanOuter, b0, b1)
                    ctx.arc(cx, cy, fanInner, b1, b0, true)
                    ctx.closePath()
                    ctx.fillStyle = oh ? "#4a4a5a" : "#3a3a4a"
                    ctx.fill()
                    ctx.strokeStyle = "#4a4a5a"
                    ctx.stroke()

                    ctx.save()
                    ctx.translate(cx, cy)
                    ctx.rotate(oc)
                    ctx.textAlign = "center"
                    ctx.textBaseline = "middle"
                    ctx.font = "11px sans-serif"
                    ctx.fillStyle = oh ? "#ffffff" : "#cccccc"
                    ctx.fillText(o.label, 0, -(fanInner + fanOuter) / 2)
                    ctx.restore()
                }
            }

            // Center hub
            ctx.beginPath()
            ctx.arc(cx, cy, innerR, 0, Math.PI * 2)
            ctx.fillStyle = "#14141e"
            ctx.fill()
            ctx.strokeStyle = "#4a4a5a"
            ctx.stroke()
        }

        Connections {
            target: wheelGeometry
            function onGeometryChanged() { canvas.requestPaint() }
            function onHoverChanged()    { canvas.requestPaint() }
        }
    }

    // -----------------------------------------------------------------------
    // Pointer tracking
    //
    // Hover only: the wheel is hotkey-driven, never clicked. The last known
    // position is used to commit when the hotkey is released.
    // -----------------------------------------------------------------------
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton

        onPositionChanged: {
            wheelCanvas.lastX = mouseX
            wheelCanvas.lastY = mouseY
            wheelGeometry.handlePointerMove(mouseX, mouseY)
        }
    }
}