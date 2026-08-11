import { momentClient } from '../client/MomentClient';
import { Feed, FeedEntry, FeedContentType } from '../model/MomentModel';
import { uploadImage, uploadVideo } from '../utils/MomentUpload';
import { MomentConstants } from '../utils/MomentConstants';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import { showToast } from '@wfc/uikit/src/main/ets/common/utils/Toast';
import { uikitNavigationDestinations } from '@wfc/uikit/src/main/ets/pages/uikitNavigationConfig';
import PickMultiContactModal from '@wfc/uikit/src/main/ets/pages/picker/PickMultiContactModal';
import UserInfo from '@wfc/client/src/main/ets/wfc/model/userInfo';
import wfc from '@wfc/client';
import { promptAction } from '@kit.ArkUI';
import hilog from '@ohos.hilog';
import { FontSize, Radius } from '@wfc/uikit/src/main/ets/common/design/Tokens'

const MAX_TEXT_LENGTH = 1000;
const MAX_IMAGES = 9;
const LOG_DOMAIN = 0xFF01;
const LOG_TAG = 'MomentPostFeed';

// 可见范围
enum VisibleScope {
    Public = 0,   // 公开
    Private = 1,  // 私密（仅自己可见）
    Partial = 2,  // 部分可见（白名单）
    Exclude = 3,  // 不给谁看（黑名单）
}

// 当前正在选择联系人的目标
enum PickTarget {
    None = 0,
    Partial = 1,
    Exclude = 2,
    Mention = 3,
}

interface PostFeedState {
    text: string;
    selectedImages: string[];
    selectedVideo: string;
    isPosting: boolean;
    uploadingCount: number;
    totalCount: number;
}

@Component
export struct PostFeedPage {
    @State postState: PostFeedState = {
        text: '',
        selectedImages: [],
        selectedVideo: '',
        isPosting: false,
        uploadingCount: 0,
        totalCount: 0
    };
    // TextArea 高度跟随内容动态扩展
    @State textAreaHeight: number = 130;
    // 路由参数：长按相机进入时为 true，隐藏媒体区，只发文字
    @State textOnly: boolean = false;

    // 可见范围 / 提醒谁看
    @State visibleScope: VisibleScope = VisibleScope.Public;
    @State partialVisibleUsers: UserInfo[] = [];
    @State excludeUsers: UserInfo[] = [];
    @State mentionUsers: UserInfo[] = [];
    private pickTarget: PickTarget = PickTarget.None;

    @Consume('mainNavPathStack') mainNavPathStack: NavPathStack;

    aboutToAppear() {
        let params = this.mainNavPathStack.getParamByIndex(this.mainNavPathStack.size() - 1) as Record<string, Object>;
        if (params && typeof params['textOnly'] === 'boolean') {
            this.textOnly = params['textOnly'] as boolean;
        }
        // 「谁可以看」初始值读取发布默认可见范围
        let scope = momentClient.getDefaultVisibleScope();
        this.visibleScope = scope.mode as VisibleScope;
        if (scope.users.length > 0) {
            let users = wfc.getUserInfos(scope.users);
            if (this.visibleScope === VisibleScope.Partial) {
                this.partialVisibleUsers = users;
            } else if (this.visibleScope === VisibleScope.Exclude) {
                this.excludeUsers = users;
            }
        }
    }

