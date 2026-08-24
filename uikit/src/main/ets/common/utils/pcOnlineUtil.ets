/*
 * PC/多端在线信息展示辅助：平台图标与设备名称。
 * 多端登录条（会话列表）与「已登录的设备」页共用，保证图标/命名一致。
 *
 * 注意：PCOnlineInfo 的 type（PC/Web/WX/Pad 在线类型）由服务端权威下发，
 * 而 platform 是各端上报的具体平台号，老客户端可能上报 0（UNSET），
 * 因此图标/命名以 type 为主、platform 为辅，避免 platform 缺失时全部显示成手机。
 */
import Platform from '@wfc/client/src/main/ets/wfc/client/platform'
import PCOnlineInfo from '@wfc/client/src/main/ets/wfc/model/pcOnlineInfo'

/**
 * 平台灰色图标（SymbolGlyph 资源）。
 */
export function pcPlatformSymbol(info: PCOnlineInfo): Resource {
    switch (info.type) {
        case PCOnlineInfo.PC_Online:
            return $r('sys.symbol.computer')
        case PCOnlineInfo.Web_Online:
            return $r('sys.symbol.desktop_site')
        case PCOnlineInfo.Pad_Online:
            return $r('sys.symbol.pad')
        case PCOnlineInfo.WX_Online:
            return $r('sys.symbol.phone')
        case PCOnlineInfo.Wearable_Online:
            return $r('sys.symbol.watch')
        case PCOnlineInfo.TV_Online:
            return $r('sys.symbol.TV_tv')
        default:
            // type 未知时按具体平台兜底
            switch (info.platform.platform) {
                case Platform.PlatformType_Windows:
                case Platform.PlatformType_OSX:
                case Platform.PlatformType_Linux:
                case Platform.PlatformType_Harmony_PC:
                    return $r('sys.symbol.computer')
                case Platform.PlatformType_WEB:
                    return $r('sys.symbol.desktop_site')
                case Platform.PlatformType_WX:
                    return $r('sys.symbol.phone')
                case Platform.PlatformType_iPad:
                case Platform.PlatformType_APad:
                case Platform.PlatformType_Harmony_Pad:
                    return $r('sys.symbol.pad')
                case Platform.PlatformType_AndroidWearable:
                case Platform.PlatformType_HarmonyWearable:
                    return $r('sys.symbol.watch')
                case Platform.PlatformType_AndroidTV:
                case Platform.PlatformType_AppleTV:
                case Platform.PlatformType_HarmonyTV:
                    return $r('sys.symbol.TV_tv')
                default:
                    return $r('sys.symbol.phone')
            }
    }
}

/**
 * 设备名称（微信风格）：Windows / Mac / Web / 微信小程序 / iPad / 手表 / 电视 等。
 */
export function pcDeviceName(info: PCOnlineInfo): string {
    switch (info.type) {
        case PCOnlineInfo.WX_Online:
            return '微信小程序'
        case PCOnlineInfo.Wearable_Online:
            return '手表'
        case PCOnlineInfo.TV_Online:
            return '电视'
        default:
            break
    }
    let name = info.platform.getPlatFormName()
    if (name === 'PC') {
        // platform 未上报（UNSET）时按在线类型回退
        if (info.type === PCOnlineInfo.Web_Online) {
            return 'Web'
        }
        if (info.type === PCOnlineInfo.Pad_Online) {
            return '平板'
        }
        return '电脑'
    }
    return name
}

/**
 * 是否为桌面电脑类设备（支持「锁定电脑」等操作）。
 */
export function isPcDesktopDevice(info: PCOnlineInfo): boolean {
    if (info.type === PCOnlineInfo.PC_Online) {
        return true
    }
    let platform = info.platform.platform
    return platform === Platform.PlatformType_Windows
        || platform === Platform.PlatformType_OSX
        || platform === Platform.PlatformType_Linux
        || platform === Platform.PlatformType_Harmony_PC
}
