#include "WheelGeometry.h"

#include <QDebug>
#include <QtMath>
#include <cmath>

namespace {

// Inner ring is always drawn as 8 equal sectors regardless of slice count
// (spec section 8.1), so an under-filled ring stays visually circular.
constexpr int kInnerSlots = 8;
constexpr int kMaxOuterCommands = 16;
constexpr double kInnerHoleRatio = 0.30;   // inner radius / wheel radius
constexpr double kFanInnerRatio = 1.10;
constexpr double kFanOuterRatio = 1.80;
constexpr double kMinFanSpanDeg = 45.0;    // span for a single command
constexpr double kMaxFanSpanDeg = 360.0;   // span at 16 commands
constexpr double kOuterSliceSweepDeg = 20.0;

// Angular half-width used for hit-testing one outer command.
// Keeps adjacent wedges from overlapping at high command counts.
double outerHitHalfSweep(int commandCount)
{
    if (commandCount <= 1) return kMinFanSpanDeg / 2.0;
    const double span = qMin(kMaxFanSpanDeg,
                             kMinFanSpanDeg
                                 + (kMaxFanSpanDeg - kMinFanSpanDeg)
                                       * (qMin(commandCount, kMaxOuterCommands) / 16.0));
    const double step = span / (commandCount - 1);
    return qMax(6.0, qMin(step / 2.0, kOuterSliceSweepDeg));
}

} // namespace

WheelGeometry::WheelGeometry(QObject* parent)
    : QObject(parent)
{
}

// ---------------------------------------------------------------------------
// Viewport
// ---------------------------------------------------------------------------

void WheelGeometry::setViewportSize(double width, double height)
{
    if (qFuzzyCompare(width, m_viewportWidth) && qFuzzyCompare(height, m_viewportHeight))
        return;

    m_viewportWidth = width;
    m_viewportHeight = height;
    m_center = QPointF(width / 2.0, height / 2.0);

    // Polygons are absolute; rebuild them against the new centre.
    if (m_profile)
        buildForProfile(m_profile);
}

// ---------------------------------------------------------------------------
// Build
// ---------------------------------------------------------------------------

void WheelGeometry::onActiveProfileChanged(const Profile* profile)
{
    buildForProfile(profile);
}

void WheelGeometry::buildForProfile(const Profile* profile)
{
    m_profile = profile;
    m_selectedCategoryId = QUuid();
    m_outerFan.clear();
    m_hoveredSliceId.clear();
    rebuildInnerRing();
    emit hoverChanged();
    emit geometryChanged();
}

void WheelGeometry::rebuildInnerRing()
{
    m_innerSlices.clear();
    if (!m_profile || m_profile->innerRing.isEmpty())
        return;

    const double sliceSweep = 360.0 / kInnerSlots;
    const double startAngle = -90.0; // first slice starts at the top
    const double innerR = m_wheelRadius * kInnerHoleRatio;
    const double outerR = m_wheelRadius;
    const int segments = 24;

    const QVector<InnerSlice>& src = m_profile->innerRing;
    for (int i = 0; i < src.size(); ++i) {
        const InnerSlice& in = src.at(i);

        Slice s;
        s.id = in.id;
        s.isCategory = (in.type == InnerSlice::Type::Category);
        s.label = in.label.isEmpty()
                      ? (s.isCategory ? in.category.name : in.command.commandId)
                      : in.label;
        s.command = s.isCategory ? nullptr : &in.command;
        s.category = s.isCategory ? &in.category : nullptr;

        const double a0 = startAngle + i * sliceSweep;
        const double a1 = a0 + sliceSweep;

        QPolygonF poly;
        for (int k = 0; k <= segments; ++k) {
            const double a = qDegreesToRadians(a0 + (a1 - a0) * k / segments);
            poly << QPointF(m_center.x() + outerR * std::cos(a),
                            m_center.y() + outerR * std::sin(a));
        }
        for (int k = segments; k >= 0; --k) {
            const double a = qDegreesToRadians(a0 + (a1 - a0) * k / segments);
            poly << QPointF(m_center.x() + innerR * std::cos(a),
                            m_center.y() + innerR * std::sin(a));
        }

        s.polygon = poly;
        s.labelAngleDeg = a0 + sliceSweep / 2.0;
        s.labelRadius = (innerR + outerR) / 2.0;

        m_innerSlices.append(s);
    }
}

