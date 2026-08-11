// 导出导航配置
import { MomentPageMap } from './src/main/ets/pages/momentNavigationConfig';

export { MomentPageMap, MOMENT_NAV_DESTINATION_PREFIX, momentNavigationDestinations } from './src/main/ets/pages/momentNavigationConfig';

// 供 chat 模块动态 import 后注册路由使用（Navigation 的 NavDestination 全局 @Builder 需要 wrapBuilder 包装）
export const wrappedMomentPageMap: WrappedBuilder<[string]> = wrapBuilder(MomentPageMap);

// 导出主要页面
export { FeedListPage } from './src/main/ets/pages/FeedListPage';
export { PostFeedPage } from './src/main/ets/pages/PostFeedPage';
export { FeedDetailPage } from './src/main/ets/pages/FeedDetailPage';
export { FeedMessagesPage } from './src/main/ets/pages/FeedMessagesPage';
export { MomentPrivacySettingsPage } from './src/main/ets/pages/MomentPrivacySettingsPage';

// 导出组件
export { FeedItemComponent } from './src/main/ets/components/FeedItemComponent';
export { FeedHeaderComponent } from './src/main/ets/components/FeedHeaderComponent';
export { NineGridView } from './src/main/ets/components/NineGridView';
export { CommentWidget } from './src/main/ets/components/CommentWidget';
export { FeedImagePreviewDialog } from './src/main/ets/components/FeedImagePreviewDialog';
export { FeedVideoPlayerDialog } from './src/main/ets/components/FeedVideoPlayerDialog';

// 导出模型
export { FeedViewModel, FeedListState, FeedInteractionEvents, CommentInputState} from './src/main/ets/model/FeedViewModel';

// 导出工具
export { MomentConstants, TimeFormatter } from './src/main/ets/utils/MomentConstants';

// 导出数据层模型
export { Feed, FeedEntry, Comment, Profile, FeedContentType, FeedCommentType, UpdateUserProfileType, VisibleScope } from './src/main/ets/model/MomentModel';

// 导出数据层客户端
export { momentClient, MomentClient } from './src/main/ets/client/MomentClient';

// 导出媒体上传
export { uploadImage, uploadVideo, uploadMomentMedia } from './src/main/ets/utils/MomentUpload';
