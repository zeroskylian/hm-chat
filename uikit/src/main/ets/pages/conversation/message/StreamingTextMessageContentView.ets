import Config from '@wfc/client/src/main/ets/config'
import Message from "@wfc/client/src/main/ets/wfc/messages/message";
import StreamingTextGeneratingMessageContent from "@wfc/client/src/main/ets/wfc/messages/streamingTextGeneratingMessageContent";
import StreamingTextGeneratedMessageContent from "@wfc/client/src/main/ets/wfc/messages/streamingTextGeneratedMessageContent";
import { showToast } from '../../../common/utils/Toast';
import { normalizeUrl, isHttpUrl } from '../../../common/utils/TextLinkParser';
import { common } from '@kit.AbilityKit';
import { uikitNavigationDestinations } from '../../uikitNavigationConfig';
import { FontSize, Radius } from '../../../common/design/Tokens'
import { MarkdownMessageView } from './MarkdownMessageView'

@Component
export default struct StreamingTextMessageContentView {
    @Consume('mainNavPathStack') mainNavPathStack: NavPathStack;
    @Link message: Message

    streamingMessageContent() {
        if (this.message.messageContent instanceof StreamingTextGeneratingMessageContent) {
            return (this.message.messageContent as StreamingTextGeneratingMessageContent).text
        } else if (this.message.messageContent instanceof StreamingTextGeneratedMessageContent) {
            return (this.message.messageContent as StreamingTextGeneratedMessageContent).text
        }
        return ''
    }

    isGenerated() {
        return this.message.messageContent instanceof StreamingTextGeneratedMessageContent;
    }

    build() {
        Column() {
            // Markdown 渲染（AI 回复常见格式：标题/粗体/代码块/列表/引用/链接）
            MarkdownMessageView({
                markdownText: this.streamingMessageContent(),
                onLinkClick: (url: string): void => this.handleLinkClick(url)
            })
                .constraintSize({ minHeight: 40 })
                .padding(12)

            if (!this.isGenerated()) {
                Row({ space: 4 }) {
                    LoadingProgress()
                        .width(14)
                        .height(14)
                        .color($r('app.color.wf_primary'))
                    Text('生成中...')
                        .fontSize(FontSize.xs)
                        .fontColor($r('app.color.wf_tertiary_text'))
                }
                .width('100%')
                .padding({ left: 12, bottom: 8 })
                .alignItems(VerticalAlign.Center)
            } else {
                Text('本内容由 AI 生成')
                    .fontSize(FontSize.xs)
                    .fontColor($r('app.color.wf_tertiary_text'))
                    .padding({ left: 12, top: 4, bottom: 4 })
            }
        }
        .borderRadius(Radius.sm)
        .backgroundColor(this.message.direction === 0 ? $r('app.color.wf_sent_bubble_bg') : $r('app.color.wf_received_bubble_bg'))
        .alignItems(HorizontalAlign.Start)
        .onClick(() => {
            // 点击气泡查看全文（Markdown 源码预览）
            if (this.isGenerated()) {
                this.mainNavPathStack.pushPathByName(uikitNavigationDestinations.TextMessagePreviewPage, {
                    'message': this.message
                } as Record<string, object>)
            }
        })
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
