#pragma once

#include <QObject>
#include <QUuid>
#include <QMap>
#include "config/generated/ConfigTypes.h"

class ConfigService;
class ResolveConnection;

class ProfileResolver : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString activePage READ activePage NOTIFY activePageChanged)
    Q_PROPERTY(QString activeProfileName READ activeProfileName NOTIFY activeProfileChanged)

public:
    explicit ProfileResolver(ConfigService* configService, ResolveConnection* resolveConnection, QObject* parent = nullptr);
    
    const Profile* activeProfile() const { return m_activeProfile; }
    QString activePage() const { return m_activePage; }
    QString activeProfileName() const { return m_activeProfile ? m_activeProfile->name : QString(); }
    const QUuid& activeProfileId() const { return m_activeProfileId; }

    Q_INVOKABLE void cycleProfile();

public slots:
    void onPageChanged(const QString& pageName);
    void onConfigurationChanged(const RuntimeConfig& newConfig);
    void onActiveProfileChanged();

signals:
    void activeProfileChanged(const Profile* profile);
    void activePageChanged(const QString& pageName);

private:
    void selectProfileForPage(const QString& pageName);
    const Profile* findDefaultProfile(const PageConfig& pageConfig) const;
    const Profile* findProfileById(const PageConfig& pageConfig, const QUuid& id) const;

    ConfigService* m_configService;
    ResolveConnection* m_resolveConnection;
    QMap<QString, QUuid> m_lastActiveProfilePerPage; // page -> profileId
    const Profile* m_activeProfile = nullptr;
    QUuid m_activeProfileId;
    QString m_activePage;
};