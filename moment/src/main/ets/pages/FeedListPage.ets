import { momentClient } from '../client/MomentClient';
import { Feed, Comment, Profile, FeedEntry, FeedCommentType, UpdateUserProfileType } from '../model/MomentModel';
import { FeedViewModel, FeedInteractionEvents, CommentInputState } from '../model/FeedViewModel';
import { MomentConstants } from '../utils/MomentConstants';
import { uploadMomentMedia } from '../utils/MomentUpload';
import { FeedItemComponent } from '../components/FeedItemComponent';
import { FeedHeaderComponent } from '../components/FeedHeaderComponent';
import { FeedImagePreviewDialog } from '../components/FeedImagePreviewDialog';
import { FeedVideoPlayerDialog } from '../components/FeedVideoPlayerDialog';
import wfc from '@wfc/client';
import { momentNavigationDestinations } from './momentNavigationConfig';
import { uikitNavigationDestinations } from '@wfc/uikit/src/main/ets/pages/uikitNavigationConfig';
import { showToast } from '@wfc/uikit/src/main/ets/common/utils/Toast';
import { promptAction, KeyboardAvoidMode } from '@kit.ArkUI';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import { FontSize, Radius } from '@wfc/uikit/src/main/ets/common/design/Tokens'

const PAGE_SIZE = 20;

@Component
export struct FeedListPage {
    // 顶层 @State，保证数组的增删改能被观测刷新
    @State feeds: FeedViewModel[] = [];
    @State isLoading: boolean = false;
    @State isRefreshing: boolean = false;
    @State isLoadingMore: boolean = false;
    @State hasMore: boolean = true;
    @State errorMsg: string = '';
    @State commentInputState: CommentInputState = {
        isVisible: false,
        feedId: undefined,
        replyTo: undefined,
        replyToName: undefined,
        placeholder: '写评论...'
    };
    @State commentText: string = '';
    @State userProfile: Profile | undefined = undefined;
    // 路由参数：非空表示「某用户的朋友圈主页」，空表示自己的朋友圈首页
    @State pageUserId: string = '';

    // 未读数由数据层在收消息时写入 AppStorage
    @StorageProp('momentUnreadCount') unreadCount: number = 0;

    @State titleBarOpacity: number = 0;
    private listScroller: Scroller = new Scroller();

    @State previewImages: FeedEntry[] = [];
    @State previewIndex: number = 0;
    previewDialogController: CustomDialogController = new CustomDialogController({
        builder: FeedImagePreviewDialog({
            images: this.$previewImages,
            index: this.$previewIndex,
        }),
        customStyle: true,
        autoCancel: true,
        alignment: DialogAlignment.Center
    });

    @State previewVideoUrl: string = '';
    @State previewVideoThumb: string = '';
    videoDialogController: CustomDialogController = new CustomDialogController({
        builder: FeedVideoPlayerDialog({
            videoUrl: this.$previewVideoUrl,
            thumbUrl: this.$previewVideoThumb,
        }),
        customStyle: true,
        autoCancel: true,
        alignment: DialogAlignment.Center
    });

    private currentUserId: string = '';

    @Consume('mainNavPathStack') mainNavPathStack: NavPathStack;

    private isHome(): boolean {
        return this.pageUserId.length === 0;
    }

    // 头部展示的用户 id：首页是自己，用户主页是对方
    private headerUserId(): string {
        return this.isHome() ? this.currentUserId : this.pageUserId;
    }

    aboutToAppear() {
        this.currentUserId = wfc.getUserId();
        let params = this.mainNavPathStack.getParamByIndex(this.mainNavPathStack.size() - 1) as Record<string, Object>;
        if (params && typeof params['userId'] === 'string') {
            this.pageUserId = params['userId'] as string;
        }
        // 缓存秒开：先展示本地缓存，再网络刷新
        let cached = momentClient.feedsRestore(this.isHome() ? null : this.pageUserId);
        if (cached.length > 0) {
            this.feeds = cached.map(f => new FeedViewModel(f));
        }
        this.loadInitialFeeds();
        this.loadUserProfile();
        try {
            this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
        } catch (e) {}
    }

