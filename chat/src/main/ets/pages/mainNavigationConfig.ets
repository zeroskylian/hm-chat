import { UIKitPageMap, UIKIT_NAV_DESTINATION_PREFIX } from "@wfc/uikit/src/main/ets/pages/uikitNavigationConfig"
import AboutPage from "./me/AboutPage"
import AccountPage from "./me/AccountPage"
import ChangePasswordPage from "./me/ChangePasswordPage"
import DestroyAccountPage from "./me/DestroyAccountPage"
import ResetPasswordPage from "./me/ResetPasswordPage"
import SettingPage from "./me/SettingPage"
import PrivacySettingPage from "./me/PrivacySettingPage"
import FindMeSettingPage from "./me/FindMeSettingPage"
import BlackListPage from "./me/BlackListPage"
import FontSizeSettingPage from "./me/FontSizeSettingPage"
import TestPage from "./test/TestPage"
import BackupAndRestorePage from "./backup/BackupAndRestorePage"
import BackupTargetPage from "./backup/BackupTargetPage"
import ConversationSelectPage from "./backup/ConversationSelectPage"
import BackupOptionsPage from "./backup/BackupOptionsPage"
import BackupProgressPage from "./backup/BackupProgressPage"
import RestoreSourcePage from "./backup/RestoreSourcePage"
import BackupListPage from "./backup/BackupListPage"
import RestoreOptionsPage from "./backup/RestoreOptionsPage"
import RestoreProgressPage from "./backup/RestoreProgressPage"
import PCBackupProgressPage from "./backup/PCBackupProgressPage"
import PCRestoreListPage from "./backup/PCRestoreListPage"
import PCRestoreProgressPage from "./backup/PCRestoreProgressPage"

const APP_NAV_DESTINATION_PREFIX = 'app-'
// 朋友圈路由前缀，与 @wfc/moment 的 MOMENT_NAV_DESTINATION_PREFIX 保持一致（不允许静态 import，此处本地定义）
const MOMENT_NAV_DESTINATION_PREFIX = 'moment_'

export class appNavigationDestinations {
    static AboutPage = APP_NAV_DESTINATION_PREFIX + 'aboutPage'
    static AccountPage = APP_NAV_DESTINATION_PREFIX + 'accountPage'
    static ResetPasswordPage = APP_NAV_DESTINATION_PREFIX + 'resetPasswordPage'
    static ChangePasswordPage = APP_NAV_DESTINATION_PREFIX + 'changePasswordPage'
    static SettingPage = APP_NAV_DESTINATION_PREFIX + 'settingPage'
    static PrivacySettingPage = APP_NAV_DESTINATION_PREFIX + 'privacySettingPage'
    static FindMeSettingPage = APP_NAV_DESTINATION_PREFIX + 'findMeSettingPage'
    static BlackListPage = APP_NAV_DESTINATION_PREFIX + 'blackListPage'
    static FontSizeSettingPage = APP_NAV_DESTINATION_PREFIX + 'fontSizeSettingPage'
    static DestroyAccountPage = APP_NAV_DESTINATION_PREFIX + 'destroyAccountPage'
    static BackupAndRestorePage = APP_NAV_DESTINATION_PREFIX + 'backupAndRestorePage'
    static BackupTargetPage = APP_NAV_DESTINATION_PREFIX + 'backupTargetPage'
    static ConversationSelectPage = APP_NAV_DESTINATION_PREFIX + 'conversationSelectPage'
    static BackupOptionsPage = APP_NAV_DESTINATION_PREFIX + 'backupOptionsPage'
    static BackupProgressPage = APP_NAV_DESTINATION_PREFIX + 'backupProgressPage'
    static RestoreSourcePage = APP_NAV_DESTINATION_PREFIX + 'restoreSourcePage'
    static BackupListPage = APP_NAV_DESTINATION_PREFIX + 'backupListPage'
    static RestoreOptionsPage = APP_NAV_DESTINATION_PREFIX + 'restoreOptionsPage'
    static RestoreProgressPage = APP_NAV_DESTINATION_PREFIX + 'restoreProgressPage'
    static PCBackupProgressPage = APP_NAV_DESTINATION_PREFIX + 'pcBackupProgressPage'
    static PCRestoreListPage = APP_NAV_DESTINATION_PREFIX + 'pcRestoreListPage'
    static PCRestoreProgressPage = APP_NAV_DESTINATION_PREFIX + 'pcRestoreProgressPage'
}

