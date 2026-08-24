import { momentClient } from '../client/MomentClient';
import { Feed, Comment, FeedEntry, FeedCommentType } from '../model/MomentModel';
import { FeedViewModel, FeedInteractionEvents, CommentInputState } from '../model/FeedViewModel';
import { MomentConstants } from '../utils/MomentConstants';
import { FeedItemComponent } from '../components/FeedItemComponent';
import { FeedImagePreviewDialog } from '../components/FeedImagePreviewDialog';
import { FeedVideoPlayerDialog } from '../components/FeedVideoPlayerDialog';
import wfc from '@wfc/client';
import { momentNavigationDestinations } from './momentNavigationConfig';
import { showToast } from '@wfc/uikit/src/main/ets/common/utils/Toast';
import { promptAction, KeyboardAvoidMode } from '@kit.ArkUI';
import { FontSize, Radius } from '@wfc/uikit/src/main/ets/common/design/Tokens'

/**
 * 单条朋友圈详情页。
 * 路由参数：{ feedId: string }（int64 的十进制字符串）
 */
@Component
export struct FeedDetailPage {
    @State feedViewModel: FeedViewModel | undefined = undefined;
    @State loadFailed: boolean = false;
    @State commentInputState: CommentInputState = {
        isVisible: false,
        feedId: undefined,
        replyTo: undefined,
        replyToName: undefined,
        placeholder: '写评论...'
    };
    @State commentText: string = '';

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

    private feedId: string = '';
    private currentUserId: string = '';

    @Consume('mainNavPathStack') mainNavPathStack: NavPathStack;

    aboutToAppear() {
        this.currentUserId = wfc.getUserId();
        let params = this.mainNavPathStack.getParamByIndex(this.mainNavPathStack.size() - 1) as Record<string, Object>;
        if (params) {
            let id = params['feedId'];
            if (typeof id === 'string') {
                this.feedId = id;
            } else if (typeof id === 'number' && id > 0) {
                this.feedId = id.toString();
            }
        }
        this.loadFeed();
        try {
            this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
        } catch (e) {}
    }

    private loadFeed() {
        if (!this.feedId) {
            this.loadFailed = true;
            return;
        }
        // 网络失败时用本地缓存兜底，避免“内容不存在或已删除”误报
        if (!this.feedViewModel) {
            let cached = momentClient.feedsRestore(null).find(f => f.feedId === this.feedId);
            if (!cached) {
                cached = momentClient.feedsRestore(this.currentUserId).find(f => f.feedId === this.feedId);
            }
            if (cached) {
                this.feedViewModel = new FeedViewModel(cached);
            }
        }
        momentClient.getFeed(this.feedId, (feed: Feed) => {
            this.feedViewModel = new FeedViewModel(feed);
            this.loadFailed = false;
            // 同步进列表缓存，退出重进时不回退
            momentClient.updateFeedCache(feed, null);
        }, () => {
            if (!this.feedViewModel) {
                this.loadFailed = true;
            }
        });
    }

    // 互动后刷新该条朋友圈
    private refreshFeed() {
        this.loadFeed();
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
                        feed.isLiking = false;
                        this.refreshFeed();
                    }, (errorCode: number) => {
                        feed.isLiking = false;
                        showToast(`操作失败 (${errorCode})`);
                    });
                } else {
                    feed.isLiking = false;
                }
            } else {
                let comment = new Comment();
                comment.feedId = feedId;
                comment.type = FeedCommentType.Thumbup;
                comment.sender = this.currentUserId;
                momentClient.postComment(comment, () => {
                    feed.isLiking = false;
                    this.refreshFeed();
                }, (errorCode: number) => {
                    feed.isLiking = false;
                    showToast(`操作失败 (${errorCode})`);
                });
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
            momentClient.postComment(comment, () => {
                feed.isCommenting = false;
                this.commentInputState.isVisible = false;
                this.commentText = '';
                this.refreshFeed();
            }, (errorCode: number) => {
                feed.isCommenting = false;
                showToast(`评论失败 (${errorCode})`);
            });
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
                        AppStorage.setOrCreate('momentNeedRefresh', true);
                        this.mainNavPathStack.pop();
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
                this.refreshFeed();
            }, (errorCode: number) => {
                showToast(`删除失败 (${errorCode})`);
            });
        },

        onUserClick: (userId: string) => {
            if (userId) {
                this.mainNavPathStack.pushPathByName(momentNavigationDestinations.FeedListPage, {
                    'userId': userId
                } as Record<string, Object>);
            }
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
            feed.markDirty();
        }
    };

    private showCommentInput(feed: FeedViewModel, replyTo?: string, replyToName?: string) {
        this.commentInputState = {
            isVisible: true,
            feedId: feed.feed.feedId,
            replyTo,
            replyToName,
            placeholder: replyTo ? `回复 ${replyToName || replyTo}` : '写评论...'
        };
    }

    build() {
        NavDestination() {
            Stack({ alignContent: Alignment.Top }) {
                Column() {
                    if (this.feedViewModel) {
                        Scroll() {
                            FeedItemComponent({
                                feedViewModel: this.feedViewModel,
                                currentUserId: this.currentUserId,
                                events: this.interactionEvents,
                                onCommentClick: (replyTo?: string, replyToName?: string) => {
                                    this.showCommentInput(this.feedViewModel!, replyTo, replyToName);
                                }
                            })
                        }
                        .layoutWeight(1)
                        .scrollBar(BarState.Off)
                        .align(Alignment.Top)
                    } else if (this.loadFailed) {
                        Column() {
                            Text('内容不存在或已删除')
                                .fontSize(MomentConstants.FONT_SIZE_MEDIUM)
                                .fontColor(MomentConstants.TEXT_SECONDARY_COLOR)
                        }
                        .width('100%')
                        .layoutWeight(1)
                        .justifyContent(FlexAlign.Center)
                    } else {
                        Column() {
                            LoadingProgress()
                                .width(32)
                                .height(32)
                                .color(MomentConstants.PRIMARY_COLOR)
                        }
                        .width('100%')
                        .layoutWeight(1)
                        .justifyContent(FlexAlign.Center)
                    }
                }
                .width('100%')
                .height('100%')

                if (this.commentInputState.isVisible) {
                    this.buildCommentInput()
                }
            }
            .width('100%')
            .height('100%')
        }
        .title('详情')
        .backgroundColor(MomentConstants.BACKGROUND_COLOR)
        .onShown(() => {
            try { this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE); } catch (e) {}
        })
        .onHidden(() => {
            try { this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET); } catch (e) {}
        })
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
                    .id('detail_comment_input')
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
                            focusControl.requestFocus('detail_comment_input');
                        }, 80);
                    })
                    .onChange((value: string) => {
                        this.commentText = value;
                    })
                    .onSubmit(() => {
                        if (this.feedViewModel && this.commentText.trim()) {
                            this.interactionEvents.onComment(this.feedViewModel, this.commentText, this.commentInputState.replyTo);
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
                        if (this.feedViewModel) {
                            this.interactionEvents.onComment(this.feedViewModel, this.commentText, this.commentInputState.replyTo);
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