    private loadUserProfile() {
        momentClient.getUserProfile(this.headerUserId(), (profile: Profile) => {
            this.userProfile = profile;
        }, () => {});
    }

    private loadInitialFeeds() {
        this.isLoading = true;
        momentClient.getFeeds(0, PAGE_SIZE, this.isHome() ? null : this.pageUserId, (feeds: Feed[]) => {
            this.feeds = feeds.map(f => new FeedViewModel(f));
            this.hasMore = feeds.length >= PAGE_SIZE;
            this.isLoading = false;
            this.errorMsg = '';
        }, (errorCode: number) => {
            this.isLoading = false;
            this.errorMsg = `加载失败 (${errorCode})`;
        });
    }

    private onRefresh() {
        this.isRefreshing = true;
        momentClient.getFeeds(0, PAGE_SIZE, this.isHome() ? null : this.pageUserId, (feeds: Feed[]) => {
            this.feeds = feeds.map(f => new FeedViewModel(f));
            this.hasMore = feeds.length >= PAGE_SIZE;
            this.isRefreshing = false;
            this.errorMsg = '';
        }, () => {
            this.isRefreshing = false;
        });
    }

    private onLoadMore() {
        if (this.isLoadingMore || !this.hasMore) return;
        this.isLoadingMore = true;
        const lastFeed = this.feeds[this.feeds.length - 1];
        const fromIndex = lastFeed?.feed.feedId ?? 0;
        momentClient.getFeeds(fromIndex, PAGE_SIZE, this.isHome() ? null : this.pageUserId, (feeds: Feed[]) => {
            if (feeds.length === 0) {
                this.hasMore = false;
            } else {
                this.feeds = [...this.feeds, ...feeds.map(f => new FeedViewModel(f))];
                this.hasMore = feeds.length >= PAGE_SIZE;
            }
            this.isLoadingMore = false;
        }, () => {
            this.isLoadingMore = false;
        });
    }

    // 相机按钮：点击弹「从相册选择 / 发表文字」
    private showPublishMenu() {
        promptAction.showActionMenu({
            title: '',
            buttons: [
                { text: '从相册选择', color: $r('app.color.text_primary') },
                { text: '发表文字', color: $r('app.color.text_primary') }
            ]
        }).then(result => {
            if (result.index === 0) {
                this.pushPostFeedPage(false);
            } else if (result.index === 1) {
                this.pushPostFeedPage(true);
            }
        }).catch(() => {});
    }

    private pushPostFeedPage(textOnly: boolean) {
        this.mainNavPathStack.pushPathByName(momentNavigationDestinations.PostFeedPage, {
            'textOnly': textOnly
        } as Record<string, Object>);
    }

    // 封面点击：更新背景（仅自己的朋友圈首页）
    private onBackgroundClick() {
        if (!this.isHome()) return;
        promptAction.showActionMenu({
            title: '',
            buttons: [
                { text: '更新背景', color: $r('app.color.text_primary') }
            ]
        }).then(result => {
            if (result.index === 0) {
                this.pickAndUpdateBackground();
            }
        }).catch(() => {});
    }

    private async pickAndUpdateBackground() {
        try {
            const options = new photoAccessHelper.PhotoSelectOptions();
            options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
            options.maxSelectNumber = 1;
            const photoPicker = new photoAccessHelper.PhotoViewPicker();
            const photoUris = (await photoPicker.select(options)).photoUris;
            if (!photoUris || photoUris.length === 0) {
                return;
            }
            const url = await uploadMomentMedia(photoUris[0]);
            momentClient.updateMyProfile(UpdateUserProfileType.BackgroundUrl, url, null, () => {
                this.loadUserProfile();
            }, (errorCode: number) => {
                showToast(`设置失败 (${errorCode})`);
            });
        } catch (e) {
            // 用户取消选择或上传失败
        }
    }

