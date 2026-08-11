import { Comment } from '../model/MomentModel';
import { FeedViewModel } from '../model/FeedViewModel';
import { MomentConstants } from '../utils/MomentConstants';
import wfc from '@wfc/client';
import UserInfo from '@wfc/client/src/main/ets/wfc/model/userInfo';
import { promptAction } from '@kit.ArkUI';
import pasteboard from '@ohos.pasteboard';
import { FontSize } from '@wfc/uikit/src/main/ets/common/design/Tokens'

/**
 * 点赞 + 评论区（灰底区域）。
 * 点赞行：逗号分隔可点昵称；评论行：昵称[回复 昵称]：内容。
 * 点自己评论弹[删除/复制]；点别人评论触发回复；长按任意评论弹[复制/回复/(删除)]。
 */
@Component
export struct CommentWidget {
    @ObjectLink feedViewModel: FeedViewModel;
    @Prop currentUserId: string;
    onUserClick: (userId: string) => void = () => {};
    onReplyComment: (comment: Comment) => void = () => {};
    onDeleteComment: (comment: Comment) => void = () => {};
    onMoreComments: (feed: FeedViewModel) => void = () => {};

    private getUserInfo(userId: string): UserInfo {
        return wfc.getUserInfo(userId);
    }

    private getDisplayComments(): Array<Comment> {
        const comments = this.feedViewModel.getCommentsList();
        return this.feedViewModel.showAllComments ? comments : comments.slice(0, MomentConstants.INITIAL_COMMENTS_COUNT);
    }

    build() {
        Column({ space: 0 }) {
            // 点赞区
            if (this.feedViewModel.hasLikes()) {
                this.buildLikesArea()
            }

            if (this.feedViewModel.hasLikes() && this.feedViewModel.hasComments()) {
                Divider()
                    .color(MomentConstants.DIVIDER_COLOR)
                    .strokeWidth(0.5)
                    .margin({ top: 8, bottom: 8 })
            }

            // 评论区
            if (this.feedViewModel.hasComments()) {
                this.buildCommentsArea()
            }
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .backgroundColor(MomentConstants.INTERACTIONS_BACKGROUND_COLOR)
        .borderRadius(MomentConstants.BORDER_RADIUS_SMALL)
        .margin({ top: 8 })
    }

    @Builder
    private buildLikesArea() {
        Row({ space: 0 }) {
            SymbolGlyph($r('sys.symbol.heart_fill'))
                .fontSize(FontSize.sm)
                .fontColor([MomentConstants.LINK_COLOR])
                .margin({ right: 8, top: 2 })

            // 点赞用户名列表（逗号分隔，每个名字可点击）
            Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.feedViewModel.getLikesList(), (like: Comment, idx: number) => {
                    Text(`${idx > 0 ? '，' : ''}${this.getUserInfo(like.sender).displayName}`)
                        .fontSize(MomentConstants.FONT_SIZE_SMALL)
                        .fontColor(MomentConstants.LINK_COLOR)
                        .onClick(() => this.onUserClick(like.sender))
                }, (like: Comment) => `like_${like.commentId}`)
            }
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
    }

    @Builder
    private buildCommentsArea() {
        Column({ space: 4 }) {
            ForEach(this.getDisplayComments(), (comment: Comment, index: number) => {
                this.buildCommentItem(comment)
            }, (comment: Comment, index: number) => `comment_${comment.commentId}_${index}`)

            if (!this.feedViewModel.showAllComments && this.feedViewModel.getCommentsList().length > MomentConstants.INITIAL_COMMENTS_COUNT) {
                Row({ space: 4 }) {
                    Text(`展开${this.feedViewModel.getCommentsList().length - MomentConstants.INITIAL_COMMENTS_COUNT}条评论`)
                        .fontSize(MomentConstants.FONT_SIZE_SMALL)
                        .fontColor(MomentConstants.LINK_COLOR)
                    SymbolGlyph($r('sys.symbol.chevron_down'))
                        .fontSize(FontSize.xs)
                        .fontColor([MomentConstants.LINK_COLOR])
                }
                .onClick(() => this.onMoreComments(this.feedViewModel))
            }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
    }

    @Builder
    private buildCommentItem(comment: Comment) {
        Text() {
            Span(this.getUserInfo(comment.sender).displayName)
                .fontColor(MomentConstants.LINK_COLOR)
                .fontWeight(FontWeight.Medium)
                .onClick(() => this.onUserClick(comment.sender))

            if (comment.replyTo && comment.replyTo !== comment.sender) {
                Span(' 回复 ')
                    .fontColor(MomentConstants.TEXT_SECONDARY_COLOR)
                Span(this.getUserInfo(comment.replyTo).displayName)
                    .fontColor(MomentConstants.LINK_COLOR)
                    .fontWeight(FontWeight.Medium)
                    .onClick(() => this.onUserClick(comment.replyTo!))
            }

            Span('：')
                .fontColor(MomentConstants.TEXT_SECONDARY_COLOR)

            Span(comment.text || '')
                .fontColor(MomentConstants.TEXT_PRIMARY_COLOR)
        }
        .fontSize(MomentConstants.FONT_SIZE_SMALL)
        .lineHeight(MomentConstants.FONT_SIZE_SMALL * 1.65)
        .width('100%')
        .onClick(() => {
            if (comment.sender === this.currentUserId) {
                this.showSelfCommentMenu(comment);
            } else {
                this.onReplyComment(comment);
            }
        })
        .gesture(
            LongPressGesture()
                .onAction(() => this.showCommentLongPressMenu(comment))
        )
    }

    // 点自己的评论：[删除/复制]
    private showSelfCommentMenu(comment: Comment) {
        promptAction.showActionMenu({
            title: '',
            buttons: [
                { text: '删除', color: $r('app.color.like_active') },
                { text: '复制', color: $r('app.color.text_primary') }
            ]
        }).then(result => {
            if (result.index === 0) {
                this.onDeleteComment(comment);
            } else if (result.index === 1) {
                this.copyText(comment.text);
            }
        }).catch(() => {});
    }

    // 长按任意评论：[复制/回复/(删除)]
    private showCommentLongPressMenu(comment: Comment) {
        if (comment.sender === this.currentUserId) {
            promptAction.showActionMenu({
                title: '',
                buttons: [
                    { text: '复制', color: $r('app.color.text_primary') },
                    { text: '回复', color: $r('app.color.text_primary') },
                    { text: '删除', color: $r('app.color.like_active') }
                ]
            }).then(result => {
                if (result.index === 0) {
                    this.copyText(comment.text);
                } else if (result.index === 1) {
                    this.onReplyComment(comment);
                } else if (result.index === 2) {
                    this.onDeleteComment(comment);
                }
            }).catch(() => {});
        } else {
            promptAction.showActionMenu({
                title: '',
                buttons: [
                    { text: '复制', color: $r('app.color.text_primary') },
                    { text: '回复', color: $r('app.color.text_primary') }
                ]
            }).then(result => {
                if (result.index === 0) {
                    this.copyText(comment.text);
                } else if (result.index === 1) {
                    this.onReplyComment(comment);
                }
            }).catch(() => {});
        }
    }

    private copyText(text?: string) {
        if (!text) return;
        const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
        pasteboard.getSystemPasteboard().setData(data).then(() => {
            promptAction.showToast({ message: '已复制' });
        }).catch(() => {});
    }
}