    private async publishFeed() {
        if (this.postState.isPosting) return;
        const mediaCount = this.postState.selectedVideo ? 1 : this.postState.selectedImages.length;
        if (!this.postState.text.trim() && mediaCount === 0) {
            showToast(this.textOnly ? '请输入内容' : '请输入内容或选择图片');
            return;
        }

        this.postState.isPosting = true;
        this.postState.totalCount = mediaCount;
        this.postState.uploadingCount = 0;

        hilog.info(LOG_DOMAIN, LOG_TAG, '开始发布朋友圈, 媒体数=%{public}d', mediaCount);

        try {
            let uploadedMedias: FeedEntry[] = [];
            if (this.postState.selectedVideo) {
                let entry = await this.uploadMedia(this.postState.selectedVideo, true, 0);
                uploadedMedias.push(entry);
            } else if (this.postState.selectedImages.length > 0) {
                // 并行上传所有图片，任意一张失败则整体失败
                uploadedMedias = await Promise.all(
                    this.postState.selectedImages.map((path, index) => this.uploadMedia(path, false, index))
                );
            }

            let feedType = FeedContentType.Text;
            if (this.postState.selectedVideo) {
                feedType = FeedContentType.Video;
            } else if (uploadedMedias.length > 0) {
                feedType = FeedContentType.Image;
            }

            let feed = new Feed();
            feed.type = feedType;
            if (this.postState.text.trim()) {
                feed.text = this.postState.text.trim();
            }
            if (uploadedMedias.length > 0) {
                feed.medias = uploadedMedias;
            }
            const toUsers = this.computeToUsers();
            if (toUsers.length > 0) {
                feed.toUsers = toUsers;
            }
            if (this.visibleScope === VisibleScope.Exclude && this.excludeUsers.length > 0) {
                feed.excludeUsers = this.excludeUsers.map(u => u.uid);
            }
            if (this.mentionUsers.length > 0) {
                feed.mentionedUsers = this.mentionUsers.map(u => u.uid);
            }

            momentClient.postFeed(feed,
                () => {
                    this.postState.isPosting = false;
                    hilog.info(LOG_DOMAIN, LOG_TAG, '发布成功');
                    // 通知列表页刷新
                    AppStorage.setOrCreate('momentNeedRefresh', true);
                    showToast('发布成功');
                    this.goBack();
                },
                (errorCode: number) => {
                    this.postState.isPosting = false;
                    hilog.error(LOG_DOMAIN, LOG_TAG,
                        '发布失败, errorCode=%{public}d, 媒体数=%{public}d', errorCode, mediaCount);
                    showToast(`发布失败 (${errorCode})`);
                }
            );
        } catch (e) {
            this.postState.isPosting = false;
            hilog.error(LOG_DOMAIN, LOG_TAG,
                '媒体上传失败, 媒体数=%{public}d, msg=%{public}s', mediaCount, `${e}`);
            showToast('媒体上传失败，请重试');
        }
    }

    // 公开/不给谁看 -> 全部可见(toUsers 为空)；私密 -> 仅自己；部分可见 -> 白名单
    private computeToUsers(): string[] {
        if (this.visibleScope === VisibleScope.Private) {
            return [wfc.getUserId()];
        }
        if (this.visibleScope === VisibleScope.Partial) {
            return this.partialVisibleUsers.map(u => u.uid);
        }
        return [];
    }

    private async uploadMedia(path: string, isVideo: boolean, index: number): Promise<FeedEntry> {
        try {
            let entry = isVideo ? await uploadVideo(path) : await uploadImage(path);
            this.postState.uploadingCount++;
            hilog.info(LOG_DOMAIN, LOG_TAG, '媒体上传成功, index=%{public}d', index);
            return entry;
        } catch (e) {
            hilog.error(LOG_DOMAIN, LOG_TAG, '媒体上传失败, index=%{public}d, path=%{public}s', index, path);
            throw new Error(`upload failed at index ${index}`);
        }
    }

    // 选择图片或视频：图片与视频互斥，视频只能选 1 条，图片上限 9
    private async selectMedia() {
        try {
            if (this.postState.selectedVideo) {
                showToast('已选择视频，不能再选图片');
                return;
            }
            const remain = MAX_IMAGES - this.postState.selectedImages.length;
            if (remain <= 0) return;

            const options = new photoAccessHelper.PhotoSelectOptions();
            options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
            options.maxSelectNumber = this.postState.selectedImages.length > 0 ? remain : MAX_IMAGES;
            // 已选图片时只允许继续选图片；未选时图片视频均可
            if (this.postState.selectedImages.length > 0) {
                options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
            }

            const photoPicker = new photoAccessHelper.PhotoViewPicker();
            const result = await photoPicker.select(options);
            const photoUris = result.photoUris;
            if (!photoUris || photoUris.length === 0) {
                return;
            }

            // 通过 uri 后缀粗略识别视频
            const videoUri = photoUris.find(uri => this.isVideoUri(uri));
            if (videoUri) {
                if (photoUris.length > 1 || this.postState.selectedImages.length > 0) {
                    showToast('视频和图片不能同时发表');
                    return;
                }
                this.postState.selectedVideo = videoUri;
                return;
            }
            const newImages = [...this.postState.selectedImages, ...photoUris];
            this.postState.selectedImages = newImages.slice(0, MAX_IMAGES);
        } catch (e) {
            // 用户取消选择，忽略
        }
    }

