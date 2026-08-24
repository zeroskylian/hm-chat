import { showToast } from '../../common/utils/Toast'
import Config from '@wfc/client/src/main/ets/config'
import wfc from '@wfc/client/src/main/ets/wfc/client/wfc'
import EventType from '@wfc/client/src/main/ets/wfc/client/wfcEvent'
import Conversation from '@wfc/client/src/main/ets/wfc/model/conversation'
import ConversationType from '@wfc/client/src/main/ets/wfc/model/conversationType'
import PCOnlineInfo from '@wfc/client/src/main/ets/wfc/model/pcOnlineInfo'
import { uikitNavigationDestinations } from '../uikitNavigationConfig'
import { FontSize, Radius } from '../../common/design/Tokens'
import { pcPlatformSymbol, pcDeviceName, isPcDesktopDevice } from '../../common/utils/pcOnlineUtil'

/**
 * 已登录的设备页（微信风格）。
 * 路由参数：{ pcOnlineInfos: PCOnlineInfo[] } —— 全部在线设备。
 * 每台设备一张卡片，第一张默认展开；点击卡片展开、其余收起（手风琴）。
 */
@Component
export default struct PCSessionPage {
    @Consume('mainNavPathStack') mainNavPathStack: NavPathStack;
    @State pcOnlineInfos: PCOnlineInfo[] = []
    // 当前展开的卡片下标，-1 表示全部收起
    @State expandedIndex: number = 0
    // 每台设备的锁定状态（与 pcOnlineInfos 下标一一对应）
    @State lockStates: boolean[] = []
    @State isMuteWhenPCOnLine: boolean = false

    aboutToAppear() {
        this.isMuteWhenPCOnLine = wfc.isMuteNotificationWhenPcOnline()
        let params = this.mainNavPathStack.getParamByIndex(this.mainNavPathStack.size() - 1) as Record<string, Object>;
        let infos = params ? params['pcOnlineInfos'] : undefined
        if (Array.isArray(infos)) {
            let list = infos as Object[]
            let result: PCOnlineInfo[] = []
            list.forEach(item => {
                if (item instanceof PCOnlineInfo) {
                    result.push(item)
                }
            })
            if (result.length > 0) {
                this.pcOnlineInfos = result
            }
        }
        if (this.pcOnlineInfos.length === 0) {
            // 兼容旧参数（单设备）
            let info = params ? params['pcOnlineInfo'] : undefined
            if (info instanceof PCOnlineInfo) {
                this.pcOnlineInfos = [info]
            }
        }
        this.syncLockStates()
    }

    onSettingUpdate = () => {
        this.checkPCOnlineStatus()
    }

    checkPCOnlineStatus() {
        let infos = wfc.getPCOnlineInfos()
        this.pcOnlineInfos = infos
        if (infos.length === 0) {
            this.mainNavPathStack.pop()
            return
        }
        if (this.expandedIndex >= infos.length) {
            this.expandedIndex = 0
        }
        this.syncLockStates()
    }

    // 同步每台设备的锁定状态
    private syncLockStates() {
        let states: boolean[] = []
        this.pcOnlineInfos.forEach(info => {
            states.push(wfc.isLockPCClient(info.clientId))
        })
        this.lockStates = states
    }

    // 点击卡片：展开当前、收起其它；点击已展开的卡片则收起
    private toggleExpand(index: number) {
        this.expandedIndex = this.expandedIndex === index ? -1 : index
    }

    // 退出某台设备登录
    private kickoffDevice(info: PCOnlineInfo) {
        wfc.kickoffPCClient(info.clientId, () => {
            showToast('已退出登录')
            this.checkPCOnlineStatus()
        }, err => {
            showToast('操作失败 ' + err)
        })
    }

