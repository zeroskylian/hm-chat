import { FeedListPage } from './FeedListPage';
import { PostFeedPage } from './PostFeedPage';
import { FeedDetailPage } from './FeedDetailPage';
import { FeedMessagesPage } from './FeedMessagesPage';
import { MomentPrivacySettingsPage } from './MomentPrivacySettingsPage';

export const MOMENT_NAV_DESTINATION_PREFIX = 'moment_'

export class momentNavigationDestinations {
    static FeedListPage = MOMENT_NAV_DESTINATION_PREFIX + 'feedListPage'
    static PostFeedPage = MOMENT_NAV_DESTINATION_PREFIX + 'postFeedPage'
    static FeedDetailPage = MOMENT_NAV_DESTINATION_PREFIX + 'feedDetailPage'
    static FeedMessagesPage = MOMENT_NAV_DESTINATION_PREFIX + 'feedMessagesPage'
    static PrivacySettingsPage = MOMENT_NAV_DESTINATION_PREFIX + 'privacySettingsPage'
}

@Builder
export function MomentPageMap(name: string) {
    if (name === momentNavigationDestinations.FeedListPage) {
        FeedListPage()
    } else if (name === momentNavigationDestinations.PostFeedPage) {
        PostFeedPage()
    } else if (name === momentNavigationDestinations.FeedDetailPage) {
        FeedDetailPage()
    } else if (name === momentNavigationDestinations.FeedMessagesPage) {
        FeedMessagesPage()
    } else if (name === momentNavigationDestinations.PrivacySettingsPage) {
        MomentPrivacySettingsPage()
    } else {
        NavDestination() {
        }
    }
}