    private isVideoUri(uri: string): boolean {
        const lower = uri.toLowerCase();
        return lower.endsWith('.mp4') || lower.endsWith('.mov') || lower.endsWith('.m4v')
            || lower.endsWith('.3gp') || lower.endsWith('.mkv') || lower.includes('/video/');
    }

    private removeImage(index: number) {
        const newImages = [...this.postState.selectedImages];
        newImages.splice(index, 1);
        this.postState.selectedImages = newImages;
    }

    private removeVideo() {
        this.postState.selectedVideo = '';
    }

    private goBack() {
        this.mainNavPathStack.pop();
    }

    // ===== 可见范围 / 提醒谁看 =====

    // 点击「谁可以看」，弹出范围选择
    private showScopeMenu(): void {
        promptAction.showActionMenu({
            title: '谁可以看',
            buttons: [
                { text: '公开', color: $r('app.color.text_primary') },
                { text: '私密', color: $r('app.color.text_primary') },
                { text: '部分可见', color: $r('app.color.text_primary') },
                { text: '不给谁看', color: $r('app.color.text_primary') },
            ]
        }).then(result => {
            switch (result.index) {
                case 0:
                    this.visibleScope = VisibleScope.Public;
                    break;
                case 1:
                    this.visibleScope = VisibleScope.Private;
                    break;
                case 2:
                    this.visibleScope = VisibleScope.Partial;
                    this.openContactPicker(PickTarget.Partial);
                    break;
                case 3:
                    this.visibleScope = VisibleScope.Exclude;
                    this.openContactPicker(PickTarget.Exclude);
                    break;
            }
        }).catch(() => {});
    }

    private openContactPicker(target: PickTarget): void {
        this.pickTarget = target;
        // 先清空上次结果，便于区分「取消选择」
        LocalStorage.getShared().setOrCreate<UserInfo[]>(PickMultiContactModal.PICK_RESULT, []);
        this.mainNavPathStack.pushPathByName(uikitNavigationDestinations.PickMultiContactPage, {} as Record<string, Object>);
    }

    // 从联系人选择页返回时读取结果
    private consumePickResult(): void {
        if (this.pickTarget === PickTarget.None) return;
        const result = LocalStorage.getShared().get<UserInfo[]>(PickMultiContactModal.PICK_RESULT);
        const target = this.pickTarget;
        this.pickTarget = PickTarget.None;
        // 确定按钮在 0 人时禁用，故有结果即视为用户确认；为空表示取消，保留原选择
        if (!result || result.length === 0) {
            // 取消「部分可见 / 不给谁看」且尚未选过人时，回退到公开
            if (target === PickTarget.Partial && this.partialVisibleUsers.length === 0) {
                this.visibleScope = VisibleScope.Public;
            } else if (target === PickTarget.Exclude && this.excludeUsers.length === 0) {
                this.visibleScope = VisibleScope.Public;
            }
            return;
        }
        if (target === PickTarget.Partial) {
            this.partialVisibleUsers = result;
        } else if (target === PickTarget.Exclude) {
            this.excludeUsers = result;
        } else if (target === PickTarget.Mention) {
            this.mentionUsers = result;
        }
        LocalStorage.getShared().setOrCreate<UserInfo[]>(PickMultiContactModal.PICK_RESULT, []);
    }

    private scopeLabel(): string {
        switch (this.visibleScope) {
            case VisibleScope.Private:
                return '私密';
            case VisibleScope.Partial:
                return this.partialVisibleUsers.length > 0 ? `部分可见(${this.partialVisibleUsers.length})` : '部分可见';
            case VisibleScope.Exclude:
                return this.excludeUsers.length > 0 ? `不给谁看(${this.excludeUsers.length})` : '不给谁看';
            default:
                return '公开';
        }
    }

    private mentionLabel(): string {
        return this.mentionUsers.length > 0 ? `${this.mentionUsers.length}人` : '';
    }

    private canPublish(): boolean {
        return !this.postState.isPosting &&
            (this.postState.text.trim().length > 0 || this.postState.selectedImages.length > 0 || !!this.postState.selectedVideo);
    }

    // 根据字符数估算 TextArea 高度（约每行 20 字，行高 22vp）
    private estimateTextAreaHeight(text: string): number {
        const lineCount = Math.max(1, Math.ceil(text.length / 22));
        const estimated = lineCount * 22 + 36;
        return Math.min(Math.max(estimated, 120), 300);
    }

