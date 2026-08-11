import wfc from '@wfc/client/src/main/ets/wfc/client/wfc'
import UserSettingScope from '@wfc/client/src/main/ets/wfc/client/userSettingScope'
import ToggleItemView from '@wfc/uikit/src/main/ets/view/ToggleItemView'
import { showToast } from '@wfc/uikit/src/main/ets/common/utils/Toast'
import { FontSize } from '@wfc/uikit/src/main/ets/common/design/Tokens'

// 与 iOS WFCCDisableSearchMask 一致：关闭对应搜索渠道的位掩码
const DISABLE_SEARCH_NAME_MASK = 2 // 账号
const DISABLE_SEARCH_MOBILE_MASK = 4 // 电话号码

@Preview
@Component
export default struct FindMeSettingPage {
    @Consume('mainNavPathStack') mainNavPathStack: NavPathStack;
    // 位掩码：某位置 1 表示关闭该渠道（与 iOS 隐私设置一致）
    @State searchableValue: number = 0

    aboutToAppear() {
        let value = wfc.getUserSetting(UserSettingScope.PrivacySearchable, '')
        let n = parseInt(value)
        this.searchableValue = isNaN(n) ? 0 : n
    }

    private isEnabled(mask: number): boolean {
        return (this.searchableValue & mask) === 0
    }

    private onToggle(mask: number, isOn: boolean) {
        let oldValue = this.searchableValue
        let newValue = isOn ? (oldValue & ~mask) : (oldValue | mask)
        // 乐观更新，失败回滚
        this.searchableValue = newValue
        wfc.setUserSetting(UserSettingScope.PrivacySearchable, '', newValue.toString(), () => {
        }, (err: number) => {
            this.searchableValue = oldValue
            showToast('网络错误')
        })
    }

    build() {
        NavDestination() {
            Column() {
                Text('可以通过以下方法找到我')
                    .fontSize(FontSize.sm)
                    .fontColor($r('app.color.wf_tertiary_text'))
                    .width('100%')
                    .padding({ left: 16, top: 12, bottom: 8 })

                Column() {
                    ToggleItemView({
                        title: '账号',
                        isOn: this.isEnabled(DISABLE_SEARCH_NAME_MASK),
                        showDivider: true,
                        onChange: (isOn: boolean) => {
                            this.onToggle(DISABLE_SEARCH_NAME_MASK, isOn)
                        }
                    })
                    ToggleItemView({
                        title: '电话号码',
                        isOn: this.isEnabled(DISABLE_SEARCH_MOBILE_MASK),
                        onChange: (isOn: boolean) => {
                            this.onToggle(DISABLE_SEARCH_MOBILE_MASK, isOn)
                        }
                    })
                }
                .backgroundColor($r('app.color.wf_background'))
            }
            .width('100%')
            .height('100%')
            .backgroundColor($r('app.color.wf_primary_background_color'))
        }
        .title('找到我的方式')
        .height('100%')
        .width('100%')
    }
}
