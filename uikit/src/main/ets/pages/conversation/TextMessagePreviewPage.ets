import Message from '@wfc/client/src/main/ets/wfc/messages/message'
import Conversation from '@wfc/client/src/main/ets/wfc/model/conversation'
import StreamingTextGeneratingMessageContent from '@wfc/client/src/main/ets/wfc/messages/streamingTextGeneratingMessageContent'
import StreamingTextGeneratedMessageContent from '@wfc/client/src/main/ets/wfc/messages/streamingTextGeneratedMessageContent'
import { LengthUnit, window, display } from '@kit.ArkUI'
import { TextStyleToken } from '../../common/design/Tokens'
import { MarkdownMessageView } from './message/MarkdownMessageView'
import Config from '@wfc/client/src/main/ets/config'
import { normalizeUrl, isHttpUrl } from '../../common/utils/TextLinkParser'
import { common } from '@kit.AbilityKit'
import { showToast } from '../../common/utils/Toast'
import { uikitNavigationDestinations } from '../uikitNavigationConfig'

@Component
export default struct TextMessagePreviewPage {
    @Consume('mainNavPathStack') mainNavPathStack: NavPathStack;
    private message?: Message;
    private conversation?: Conversation
    // 底部导航指示条（小白条）高度（vp）：内容避让，防止滚动到底部被遮盖
    @State bottomSafeVp: number = 0

    aboutToAppear() {
        let params = this.mainNavPathStack.getParamByIndex(this.mainNavPathStack.size() - 1) as Record<string, Object>;
        this.message = params['message'] as Message;
        this.conversation = this.message?.conversation;
        // 测量底部导航指示条高度（px → vp），与 ConversationInputPanelView 的避让方式一致
        window.getLastWindow(getContext(this)).then((win: window.Window) => {
            let area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
            let density = display.getDefaultDisplaySync().densityPixels;
            if (density > 0) {
                this.bottomSafeVp = area.bottomRect.height / density;
            }
        }).catch(() => {
            // 取不到就保持 0：系统默认避让兜底
        });
    }

    /** AI 流式消息（含 Markdown）：详情页按渲染视图展示，而非源码。 */
    private isStreamingText(): boolean {
        let c = this.message?.messageContent;
        return c instanceof StreamingTextGeneratingMessageContent
            || c instanceof StreamingTextGeneratedMessageContent;
    }

    build() {
        NavDestination() {
            Column() {
                Scroll() {
                    if (this.isStreamingText()) {
                        Column() {
                            MarkdownMessageView({
                                markdownText: this.message?.messageContent.digest(this.message) ?? '',
                                onLinkClick: (url: string): void => this.handleLinkClick(url)
                            })
                                .constraintSize({ minHeight: 40 })
                        }
                        .width('100%')
                    } else {
                        Text(this.message?.messageContent.digest(this.message))
                            .width('100%')
                            .fontSize(TextStyleToken.messagePreview)
                            .lineSpacing({ value: 12, unit: LengthUnit.VP })
                    }

                }
                .scrollBar(BarState.Off)
                .edgeEffect(EdgeEffect.Spring)
                .width('100%')
                .layoutWeight(1)
            }
            .padding({ left: 20, right: 20, top: 20, bottom: 20 + this.bottomSafeVp })
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Start)
            .width('100%')
        }
        .height('100%')
        .width('100%')
        // 标准标题栏（自带返回键）：替代旧的"点击任意处关闭"——
        // 避免点击 Markdown 链接时冒泡误触发关闭（本 SDK 的 ClickEvent 无 stopPropagation）
        .hideTitleBar(false)
        .title('消息详情')
    }

    handleLinkClick(url: string) {
        if (Config.OPEN_LINK_POLICY === 2) {
            showToast('禁止打开外部链接')
            return
        }
        if (Config.OPEN_LINK_POLICY === 1) {
            AlertDialog.show({
                title: '提示',
                message: '谨防钓鱼网站或者带毒网站，只有确认已知安全的链接才可以打开。请确实该链接是否是已知安全的？',
                primaryButton: {
                    value: '确认安全',
                    action: () => {
                        this.openUrl(url)
                    }
                },
                secondaryButton: {
                    value: '关闭',
                    action: () => {
                    }
                }
            })
            return
        }
        this.openUrl(url)
    }

    openUrl(url: string) {
        let normalizedUrl = normalizeUrl(url);
        if (isHttpUrl(normalizedUrl)) {
            this.mainNavPathStack.pushPathByName(uikitNavigationDestinations.WebViewPage, {
                'url': normalizedUrl,
                'title': ''
            } as Record<string, Object>)
        } else {
            let context = getContext(this) as common.UIAbilityContext;
            context.startAbility({ action: 'ohos.want.action.viewData', uri: normalizedUrl });
        }
    }
}
