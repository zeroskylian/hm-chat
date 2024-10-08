import BasicDataSource from '../../common/BasicDataSource'
import { get } from '../../helper/httpHelper'
import { timeFormat } from '../../util/helper'
import wfc from '@wfc/client/src/main/ets/wfc/client/wfc'
import CompositeMessageContent from '@wfc/client/src/main/ets/wfc/messages/compositeMessageContent'
import Message from '@wfc/client/src/main/ets/wfc/messages/message'
import Conversation from '@wfc/client/src/main/ets/wfc/model/conversation'
import Long from '@wfc/client/src/main/ets/wfc/util/long'
import { eq } from '@wfc/client/src/main/ets/wfc/util/longUtil'
import CompositeMessageContentContainerView from './message/CompositeMessageContentContainerView'
import { http } from '@kit.NetworkKit'
import { LengthUnit } from '@kit.ArkUI'

@Entry
@Component
export default struct TextMessagePreviewPage {
    @Consume('mainNavPathStack') mainNavPathStack: NavPathStack;
    private message?: Message;
    private conversation?: Conversation

    aboutToAppear() {
        let params = this.mainNavPathStack.getParamByIndex(this.mainNavPathStack.size() - 1) as Record<string, Object>;
        this.message = params['message'] as Message;
        this.conversation = this.message?.conversation;
    }

    build() {
        NavDestination() {
            Column() {
                Scroll() {
                    Text(this.message?.messageContent.digest(this.message))
                        .width('100%')
                        .fontSize(20)
                        .lineSpacing({ value: 12, unit: LengthUnit.VP })

                }
                .scrollBar(BarState.Off)
                .edgeEffect(EdgeEffect.Spring)
                .width('100%')
                .layoutWeight(1)

                Row() {
                    Text('TODO actions')
                }
                .height(40)
                .width('100%')
            }
            .padding(20)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .onClick(() => {
                this.mainNavPathStack.pop()
            })
        }
        .height('100%')
        .width('100%')
        .hideTitleBar(true)
    }
}
