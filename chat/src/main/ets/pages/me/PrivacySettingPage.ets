import wfc from '@wfc/client/src/main/ets/wfc/client/wfc'
import UserSettingScope from '@wfc/client/src/main/ets/wfc/client/userSettingScope'
import OptionItemView from '@wfc/uikit/src/main/ets/view/OptionItemView'
import ToggleItemView from '@wfc/uikit/src/main/ets/view/ToggleItemView'
import { showToast } from '@wfc/uikit/src/main/ets/common/utils/Toast'
import { appNavigationDestinations } from '../mainNavigationConfig'

/**
 * 隐私设置。各开关语义与 iOS WFCPrivacyTableViewController 一致：
 * 消息回执/密聊/加好友验证均走 wfc 的封装或 UserSettingScope 反向语义设置项，
 * 失败时 toast 并回滚开关。
 */
@Preview
@Component
export default struct PrivacySettingPage {
    @Consume('mainNavPathStack') mainNavPathStack: NavPathStack;
    // 朋友圈模块可用（依赖存在且服务端开启）时显示朋友圈隐私入口
    @StorageProp('momentModuleAvailable') momentAvailable: boolean = false;
    // 服务端能力开关
    @State receiptSupported: boolean = false;
    @State secretChatSupported: boolean = false;
    @State enableReceipt: boolean = true;
    @State enableSecretChat: boolean = false;
    @State addFriendNeedVerify: boolean = true;

    aboutToAppear() {
        this.receiptSupported = wfc.isReceiptEnabled()
        this.secretChatSupported = wfc.isEnableSecretChat()
        this.enableReceipt = wfc.isUserReceiptEnabled()
        this.enableSecretChat = wfc.isUserEnableSecretChat()
        // 反向语义：scope 存的是"不需要验证"，缺省为需要验证
        this.addFriendNeedVerify = wfc.getUserSetting(UserSettingScope.AddFriendNoVerify, '') !== '1'
    }

    private onReceiptChange(isOn: boolean) {
        let oldValue = this.enableReceipt
        this.enableReceipt = isOn
        wfc.setUserEnableReceipt(isOn, () => {
        }, (err: number) => {
            this.enableReceipt = oldValue
            showToast('网络错误')
        })
    }

    private onSecretChatChange(isOn: boolean) {
        let oldValue = this.enableSecretChat
        this.enableSecretChat = isOn
        wfc.setUserEnableSecretChat(isOn, () => {
        }, (err: number) => {
            this.enableSecretChat = oldValue
            showToast('网络错误')
        })
    }

    private onAddFriendVerifyChange(isOn: boolean) {
        let oldValue = this.addFriendNeedVerify
        this.addFriendNeedVerify = isOn
        wfc.setUserSetting(UserSettingScope.AddFriendNoVerify, '', isOn ? '0' : '1', () => {
        }, (err: number) => {
            this.addFriendNeedVerify = oldValue
            showToast('网络错误')
        })
    }

    build() {
        NavDestination() {
            Column() {
                Column() {
                    OptionItemView({
                        title: '找到我的方式',
                        showDivider: true,
                    })
                        .onClick(() => {
                            this.mainNavPathStack.pushPathByName(appNavigationDestinations.FindMeSettingPage, {} as Record<string, Object>)
                        })
                    OptionItemView({
                        title: '黑名单',
                    })
                        .onClick(() => {
                            this.mainNavPathStack.pushPathByName(appNavigationDestinations.BlackListPage, {} as Record<string, Object>)
                        })
                }
                .backgroundColor($r('app.color.wf_background'))

                if (this.receiptSupported || this.secretChatSupported) {
                    Column() {
                        if (this.receiptSupported) {
                            ToggleItemView({
                                title: '消息回执',
                                isOn: this.enableReceipt,
                                showDivider: this.secretChatSupported,
                                onChange: (isOn: boolean) => {
                                    this.onReceiptChange(isOn)
                                }
                            })
                        }
                        if (this.secretChatSupported) {
                            ToggleItemView({
                                title: '密聊',
                                isOn: this.enableSecretChat,
                                onChange: (isOn: boolean) => {
                                    this.onSecretChatChange(isOn)
                                }
                            })
                        }
                    }
                    .margin({ top: 12 })
                    .backgroundColor($r('app.color.wf_background'))
                }

                if (this.momentAvailable) {
                    Column() {
                        OptionItemView({
                            title: '朋友圈',
                        })
                            .onClick(() => {
                                this.mainNavPathStack.pushPathByName('moment_privacySettingsPage', {} as Record<string, Object>)
                            })
                    }
                    .margin({ top: 12 })
                    .backgroundColor($r('app.color.wf_background'))
                }

                Column() {
                    ToggleItemView({
                        title: '加我为好友时需要验证',
                        isOn: this.addFriendNeedVerify,
                        onChange: (isOn: boolean) => {
                            this.onAddFriendVerifyChange(isOn)
                        }
                    })
                }
                .margin({ top: 12 })
                .backgroundColor($r('app.color.wf_background'))
            }
            .width('100%')
            .height('100%')
            .backgroundColor($r('app.color.wf_primary_background_color'))
        }
        .title('隐私设置')
        .height('100%')
        .width('100%')
    }
}