void WheelGeometry::rebuildOuterFan(const Category& category)
{
    m_outerFan.clear();

    const QVector<CommandRef>& commands = category.outerCommands;
    const int count = qMin(commands.size(), kMaxOuterCommands);
    if (count == 0)
        return;

    // The selected category slice is the anchor: the fan is centred on it
    // (spec section 9).
    double anchorAngle = -90.0;
    for (const Slice& s : m_innerSlices) {
        if (s.category && s.category->id == category.id) {
            anchorAngle = s.labelAngleDeg;
            break;
        }
    }

    const double span = qMin(kMaxFanSpanDeg,
                             kMinFanSpanDeg
                                 + (kMaxFanSpanDeg - kMinFanSpanDeg) * (count / 16.0));
    const double start = anchorAngle - span / 2.0;
    const double step = (count > 1) ? span / (count - 1) : 0.0;

    const double innerR = m_wheelRadius * kFanInnerRatio;
    const double outerR = m_wheelRadius * kFanOuterRatio;
    const double halfSweep = outerHitHalfSweep(count);
    const int segments = 12;

    for (int i = 0; i < count; ++i) {
        const CommandRef& cmd = commands.at(i);
        const double a = start + i * step;

        Slice s;
        s.id = QUuid::createUuid(); // transient hit-test identity
        s.isCategory = false;
        s.outerCommand = &cmd;
        s.label = cmd.effectName.isEmpty() ? cmd.commandId : cmd.effectName;
        s.labelAngleDeg = a;
        s.labelRadius = (innerR + outerR) / 2.0;

        QPolygonF poly;
        for (int k = 0; k <= segments; ++k) {
            const double aa = qDegreesToRadians(a - halfSweep + 2.0 * halfSweep * k / segments);
            poly << QPointF(m_center.x() + outerR * std::cos(aa),
                            m_center.y() + outerR * std::sin(aa));
        }
        for (int k = segments; k >= 0; --k) {
            const double aa = qDegreesToRadians(a - halfSweep + 2.0 * halfSweep * k / segments);
            poly << QPointF(m_center.x() + innerR * std::cos(aa),
                            m_center.y() + innerR * std::sin(aa));
        }
        s.polygon = poly;

        m_outerFan.append(s);
    }
}

// ---------------------------------------------------------------------------
// Hit testing
// ---------------------------------------------------------------------------

const WheelGeometry::Slice* WheelGeometry::findSliceAt(const QPointF& p, bool outer) const
{
    const QVector<Slice>& list = outer ? m_outerFan : m_innerSlices;
    for (const Slice& s : list) {
        if (s.polygon.containsPoint(p, Qt::OddEvenFill))
            return &s;
    }
    return nullptr;
}

QVariantMap WheelGeometry::hitTest(double x, double y)
{
    const QPointF p(x, y);

    if (!m_outerFan.isEmpty()) {
        if (const Slice* s = findSliceAt(p, true)) {
            setHovered(s->id.toString());
            return sliceToVariant(*s);
        }
    }

    if (const Slice* s = findSliceAt(p, false)) {
        setHovered(s->id.toString());
        return sliceToVariant(*s);
    }

    setHovered(QString());
    QVariantMap miss;
    miss.insert(QStringLiteral("hit"), false);
    return miss;
}

void WheelGeometry::handlePointerMove(double x, double y)
{
    const QPointF p(x, y);

    const Slice* innerHit = findSliceAt(p, false);
    const Slice* outerHit = m_outerFan.isEmpty() ? nullptr : findSliceAt(p, true);

    setHovered(outerHit ? outerHit->id.toString()
                        : (innerHit ? innerHit->id.toString() : QString()));

    if (!m_outerFan.isEmpty()) {
        // A fan is open. Only close it when the pointer is clearly back on
        // the inner ring (a non-category slice or empty space).
        if (!outerHit && (!innerHit || !innerHit->isCategory)) {
            m_outerFan.clear();
            m_selectedCategoryId = QUuid();
            emit geometryChanged();
        }
        return;
    }

    // No fan open. Expand a category the pointer is over.
    if (innerHit && innerHit->isCategory && innerHit->category) {
        m_selectedCategoryId = innerHit->category->id;
        rebuildOuterFan(*innerHit->category);
        emit geometryChanged();
    }
}