    private interactionEvents: FeedInteractionEvents = {
        onLike: (feed: FeedViewModel) => {
            if (feed.isLiking) return;
            const feedId = feed.feed.feedId;
            if (feedId === undefined) return;
            feed.isLiking = true;
            const isLiked = feed.isLiked(this.currentUserId);
            if (isLiked) {
                const likeComment = feed.getLikesList().find(like => like.sender === this.currentUserId);
                if (likeComment && likeComment.commentId !== undefined) {
                    momentClient.deleteComment(likeComment.commentId, feedId, () => {
                        if (feed.feed.comments) {
                            const idx = feed.feed.comments.findIndex(c => c.commentId === likeComment.commentId);
                            if (idx !== -1) feed.feed.comments.splice(idx, 1);
                        }
                        feed.isLiking = false;
                        this.updateFeed(feed);
                    }, () => { feed.isLiking = false; });
                } else {
                    feed.isLiking = false;
                }
            } else {
                let comment = new Comment();
                comment.feedId = feedId;
                comment.type = FeedCommentType.Thumbup;
                comment.sender = this.currentUserId;
                momentClient.postComment(comment, (commentId: number, timestamp: number) => {
                    comment.commentId = commentId;
                    comment.serverTime = timestamp;
                    if (!feed.feed.comments) feed.feed.comments = [];
                    feed.feed.comments.push(comment);
                    feed.isLiking = false;
                    this.updateFeed(feed);
                }, () => { feed.isLiking = false; });
            }
        },

        onComment: (feed: FeedViewModel, commentText: string, replyTo?: string) => {
            if (feed.isCommenting || !commentText.trim()) return;
            const feedId = feed.feed.feedId;
            if (feedId === undefined) return;
            feed.isCommenting = true;
            let comment = new Comment();
            comment.feedId = feedId;
            comment.type = FeedCommentType.Comment;
            comment.sender = this.currentUserId;
            comment.text = commentText.trim();
            comment.replyTo = replyTo || undefined;
            momentClient.postComment(comment, (commentId: number, timestamp: number) => {
                comment.commentId = commentId;
                comment.serverTime = timestamp;
                if (!feed.feed.comments) feed.feed.comments = [];
                feed.feed.comments.push(comment);
                feed.isCommenting = false;
                this.updateFeed(feed);
                this.commentInputState.isVisible = false;
                this.commentText = '';
            }, () => { feed.isCommenting = false; });
        },

        onDelete: (feed: FeedViewModel) => {
            promptAction.showDialog({
                title: '删除动态',
                message: '确定要删除这条朋友圈吗？',
                buttons: [
                    { text: '取消', color: $r('app.color.text_secondary') },
                    { text: '删除', color: $r('app.color.like_active') }
                ]
            }).then(data => {
                if (data.index === 1 && feed.feed.feedId !== undefined) {
                    momentClient.deleteFeed(feed.feed.feedId, () => {
                        this.feeds = this.feeds.filter(f => f.feed.feedId !== feed.feed.feedId);
                    }, (errorCode: number) => {
                        showToast(`删除失败 (${errorCode})`);
                    });
                }
            }).catch(() => {});
        },

        onDeleteComment: (feed: FeedViewModel, comment: Comment) => {
            const feedId = feed.feed.feedId;
            if (feedId === undefined || comment.commentId === undefined) return;
            momentClient.deleteComment(comment.commentId, feedId, () => {
                if (feed.feed.comments) {
                    const idx = feed.feed.comments.findIndex(c => c.commentId === comment.commentId);
                    if (idx !== -1) feed.feed.comments.splice(idx, 1);
                }
                this.updateFeed(feed);
            }, (errorCode: number) => {
                showToast(`删除失败 (${errorCode})`);
            });
        },

        onUserClick: (userId: string) => {
            this.mainNavPathStack.pushPathByName(uikitNavigationDestinations.UserInfoPage, {
                'userId': userId
            } as Record<string, Object>);
        },

        onImageClick: (images: FeedEntry[], index: number) => {
            this.previewImages = images;
            this.previewIndex = index;
            this.previewDialogController.open();
        },

        onVideoClick: (videoUrl: string, thumbUrl: string) => {
            this.previewVideoUrl = videoUrl;
            this.previewVideoThumb = thumbUrl;
            this.videoDialogController.open();
        },

        onMoreComments: (feed: FeedViewModel) => {
            feed.showAllComments = true;
            this.updateFeed(feed);
        }
    };

