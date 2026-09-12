#include "SchemaValidator.h"

#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>

QString SchemaValidator::s_lastError;

namespace {

// Pages are fixed concepts supplied by DaVinci Resolve (spec section 2.1).
const QSet<QString>& allowedPages()
{
    static const QSet<QString> pages = {
        QStringLiteral("media"),   QStringLiteral("cut"),
        QStringLiteral("edit"),    QStringLiteral("fusion"),
        QStringLiteral("color"),   QStringLiteral("fairlight"),
        QStringLiteral("deliver")
    };
    return pages;
}

constexpr int kMaxInnerSlices = 8;    // spec section 8.1
constexpr int kMaxOuterCommands = 16; // spec section 8.2
constexpr int kSupportedSchemaVersion = 3;

bool fail(QString& out, const QString& message)
{
    out = message;
    qCritical().noquote() << "Configuration rejected:" << message;
    return false;
}

// The Menu validates the structural invariants it depends on at runtime.
// Studio performs the same checks before publishing; the Menu must not
// silently reinterpret incompatible data if a file arrives from elsewhere
// (spec section 4).
bool checkProfile(const QJsonObject& profile, QString& err)
{
    if (!profile.contains(QStringLiteral("id")) || profile.value(QStringLiteral("id")).toString().isEmpty())
        return fail(err, QStringLiteral("profile is missing an id"));

    if (!profile.contains(QStringLiteral("name")))
        return fail(err, QStringLiteral("profile is missing a name"));

    const QJsonArray inner = profile.value(QStringLiteral("innerRing")).toArray();
    if (inner.size() > kMaxInnerSlices)
        return fail(err, QStringLiteral("profile has more than %1 inner slices").arg(kMaxInnerSlices));

    for (const QJsonValue& v : inner) {
        const QJsonObject slice = v.toObject();
        const QString type = slice.value(QStringLiteral("type")).toString();
        if (type != QLatin1String("command") && type != QLatin1String("category"))
            return fail(err, QStringLiteral("inner slice has an unknown type: %1").arg(type));

        if (type == QLatin1String("command") && !slice.contains(QStringLiteral("command")))
            return fail(err, QStringLiteral("command slice has no command reference"));

        if (type == QLatin1String("category")) {
            const QJsonObject cat = slice.value(QStringLiteral("category")).toObject();
            if (cat.isEmpty())
                return fail(err, QStringLiteral("category slice has no category definition"));
            const QJsonArray outer = cat.value(QStringLiteral("outerCommands")).toArray();
            if (outer.size() > kMaxOuterCommands)
                return fail(err, QStringLiteral("category has more than %1 commands").arg(kMaxOuterCommands));
        }
    }

    return true;
}

} // namespace

bool SchemaValidator::validate(const QByteArray& jsonData)
{
    s_lastError.clear();

    QJsonParseError parseError{};
    const QJsonDocument doc = QJsonDocument::fromJson(jsonData, &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject())
        return fail(s_lastError, QStringLiteral("invalid JSON: %1").arg(parseError.errorString()));

    const QJsonObject root = doc.object();

    // Schema version gate: reject rather than reinterpret (spec section 4).
    const int version = root.value(QStringLiteral("schemaVersion")).toInt(-1);
    if (version != kSupportedSchemaVersion) {
        return fail(s_lastError,
                    QStringLiteral("unsupported schemaVersion %1 (expected %2)")
                        .arg(version)
                        .arg(kSupportedSchemaVersion));
    }

    // Required top-level keys.
    const QStringList required = {
        QStringLiteral("pages"),
        QStringLiteral("interactionSettings"),
        QStringLiteral("wheelSettings")
    };
    for (const QString& key : required) {
        if (!root.contains(key))
            return fail(s_lastError, QStringLiteral("missing required key: %1").arg(key));
    }

    // Pages.
    const QJsonObject pages = root.value(QStringLiteral("pages")).toObject();
    if (pages.isEmpty())
        return fail(s_lastError, QStringLiteral("configuration has no pages"));

    for (auto it = pages.constBegin(); it != pages.constEnd(); ++it) {
        if (!allowedPages().contains(it.key()))
            return fail(s_lastError, QStringLiteral("unknown Resolve page: %1").arg(it.key()));

        const QJsonObject pageObj = it.value().toObject();
        const QJsonArray profiles = pageObj.value(QStringLiteral("profiles")).toArray();
        if (profiles.isEmpty())
            return fail(s_lastError,
                        QStringLiteral("page '%1' has no profiles").arg(it.key()));

        int defaultCount = 0;
        for (const QJsonValue& v : profiles) {
            const QJsonObject profile = v.toObject();
            if (!checkProfile(profile, s_lastError))
                return false;
            if (profile.value(QStringLiteral("isDefault")).toBool())
                ++defaultCount;
        }

        if (defaultCount != 1) {
            return fail(s_lastError,
                        QStringLiteral("page '%1' must have exactly one default profile (found %2)")
                            .arg(it.key())
                            .arg(defaultCount));
        }
    }

    // Interaction settings.
    const QJsonObject interaction = root.value(QStringLiteral("interactionSettings")).toObject();
    if (!interaction.contains(QStringLiteral("wheelActivationHotkey"))
        || interaction.value(QStringLiteral("wheelActivationHotkey")).toString().isEmpty()) {
        return fail(s_lastError, QStringLiteral("wheelActivationHotkey is not set"));
    }

    // Wheel settings: the slice limits are fixed by the product (spec section 8).
    const QJsonObject wheel = root.value(QStringLiteral("wheelSettings")).toObject();
    if (wheel.value(QStringLiteral("maxInnerSlices")).toInt(kMaxInnerSlices) != kMaxInnerSlices)
        return fail(s_lastError, QStringLiteral("maxInnerSlices must be %1").arg(kMaxInnerSlices));
    if (wheel.value(QStringLiteral("maxOuterCommands")).toInt(kMaxOuterCommands) != kMaxOuterCommands)
        return fail(s_lastError, QStringLiteral("maxOuterCommands must be %1").arg(kMaxOuterCommands));

    return true;
}

QString SchemaValidator::lastError()
{
    return s_lastError;
}