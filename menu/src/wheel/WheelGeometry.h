#pragma once

#include <QObject>
#include <QPointF>
#include <QPolygonF>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QVector>
#include <QUuid>

#include "config/generated/ConfigTypes.h"

// Runtime geometry for the Macro Wheel (spec section 9.2).
//
// Studio stores only semantic configuration (slice order, type, category
// relationship, command assignment). This class derives every angle, radius
// and hit-test polygon at runtime, and re-derives them only when an input
// changes:
//   - active profile changes
//   - selected category changes
//   - command count changes
//   - viewport (wheel) size changes
//
// All QML-facing accessors return value types (QVariantList / QVariantMap) so
// the QML layer never touches C++ structs directly.
class WheelGeometry : public QObject
{
    Q_OBJECT

    Q_PROPERTY(double wheelRadius READ wheelRadius NOTIFY geometryChanged)
    Q_PROPERTY(bool hasOuterFan READ hasOuterFan NOTIFY geometryChanged)
    Q_PROPERTY(QVariantList innerSlices READ innerSlicesForQml NOTIFY geometryChanged)
    Q_PROPERTY(QVariantList outerFan READ outerFanForQml NOTIFY geometryChanged)
    Q_PROPERTY(QString hoveredSliceId READ hoveredSliceId NOTIFY hoverChanged)

public:
    explicit WheelGeometry(QObject* parent = nullptr);

    double wheelRadius() const { return m_wheelRadius; }
    bool hasOuterFan() const { return !m_outerFan.isEmpty(); }
    QVariantList innerSlicesForQml() const;
    QVariantList outerFanForQml() const;
    QString hoveredSliceId() const { return m_hoveredSliceId; }

    // Called by the overlay when it (re)opens, before geometry is used.
    Q_INVOKABLE void setViewportSize(double width, double height);

    // Rebuild for the given profile. Called on profile change and on open.
    void buildForProfile(const Profile* profile);

    // QML entry point: x/y in viewport coordinates.
    // Returns { "hit": bool, "ring": "inner"|"outer", "sliceId": ..., "isCategory": bool, "label": ... }
    Q_INVOKABLE QVariantMap hitTest(double x, double y);

    // Called on pointer move while the wheel is open. Updates hover state and
    // auto-expands/collapses the outer fan as the pointer enters or leaves a
    // category slice. Never executes a command.
    Q_INVOKABLE void handlePointerMove(double x, double y);

    // QML entry point when the hotkey is released over a slice.
    // Returns true if a command was executed (caller should close the wheel),
    // false if a category was opened (caller keeps the wheel open).
    Q_INVOKABLE bool activateAt(double x, double y);

    Q_INVOKABLE void cancelSelection();

public slots:
    void onActiveProfileChanged(const Profile* profile);

signals:
    void geometryChanged();
    void hoverChanged();
    // Emitted when a leaf command is committed. Payload is one of:
    //   { "type": "builtin",   "id": "<builtin id>" }
    //   { "type": "custom",    "id": "<uuid>" }
    //   { "type": "script",    "id": "<uuid>" }
    //   { "type": "addEffect", "payload": "<search text>", "name": "<label>" }
    void commandTriggered(const QVariantMap& command);

private:
    struct Slice {
        QUuid id;
        QString label;
        bool isCategory = false;
        QPolygonF polygon;
        double labelAngleDeg = 0;
        double labelRadius = 0;
        const CommandRef* command = nullptr;      // inner command slice
        const Category* category = nullptr;       // inner category slice
        const CommandRef* outerCommand = nullptr; // outer fan entry
    };

    void rebuildInnerRing();
    void rebuildOuterFan(const Category& category);
    void setHovered(const QString& sliceId);

    const Slice* findSliceAt(const QPointF& p, bool outer) const;

    static QVariantMap sliceToVariant(const Slice& s);
    static QVariantMap commandToVariant(const CommandRef& c);

    const Profile* m_profile = nullptr;
    QVector<Slice> m_innerSlices;
    QVector<Slice> m_outerFan;
    QUuid m_selectedCategoryId;
    QString m_hoveredSliceId;

    QPointF m_center{0.0, 0.0};
    double m_viewportWidth = 720.0;
    double m_viewportHeight = 720.0;
    double m_wheelRadius = 180.0;   // fixed in v1 (spec section 10)
};