    // 朋友圈互动（点赞/评论/展开）后刷新对应项：
    // 1) 递增 updateTime 使该项的 ForEach key 变化，强制重建该条目；
    // 2) 重新赋值数组引用，触发父组件 List 重新求值。
    private updateFeed(feed: FeedViewModel) {
        feed.markDirty();
        this.feeds = this.feeds.slice();
    }

    private showCommentInput(feed: FeedViewModel, listIndex: number, replyTo?: string, replyToName?: string) {
        this.commentInputState = {
            isVisible: true,
            feedId: feed.feed.feedId,
            replyTo,
            replyToName,
            placeholder: replyTo ? `回复 ${replyToName || replyTo}` : '写评论...'
        };
        setTimeout(() => {
            const targetIndex = listIndex + ((this.isHome() && this.unreadCount > 0) ? 2 : 1);
            this.listScroller.scrollToIndex(targetIndex, true, ScrollAlign.END);
        }, 300);
    }

    build() {
        NavDestination() {
            Stack({ alignContent: Alignment.Top }) {
                Stack({ alignContent: Alignment.Top }) {
                    Column() {
                        if (this.isLoading && this.feeds.length === 0) {
                            this.buildSkeletonView()
                        } else if (this.errorMsg && this.feeds.length === 0) {
                            this.buildErrorView()
                        } else {
                            this.buildFeedList()
                        }
                    }
                    .width('100%')
                    .height('100%')
                    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])

                    if (this.commentInputState.isVisible) {
                        this.buildCommentInput()
                    }
                }
                .width('100%')
                .height('100%')
                .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])

                // 自定义标题栏（绝对定位，不随键盘移动）
                this.buildCustomTitleBar()
            }
            .width('100%')
            .height('100%')
        }
        .hideTitleBar(true)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
        .onShown(() => {
            try { this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE); } catch (e) {}
            // 发布新朋友圈后返回时刷新列表
            if (AppStorage.get<boolean>('momentNeedRefresh')) {
                AppStorage.setOrCreate('momentNeedRefresh', false);
                this.onRefresh();
            }
        })
        .onHidden(() => {
            try { this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET); } catch (e) {}
        })
    }

    @Builder
    private buildCustomTitleBar() {
        Stack({ alignContent: Alignment.Top }) {
            // 背景
            Row()
                .width('100%')
                .height(48 + px2vp(AppStorage.get<number>('SafeAreaTopHeight') || 0))
                .backgroundColor(MomentConstants.BACKGROUND_COLOR)
                .opacity(this.titleBarOpacity)
                .blur(this.titleBarOpacity > 0 ? 20 : 0)

            Row() {
                // 返回按钮
                Button() {
                    SymbolGlyph($r('sys.symbol.chevron_backward'))
                        .fontSize(FontSize.xl)
                        .fontColor([this.titleBarOpacity > 0.5 ? $r('app.color.text_primary') : Color.White])
                }
                .width(40)
                .height(40)
                .type(ButtonType.Circle)
                .backgroundColor(Color.Transparent)
                .onClick(() => this.mainNavPathStack.pop())

                Blank()

                if (this.titleBarOpacity > 0.3) {
                    Text(this.isHome() ? '朋友圈' : wfc.getUserInfo(this.pageUserId).displayName)
                        .fontSize(MomentConstants.FONT_SIZE_TITLE)
                        .minFontScale(1)
                        .maxFontScale(1)
                        .fontWeight(FontWeight.Bold)
                        .fontColor($r('app.color.text_primary'))
                        .opacity(Math.min(this.titleBarOpacity * 2, 1))
                        .transition({ type: TransitionType.All, opacity: 0 })
                }

                Blank()

                // 相机按钮（用户朋友圈主页隐藏）
                if (this.isHome()) {
                    Button() {
                        SymbolGlyph($r('sys.symbol.camera'))
                            .fontSize(FontSize.xl)
                            .fontColor([this.titleBarOpacity > 0.5 ? $r('app.color.text_primary') : Color.White])
                    }
                    .width(40)
                    .height(40)
                    .type(ButtonType.Circle)
                    .backgroundColor(Color.Transparent)
                    .onClick(() => this.showPublishMenu())
                    .gesture(
                        LongPressGesture()
                            .onAction(() => this.pushPostFeedPage(true))
                    )
                } else {
                    Blank().width(40).height(40)
                }
            }
            .width('100%')
            .height(48 + px2vp(AppStorage.get<number>('SafeAreaTopHeight') || 0))
            .padding({ left: 8, right: 8, top: px2vp(AppStorage.get<number>('SafeAreaTopHeight') || 0) })
            .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .position({ x: 0, y: 0 })
        .zIndex(100)
    }

    // 骨架屏
    @Builder
    private buildSkeletonView() {
        Column() {
            // 封面骨架
            Column()
                .width('100%')
                .height(MomentConstants.COVER_HEIGHT + px2vp(AppStorage.get<number>('SafeAreaTopHeight') || 0) + MomentConstants.AVATAR_SIZE_LARGE / 2)
                .backgroundColor($r('app.color.skeleton_base'))

            // Feed 条目骨架（3条）
            ForEach([0, 1, 2], (_: number) => {
                this.buildSkeletonItem()
            })
        }
        .width('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    }

    @Builder
    private buildSkeletonItem() {
        Row() {
            // 头像骨架
            Column()
                .width(MomentConstants.AVATAR_SIZE)
                .height(MomentConstants.AVATAR_SIZE)
                .borderRadius(MomentConstants.BORDER_RADIUS)
                .backgroundColor($r('app.color.skeleton_base'))
                .margin({ right: 12 })

            Column({ space: 8 }) {
                // 用户名骨架
                Column()
                    .width('40%')
                    .height(16)
                    .borderRadius(Radius.sm)
                    .backgroundColor($r('app.color.skeleton_base'))
                // 文本骨架
                Column()
                    .width('90%')
                    .height(12)
                    .borderRadius(Radius.sm)
                    .backgroundColor($r('app.color.skeleton_highlight'))
                Column()
                    .width('70%')
                    .height(12)
                    .borderRadius(Radius.sm)
                    .backgroundColor($r('app.color.skeleton_highlight'))
                // 时间骨架
                Column()
                    .width('25%')
                    .height(12)
                    .borderRadius(Radius.sm)
                    .backgroundColor($r('app.color.skeleton_highlight'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: MomentConstants.CARD_PADDING, right: MomentConstants.CARD_PADDING, top: 16, bottom: 16 })
        .backgroundColor(MomentConstants.CARD_BACKGROUND_COLOR)

        Divider()
            .color(MomentConstants.DIVIDER_COLOR)
            .strokeWidth(0.5)
            .margin({ left: MomentConstants.CARD_PADDING + MomentConstants.AVATAR_SIZE + 10 })
    }

    @Builder
    private buildErrorView() {
        Column({ space: 16 }) {
            SymbolGlyph($r('sys.symbol.wifi_slash'))
                .fontSize(FontSize.huge)
                .fontColor([MomentConstants.TEXT_SECONDARY_COLOR])

            Text('加载失败')
                .fontSize(MomentConstants.FONT_SIZE_MEDIUM)
                .fontColor(MomentConstants.TEXT_SECONDARY_COLOR)

            Button('重新加载')
                .backgroundColor(MomentConstants.PRIMARY_COLOR)
                .fontColor(Color.White)
                .borderRadius(MomentConstants.BORDER_RADIUS)
                .padding({ left: 24, right: 24 })
                .height(40)
                .onClick(() => this.loadInitialFeeds())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
    }

    @Builder
    private buildFeedList() {
        Refresh({ refreshing: $$this.isRefreshing, offset: 64, friction: 100 }) {
            List({ space: 0, scroller: this.listScroller }) {
                // 顶部 Header
                ListItem() {
                    FeedHeaderComponent({
                        profile: this.userProfile,
                        userId: this.headerUserId(),
                        onBackgroundClick: (): void => this.onBackgroundClick()
                    })
                }

                // 未读提示（仅自己的朋友圈首页）
                if (this.isHome() && this.unreadCount > 0) {
                    ListItem() {
                        this.buildUnreadHint()
                    }
                }

                // Feed 列表
                ForEach(this.feeds, (feedItem: FeedViewModel, index: number) => {
                    ListItem() {
                        FeedItemComponent({
                            feedViewModel: feedItem,
                            currentUserId: this.currentUserId,
                            events: this.interactionEvents,
                            onCommentClick: (replyTo?: string, replyToName?: string) => {
                                this.showCommentInput(feedItem, index, replyTo, replyToName);
                            }
                        })
                    }
                }, (feedItem: FeedViewModel, index: number) => `feed_${feedItem.feed.feedId}_${feedItem.updateTime}`)

                // 加载更多 / 底部提示
                if (this.feeds.length === 0 && !this.isLoading) {
                    ListItem() { this.buildEmptyView() }
                } else if (this.hasMore) {
                    ListItem() {
                        this.buildLoadMoreView()
                    }
                    .onAppear(() => this.onLoadMore())
                } else if (this.feeds.length > 0) {
                    ListItem() {
                        Row({ space: 8 }) {
                            Divider().layoutWeight(1).color(MomentConstants.DIVIDER_COLOR).strokeWidth(0.5)
                            Text('以上是全部朋友圈')
                                .fontSize(MomentConstants.FONT_SIZE_CAPTION)
                                .fontColor(MomentConstants.TEXT_SECONDARY_COLOR)
                            Divider().layoutWeight(1).color(MomentConstants.DIVIDER_COLOR).strokeWidth(0.5)
                        }
                        .padding({ left: 20, right: 20, top: 20, bottom: 24 })
                        .alignItems(VerticalAlign.Center)
                    }
                }
            }
            .listDirection(Axis.Vertical)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.None)
            .onDidScroll(() => {
                const offset = this.listScroller.currentOffset().yOffset;
                let opacity = (offset - 120) / 80;
                this.titleBarOpacity = Math.max(0, Math.min(1, opacity));
                AppStorage.setOrCreate('closeFeedMenuTime', Date.now());
            })
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
        }
        .onRefreshing(() => this.onRefresh())
        .layoutWeight(1)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    }

    @Builder
    private buildUnreadHint() {
        Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.bell'))
                .fontSize(FontSize.sm)
                .fontColor([MomentConstants.LINK_COLOR])

            Text(`您有${this.unreadCount}条未读消息`)
                .fontSize(FontSize.sm)
                .fontColor(MomentConstants.LINK_COLOR)
                .fontWeight(FontWeight.Medium)
                .layoutWeight(1)

            SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(FontSize.sm)
                .fontColor([MomentConstants.LINK_COLOR])
        }
        .height(36)
        .padding({ left: 16, right: 16 })
        .borderRadius(MomentConstants.BORDER_RADIUS_SMALL)
        .backgroundColor(MomentConstants.INTERACTIONS_BACKGROUND_COLOR)
        .margin({ top: 8, bottom: 8, left: 90, right: 90 })
        .onClick(() => {
            this.mainNavPathStack.pushPathByName(momentNavigationDestinations.FeedMessagesPage, {} as Record<string, Object>);
        })
    }

    @Builder
    private buildEmptyView() {
        Column({ space: 16 }) {
            SymbolGlyph($r('sys.symbol.person_2'))
                .fontSize(FontSize.huge)
                .fontColor([MomentConstants.TEXT_SECONDARY_COLOR])

            Text('还没有朋友圈动态')
                .fontSize(MomentConstants.FONT_SIZE_MEDIUM)
                .fontColor(MomentConstants.TEXT_SECONDARY_COLOR)

            Text('去分享你的精彩瞬间吧')
                .fontSize(MomentConstants.FONT_SIZE_SMALL)
                .fontColor(MomentConstants.TEXT_SECONDARY_COLOR)
        }
        .width('100%')
        .padding({ top: 80, bottom: 40 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
    }

    @Builder
    private buildLoadMoreView() {
        Row({ space: 8 }) {
            if (this.isLoadingMore) {
                LoadingProgress()
                    .width(20)
                    .height(20)
                    .color(MomentConstants.TEXT_SECONDARY_COLOR)
                Text('加载中...')
                    .fontSize(MomentConstants.FONT_SIZE_CAPTION)
                    .fontColor(MomentConstants.TEXT_SECONDARY_COLOR)
            }
        }
        .width('100%')
        .height(48)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
    }

    @Builder
    private buildCommentInput() {
        Column() {
            // 半透明遮罩
            Row()
                .width('100%')
                .layoutWeight(1)
                .backgroundColor($r('app.color.mask_light'))
                .onClick(() => {
                    this.commentInputState.isVisible = false;
                    this.commentText = '';
                })

            // 输入框
            Row({ space: 12 }) {
                TextInput({
                    placeholder: this.commentInputState.placeholder,
                    text: this.commentText
                })
                    .id('comment_input')
                    .layoutWeight(1)
                    .height(40)
                    .backgroundColor(MomentConstants.BACKGROUND_COLOR)
                    .fontColor(MomentConstants.TEXT_PRIMARY_COLOR)
                    .fontSize(MomentConstants.FONT_SIZE_CONTENT)
                    .placeholderColor(MomentConstants.TEXT_SECONDARY_COLOR)
                    .borderRadius(Radius.full)
                    .padding({ left: 16, right: 16 })
                    .maxLength(500)
                    .defaultFocus(true)
                    .onAppear(() => {
                        setTimeout(() => {
                            focusControl.requestFocus('comment_input');
                        }, 80);
                    })
                    .onChange((value: string) => {
                        this.commentText = value;
                    })
                    .onSubmit(() => {
                        const targetFeed = this.feeds.find(f => f.feed.feedId === this.commentInputState.feedId);
                        if (targetFeed && this.commentText.trim()) {
                            this.interactionEvents.onComment(targetFeed, this.commentText, this.commentInputState.replyTo);
                        }
                    })

                Button('发送')
                    .height(40)
                    .padding({ left: 20, right: 20 })
                    .backgroundColor(this.commentText.trim() ? MomentConstants.PRIMARY_COLOR : $r('app.color.button_disabled'))
                    .fontColor(this.commentText.trim() ? Color.White : $r('app.color.text_disabled'))
                    .fontSize(MomentConstants.FONT_SIZE_MEDIUM)
                    .borderRadius(Radius.full)
                    .enabled(!!this.commentText.trim())
                    .onClick(() => {
                        const targetFeed = this.feeds.find(f => f.feed.feedId === this.commentInputState.feedId);
                        if (targetFeed) {
                            this.interactionEvents.onComment(targetFeed, this.commentText, this.commentInputState.replyTo);
                        }
                    })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .backgroundColor(MomentConstants.CARD_BACKGROUND_COLOR)
        }
        .width('100%')
        .height('100%')
        .zIndex(999)
    }
}