    build() {
        NavDestination() {
            Column() {
                // 全局：手机静音（其它端在线时关闭手机通知）
                Row() {
                    Text('手机静音')
                        .fontSize(FontSize.md)
                        .fontColor($r('app.color.wf_primary_text'))
                        .layoutWeight(1)

                    Toggle({ type: ToggleType.Switch, isOn: this.isMuteWhenPCOnLine })
                        .selectedColor($r('app.color.wf_primary'))
                        .onChange((isOn: boolean) => {
                            wfc.muteNotificationWhenPcOnline(isOn, () => {
                                this.isMuteWhenPCOnLine = isOn
                            }, err => {
                                showToast('设置失败 ' + err)
                            })
                        })
                }
                .width('100%')
                .height(56)
                .padding({ left: 16, right: 16 })
                .backgroundColor($r('app.color.wf_background'))

                // 设备卡片列表（手风琴：第一张默认展开）
                Scroll() {
                    Column({ space: 12 }) {
                        ForEach(this.pcOnlineInfos, (info: PCOnlineInfo, index: number) => {
                            this.buildDeviceCard(info, index)
                        }, (info: PCOnlineInfo, index: number) => {
                            return `${info.type}-${info.platform.platform}-${info.clientId}`
                        })
                    }
                    .width('100%')
                    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
                }
                .layoutWeight(1)
                .scrollBar(BarState.Off)
                .align(Alignment.Top)

                // 传文件入口
                Row() {
                    Text('传文件')
                        .fontSize(FontSize.md)
                        .fontColor($r('app.color.wf_primary_text'))
                        .layoutWeight(1)

                    Text('>')
                        .fontSize(FontSize.lg)
                        .fontColor($r('app.color.wf_tertiary_text'))
                }
                .width('100%')
                .height(56)
                .padding({ left: 16, right: 16 })
                .backgroundColor($r('app.color.wf_background'))
                .onClick(() => {
                    this.mainNavPathStack.replacePathByName(uikitNavigationDestinations.ConversationPage, {
                        'conversation': new Conversation(ConversationType.Single, Config.FILE_HELPER_ID, 0)
                    } as Record<string, Object>)
                })
            }
            .width('100%')
            .height('100%')
            .backgroundColor($r('app.color.wf_primary_background_color'))
        }
        .title('已登录的设备')
        .height('100%')
        .width('100%')
        .onReady(() => {
            // 页面显示时：添加监听并检查设备状态
            wfc.eventEmitter?.on(EventType.SettingUpdate, this.onSettingUpdate)
            this.checkPCOnlineStatus()
        })
        .onHidden(() => {
            // 页面隐藏时：移除监听
            wfc.eventEmitter?.off(EventType.SettingUpdate, this.onSettingUpdate)
        })
    }

    // 单台设备卡片：头部点击展开/收起，展开后显示设备操作
    @Builder
    private buildDeviceCard(info: PCOnlineInfo, index: number) {
        Column() {
            // 卡片头部
            Row() {
                SymbolGlyph(pcPlatformSymbol(info))
                    .fontSize(FontSize.lg)
                    .fontColor([$r('app.color.wf_primary_text')])

                Text(pcDeviceName(info))
                    .fontSize(FontSize.md)
                    .fontColor($r('app.color.wf_primary_text'))
                    .margin({ left: 12 })
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                SymbolGlyph($r('sys.symbol.chevron_down'))
                    .fontSize(FontSize.sm)
                    .fontColor([$r('app.color.wf_tertiary_text')])
                    .rotate({ angle: this.expandedIndex === index ? 180 : 0 })
            }
            .width('100%')
            .height(56)
            .padding({ left: 16, right: 16 })
            .onClick(() => this.toggleExpand(index))

            // 展开内容
            if (this.expandedIndex === index) {
                Column() {
                    // 桌面电脑类设备：锁定电脑
                    if (isPcDesktopDevice(info)) {
                        Row() {
                            Text('锁定电脑')
                                .fontSize(FontSize.md)
                                .fontColor($r('app.color.wf_primary_text'))
                                .layoutWeight(1)

                            Toggle({ type: ToggleType.Switch, isOn: this.lockStates[index] ?? false })
                                .selectedColor($r('app.color.wf_primary'))
                                .onChange((isOn: boolean) => {
                                    wfc.lockPCClient(info.clientId, isOn, () => {
                                        this.lockStates[index] = isOn
                                    }, err => {
                                        showToast('设置失败 ' + err)
                                    })
                                })
                        }
                        .width('100%')
                        .height(56)
                        .padding({ left: 16, right: 16 })

                        Divider()
                            .strokeWidth(0.5)
                            .color($r('app.color.wf_divider'))
                            .margin({ left: 16 })
                    }

                    // 退出该设备登录
                    Row() {
                        Text(`退出${pcDeviceName(info)}登录`)
                            .fontSize(FontSize.md)
                            .fontColor(0xFA5151)
                    }
                    .width('100%')
                    .height(52)
                    .justifyContent(FlexAlign.Center)
                    .onClick(() => this.kickoffDevice(info))
                }
                .width('100%')
            }
        }
        .width('100%')
        .backgroundColor($r('app.color.wf_background'))
        .borderRadius(Radius.md)
        .clip(true)
    }
}