QVariantMap WheelGeometry::sliceToVariant(const Slice& s)
{
    QVariantMap m;
    m.insert(QStringLiteral("hit"), true);
    m.insert(QStringLiteral("sliceId"), s.id.toString());
    m.insert(QStringLiteral("label"), s.label);
    m.insert(QStringLiteral("isCategory"), s.isCategory);
    m.insert(QStringLiteral("ring"),
             s.outerCommand ? QStringLiteral("outer") : QStringLiteral("inner"));
    m.insert(QStringLiteral("labelAngleDeg"), s.labelAngleDeg);
    m.insert(QStringLiteral("labelRadius"), s.labelRadius);
    return m;
}

void WheelGeometry::setHovered(const QString& sliceId)
{
    if (m_hoveredSliceId == sliceId)
        return;
    m_hoveredSliceId = sliceId;
    emit hoverChanged();
}

// ---------------------------------------------------------------------------
// Activation
// ---------------------------------------------------------------------------

QVariantMap WheelGeometry::commandToVariant(const CommandRef& c)
{
    QVariantMap payload;
    switch (c.type) {
    case CommandRef::Type::Builtin:
        payload.insert(QStringLiteral("type"), QStringLiteral("builtin"));
        payload.insert(QStringLiteral("id"), c.commandId);
        break;
    case CommandRef::Type::Custom:
        payload.insert(QStringLiteral("type"), QStringLiteral("custom"));
        payload.insert(QStringLiteral("id"), c.commandId);
        break;
    case CommandRef::Type::Script:
        payload.insert(QStringLiteral("type"), QStringLiteral("script"));
        payload.insert(QStringLiteral("id"), c.scriptId.toString());
        break;
    case CommandRef::Type::AddEffect:
        payload.insert(QStringLiteral("type"), QStringLiteral("addEffect"));
        payload.insert(QStringLiteral("payload"), c.effectPayload);
        payload.insert(QStringLiteral("name"),
                       c.effectName.isEmpty() ? c.effectPayload : c.effectName);
        break;
    }
    return payload;
}

bool WheelGeometry::activateAt(double x, double y)
{
    const QPointF p(x, y);

    // The outer fan is drawn on top: test it first.
    if (!m_outerFan.isEmpty()) {
        if (const Slice* s = findSliceAt(p, true)) {
            if (s->outerCommand) {
                emit commandTriggered(commandToVariant(*s->outerCommand));
                return true;
            }
        }
        // Released outside an open fan: cancel rather than falling through to
        // the inner ring, which the user can no longer see.
        cancelSelection();
        return true;
    }

    if (const Slice* s = findSliceAt(p, false)) {
        if (s->isCategory && s->category) {
            m_selectedCategoryId = s->category->id;
            rebuildOuterFan(*s->category);
            emit geometryChanged();
            return false; // keep the wheel open
        }
        if (s->command) {
            emit commandTriggered(commandToVariant(*s->command));
            return true;
        }
    }

    cancelSelection();
    return true;
}

void WheelGeometry::cancelSelection()
{
    if (!m_outerFan.isEmpty()) {
        m_outerFan.clear();
        m_selectedCategoryId = QUuid();
        emit geometryChanged();
    }
    setHovered(QString());
}

// ---------------------------------------------------------------------------
// QML value conversion
// ---------------------------------------------------------------------------

QVariantList WheelGeometry::innerSlicesForQml() const
{
    QVariantList out;
    out.reserve(m_innerSlices.size());
    for (const Slice& s : m_innerSlices)
        out.append(sliceToVariant(s));
    return out;
}

QVariantList WheelGeometry::outerFanForQml() const
{
    QVariantList out;
    out.reserve(m_outerFan.size());
    for (const Slice& s : m_outerFan)
        out.append(sliceToVariant(s));
    return out;
}