    build() {
        NavDestination() {
            Column() {
                // 文本输入区
                this.buildTextInput()

                // 媒体选择区（纯文字模式不显示）
                if (!this.textOnly) {
                    this.buildMediaSelector()
                }

                // 可见范围 / 提醒谁看
                this.buildOptions()

                // 上传进度
                if (this.postState.isPosting && this.postState.totalCount > 0) {
                    this.buildUploadProgress()
                }

                Blank()
            }
            .width('100%')
            .height('100%')
            .padding({ left: 16, right: 16, top: 0 })
            .backgroundColor(MomentConstants.BACKGROUND_COLOR)
        }
        .title(this.textOnly ? '发表文字' : '发表朋友圈')
        .menus(this.buildPostMenu)
        .backgroundColor(MomentConstants.BACKGROUND_COLOR)
        .onShown(() => this.consumePickResult())
    }

    @Builder
    private buildPostMenu() {
        Row() {
            if (this.postState.isPosting) {
                LoadingProgress()
                    .width(24)
                    .height(24)
                    .color(MomentConstants.PRIMARY_COLOR)
            } else {
                Button('发表')
                    .backgroundColor(this.canPublish() ? MomentConstants.PRIMARY_COLOR : $r('app.color.button_disabled'))
                    .fontColor(this.canPublish() ? Color.White : $r('app.color.text_disabled'))
                    .fontSize(FontSize.sm)
                    .height(32)
                    .padding({ left: 20, right: 20 })
                    .borderRadius(MomentConstants.BORDER_RADIUS)
                    .enabled(this.canPublish())
                    .onClick(() => {
                        if (this.canPublish()) this.publishFeed();
                    })
            }
        }
        .height('100%')
        .margin({ right: 16 })
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
    }

    @Builder
    private buildOptions() {
        Column() {
            this.buildOptionRow('谁可以看', this.scopeLabel(), (): void => this.showScopeMenu())
            Divider()
                .color(MomentConstants.DIVIDER_COLOR)
                .strokeWidth(0.5)
            this.buildOptionRow('提醒谁看', this.mentionLabel(), (): void => this.openContactPicker(PickTarget.Mention))
        }
        .width('100%')
        .borderRadius(MomentConstants.BORDER_RADIUS)
        .backgroundColor(MomentConstants.CARD_BACKGROUND_COLOR)
        .margin({ top: 4 })
    }

    @Builder
    private buildOptionRow(title: string, value: string, action: () => void) {
        Row() {
            Text(title)
                .fontSize(MomentConstants.FONT_SIZE_CONTENT)
                .fontColor(MomentConstants.TEXT_PRIMARY_COLOR)
                .layoutWeight(1)

            Text(value)
                .fontSize(MomentConstants.FONT_SIZE_MEDIUM)
                .fontColor(MomentConstants.TEXT_SECONDARY_COLOR)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: '60%' })
                .margin({ right: 8 })

            SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(FontSize.sm)
                .fontColor([MomentConstants.TEXT_SECONDARY_COLOR])
        }
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .onClick(action)
    }

    @Builder
    private buildTextInput() {
        Column() {
            TextArea({
                placeholder: '这一刻的想法...',
                text: this.postState.text
            })
                .width('100%')
                .height(this.textAreaHeight)
                .fontSize(MomentConstants.FONT_SIZE_CONTENT)
                .backgroundColor(MomentConstants.CARD_BACKGROUND_COLOR)
                .fontColor(MomentConstants.TEXT_PRIMARY_COLOR)
                .placeholderColor(MomentConstants.TEXT_SECONDARY_COLOR)
                .borderRadius(MomentConstants.BORDER_RADIUS)
                .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                .maxLength(MAX_TEXT_LENGTH)
                .onChange((value: string) => {
                    this.postState.text = value;
                    this.textAreaHeight = this.estimateTextAreaHeight(value);
                })

            // 字数提示（接近上限时显示）
            if (this.postState.text.length > MAX_TEXT_LENGTH * 0.8) {
                Row() {
                    Blank()
                    Text(`${this.postState.text.length}/${MAX_TEXT_LENGTH}`)
                        .fontSize(MomentConstants.FONT_SIZE_CAPTION)
                        .fontColor(this.postState.text.length >= MAX_TEXT_LENGTH
                            ? MomentConstants.ERROR_COLOR
                            : MomentConstants.TEXT_SECONDARY_COLOR)
                }
                .width('100%')
                .padding({ right: 4, top: 4 })
            }
        }
        .width('100%')
        .margin({ top: 12, bottom: 12 })
    }

    @Builder
    private buildMediaSelector() {
        Column() {
            Grid() {
                // 已选图片
                ForEach(this.postState.selectedImages, (imagePath: string, index: number) => {
                    GridItem() {
                        this.buildImageItem(imagePath, index)
                    }
                }, (imagePath: string, index: number) => `img_${index}`)

                // 已选视频
                if (this.postState.selectedVideo) {
                    GridItem() {
                        this.buildVideoItem(this.postState.selectedVideo)
                    }
                }

                // 添加按钮
                if (!this.postState.selectedVideo && this.postState.selectedImages.length < MAX_IMAGES) {
                    GridItem() {
                        this.buildAddMediaButton()
                    }
                }
            }
            .columnsTemplate('1fr 1fr 1fr')
            .rowsGap(MomentConstants.IMAGE_GRID_GAP + 2)
            .columnsGap(MomentConstants.IMAGE_GRID_GAP + 2)
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
    }

    @Builder
    private buildImageItem(imagePath: string, index: number) {
        Stack({ alignContent: Alignment.TopEnd }) {
            Image(imagePath)
                .width('100%')
                .aspectRatio(1)
                .borderRadius(MomentConstants.BORDER_RADIUS)
                .objectFit(ImageFit.Cover)
                .backgroundColor(MomentConstants.COMMENT_BACKGROUND_COLOR)

            // 删除按钮
            Button() {
                SymbolGlyph($r('sys.symbol.xmark'))
                    .fontSize(FontSize.xs)
                    .fontColor([Color.White])
            }
            .width(24)
            .height(24)
            .type(ButtonType.Circle)
            .backgroundColor($r('app.color.mask_dark'))
            .margin({ top: 4, right: 4 })
            .onClick(() => this.removeImage(index))
        }
        .width('100%')
    }

    @Builder
    private buildVideoItem(videoPath: string) {
        Stack({ alignContent: Alignment.TopEnd }) {
            Stack({ alignContent: Alignment.Center }) {
                Column()
                    .width('100%')
                    .aspectRatio(1)
                    .borderRadius(MomentConstants.BORDER_RADIUS)
                    .backgroundColor(MomentConstants.COMMENT_BACKGROUND_COLOR)

                SymbolGlyph($r('sys.symbol.play_fill'))
                    .fontSize(FontSize.d3)
                    .fontColor([Color.White])
            }
            .width('100%')
            .clip(true)

            // 删除按钮
            Button() {
                SymbolGlyph($r('sys.symbol.xmark'))
                    .fontSize(FontSize.xs)
                    .fontColor([Color.White])
            }
            .width(24)
            .height(24)
            .type(ButtonType.Circle)
            .backgroundColor($r('app.color.mask_dark'))
            .margin({ top: 4, right: 4 })
            .onClick(() => this.removeVideo())
        }
        .width('100%')
    }

    @Builder
    private buildAddMediaButton() {
        Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.plus'))
                .fontSize(FontSize.d1)
                .fontColor([MomentConstants.TEXT_SECONDARY_COLOR])
        }
        .width('100%')
        .aspectRatio(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(MomentConstants.CARD_BACKGROUND_COLOR)
        .borderRadius(MomentConstants.BORDER_RADIUS)
        .border({
            width: 1,
            color: MomentConstants.DIVIDER_COLOR,
            style: BorderStyle.Dashed
        })
        .onClick(() => this.selectMedia())
    }

    @Builder
    private buildUploadProgress() {
        Column({ space: 8 }) {
            Progress({
                value: this.postState.uploadingCount,
                total: this.postState.totalCount,
                type: ProgressType.Linear
            })
                .width('100%')
                .height(4)
                .color(MomentConstants.PRIMARY_COLOR)
                .backgroundColor(MomentConstants.DIVIDER_COLOR)
                .borderRadius(Radius.xs)

            Text(`上传中(${this.postState.uploadingCount}/${this.postState.totalCount})`)
                .fontSize(MomentConstants.FONT_SIZE_CAPTION)
                .fontColor(MomentConstants.TEXT_SECONDARY_COLOR)
        }
        .width('100%')
        .padding({ top: 12, bottom: 4 })
    }
}
