/**
 * 朋友圈模块（@wfc/moment）动态加载器。
 *
 * 入口显隐条件（AppStorage 'momentModuleAvailable'）：
 * 1. chat/oh-package.json5 中声明了 "@wfc/moment": "file:../moment" 依赖
 *    （动态 import 成功；删除依赖后 import 运行时失败被 catch，静默降级）；
 * 2. 且 momentClient.isEnable() 返回 true（即 wfc.isAllowMoments()，服务端
 *    允许朋友圈；该配置在 IM 连接成功后下发，因此连接成功时会重新评估）。
 *
 * 注意：import 说明符必须是字面量，hvigor 只会打包字面量动态 import 的 HAR；
 * chat/uikit 代码中不允许出现对 '@wfc/moment' 的静态 import。
 */
import wfc from '@wfc/client'
import EventType from '@wfc/client/src/main/ets/wfc/client/wfcEvent'
import ConnectionStatus from '@wfc/client/src/main/ets/wfc/client/connectionStatus'

let momentClient: ESObject

function refreshMomentAvailable() {
    if (!momentClient) {
        return
    }
    AppStorage.setOrCreate('momentModuleAvailable', (momentClient.isEnable() as boolean) === true)
}

export async function loadMomentModule(): Promise<boolean> {
    try {
        const m: ESObject = await import('@wfc/moment')
        const client: ESObject = m.momentClient
        client.init()
        momentClient = client
        AppStorage.setOrCreate('momentPageMapBuilder', m.wrappedMomentPageMap as WrappedBuilder<[string]>)
        AppStorage.setOrCreate('momentUnreadCount', client.getUnreadCount() as number)
        refreshMomentAvailable()
        // 服务端配置在连接成功后下发，届时重新评估入口显隐
        wfc.eventEmitter?.on(EventType.ConnectionStatusChanged, (status: number) => {
            if (status === ConnectionStatus.ConnectionStatusConnected) {
                refreshMomentAvailable()
            }
        })
        console.log('loadMomentModule success, moment module loaded')
        return true
    } catch (e) {
        console.error(`loadMomentModule failed, moment module unavailable: ${JSON.stringify(e)}`)
        AppStorage.setOrCreate('momentModuleAvailable', false)
        return false
    }
}