@Builder
export function AppPageMap(name: string) {
    if (name === appNavigationDestinations.AboutPage) {
        AboutPage()
    } else if (name === appNavigationDestinations.AccountPage) {
        AccountPage()
    } else if (name === appNavigationDestinations.ResetPasswordPage) {
        ResetPasswordPage()
    } else if (name === appNavigationDestinations.ChangePasswordPage) {
        ChangePasswordPage()
    } else if (name === appNavigationDestinations.SettingPage) {
        SettingPage()
    } else if (name === appNavigationDestinations.PrivacySettingPage) {
        PrivacySettingPage()
    } else if (name === appNavigationDestinations.FindMeSettingPage) {
        FindMeSettingPage()
    } else if (name === appNavigationDestinations.BlackListPage) {
        BlackListPage()
    } else if (name === appNavigationDestinations.FontSizeSettingPage) {
        FontSizeSettingPage()
    } else if (name === 'testPage') {
        TestPage()
    } else if (name === appNavigationDestinations.DestroyAccountPage) {
        DestroyAccountPage()
    } else if (name === appNavigationDestinations.BackupAndRestorePage) {
        BackupAndRestorePage()
    } else if (name === appNavigationDestinations.BackupTargetPage) {
        BackupTargetPage()
    } else if (name === appNavigationDestinations.ConversationSelectPage) {
        ConversationSelectPage()
    } else if (name === appNavigationDestinations.BackupOptionsPage) {
        BackupOptionsPage()
    } else if (name === appNavigationDestinations.BackupProgressPage) {
        BackupProgressPage()
    } else if (name === appNavigationDestinations.RestoreSourcePage) {
        RestoreSourcePage()
    } else if (name === appNavigationDestinations.BackupListPage) {
        BackupListPage()
    } else if (name === appNavigationDestinations.RestoreOptionsPage) {
        RestoreOptionsPage()
    } else if (name === appNavigationDestinations.RestoreProgressPage) {
        RestoreProgressPage()
    } else if (name === appNavigationDestinations.PCBackupProgressPage) {
        PCBackupProgressPage()
    } else if (name === appNavigationDestinations.PCRestoreListPage) {
        PCRestoreListPage()
    } else if (name === appNavigationDestinations.PCRestoreProgressPage) {
        PCRestoreProgressPage()
    }
}

/**
 * 朋友圈 NavDestination 动态分派：路由表由 momentModuleLoader 动态 import @wfc/moment 后
 * 以 WrappedBuilder 形式写入 AppStorage；模块不可用时落到 not found。
 */
@Component
export struct MomentDynamicDest {
    name: string = ''
    @StorageLink('momentPageMapBuilder') momentPageMapBuilder: WrappedBuilder<[string]> | undefined = undefined

    build() {
        if (this.momentPageMapBuilder) {
            this.momentPageMapBuilder.builder(this.name)
        } else {
            NavDestination() {
                Column() {
                    Text('Nav destination not found')
                }
                .width('100%')
                .height('100%')
            }
        }
    }
}

@Builder
export function MainPageMap(name: string) {
    if (name.startsWith(APP_NAV_DESTINATION_PREFIX)) {
        AppPageMap(name)
    } else if (name.startsWith(UIKIT_NAV_DESTINATION_PREFIX)) {
        UIKitPageMap(name)
    } else if (name.startsWith(MOMENT_NAV_DESTINATION_PREFIX)) {
        MomentDynamicDest({ name: name })
    } else {
        NavDestination() {
            Column() {
                Text('Nav destination not found')
            }
            .width('100%')
            .height('100%')
        }
    }
}
