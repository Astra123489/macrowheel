#include "ProfileResolver.h"
#include "config/ConfigService.h"
#include "resolve/ResolveConnection.h"

#include <QDebug>

ProfileResolver::ProfileResolver(ConfigService* configService,
                                 ResolveConnection* resolveConnection,
                                 QObject* parent)
    : QObject(parent)
    , m_configService(configService)
    , m_resolveConnection(resolveConnection)
{
    // Initialize with the current page if Resolve is already connected.
    if (resolveConnection->isConnected()) {
        selectProfileForPage(resolveConnection->currentPage());
        m_activePage = resolveConnection->currentPage();
    }
}

void ProfileResolver::onPageChanged(const QString& pageName)
{
    if (m_activePage == pageName)
        return; // No page change: never rebuild the active profile (spec 7.1).

    m_activePage = pageName;
    selectProfileForPage(pageName);
    emit activePageChanged(pageName);
}

void ProfileResolver::onConfigurationChanged(const RuntimeConfig& newConfig)
{
    Q_UNUSED(newConfig);
    // Re-select profile for current page in case profiles changed
    if (!m_activePage.isEmpty()) {
        selectProfileForPage(m_activePage);
    }
}

void ProfileResolver::onActiveProfileChanged()
{
    if (m_activeProfile) {
        emit activeProfileChanged(m_activeProfile);
    }
}

void ProfileResolver::selectProfileForPage(const QString& pageName)
{
    const RuntimeConfig& config = m_configService->currentConfig();
    auto it = config.pages.find(pageName);
    if (it == config.pages.end()) {
        qWarning() << "No configuration for page:" << pageName;
        m_activeProfile = nullptr;
        m_activeProfileId = QUuid();
        onActiveProfileChanged();
        return;
    }

    const PageConfig& pageConfig = *it;
    
    // Try to get last active profile for this page
    QUuid profileId;
    auto lastIt = m_lastActiveProfilePerPage.find(pageName);
    if (lastIt != m_lastActiveProfilePerPage.end()) {
        profileId = *lastIt;
        const Profile* profile = findProfileById(pageConfig, profileId);
        if (profile) {
            m_activeProfile = profile;
            m_activeProfileId = profileId;
            onActiveProfileChanged();
            return;
        }
    }

    // Fall back to default profile
    const Profile* defaultProfile = findDefaultProfile(pageConfig);
    if (defaultProfile) {
        m_activeProfile = defaultProfile;
        m_activeProfileId = defaultProfile->id;
        m_lastActiveProfilePerPage[pageName] = defaultProfile->id;
        onActiveProfileChanged();
        return;
    }

    // No profiles at all (shouldn't happen if validation works)
    qWarning() << "No valid profile found for page:" << pageName;
    m_activeProfile = nullptr;
    m_activeProfileId = QUuid();
    onActiveProfileChanged();
}

const Profile* ProfileResolver::findDefaultProfile(const PageConfig& pageConfig) const
{
    for (const Profile& profile : pageConfig.profiles) {
        if (profile.isDefault) {
            return &profile;
        }
    }
    // If no default marked, return first
    if (!pageConfig.profiles.isEmpty()) {
        return &pageConfig.profiles.first();
    }
    return nullptr;
}

const Profile* ProfileResolver::findProfileById(const PageConfig& pageConfig, const QUuid& id) const
{
    for (const Profile& profile : pageConfig.profiles) {
        if (profile.id == id) {
            return &profile;
        }
    }
    return nullptr;
}

void ProfileResolver::cycleProfile()
{
    if (m_activePage.isEmpty() || !m_activeProfile) return;

    const RuntimeConfig& config = m_configService->currentConfig();
    auto it = config.pages.find(m_activePage);
    if (it == config.pages.end()) return;

    const PageConfig& pageConfig = *it;
    if (pageConfig.profiles.size() <= 1) return; // Nothing to cycle

    // Find current index
    int currentIndex = -1;
    for (int i = 0; i < pageConfig.profiles.size(); ++i) {
        if (pageConfig.profiles[i].id == m_activeProfileId) {
            currentIndex = i;
            break;
        }
    }

    if (currentIndex == -1) return;

    // Move to next (wrap around)
    int nextIndex = (currentIndex + 1) % pageConfig.profiles.size();
    const Profile& nextProfile = pageConfig.profiles[nextIndex];
    
    m_activeProfile = &nextProfile;
    m_activeProfileId = nextProfile.id;
    m_lastActiveProfilePerPage[m_activePage] = nextProfile.id;
    
    onActiveProfileChanged();
}