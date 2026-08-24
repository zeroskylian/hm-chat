/*
 * 朋友圈客户端，对齐 Flutter 版 MomentClientImpl。
 * 全部请求走 wfc.sendMomentsRequest，usePB 固定为 true（getFeeds/getFeed 使用 /moments_pb 路径）。
 */
import wfc from '@wfc/client/src/main/ets/wfc/client/wfc'
import EventType from '@wfc/client/src/main/ets/wfc/client/wfcEvent'
import ConnectionStatus from '@wfc/client/src/main/ets/wfc/client/connectionStatus'
import Conversation from '@wfc/client/src/main/ets/wfc/model/conversation'
import ConversationType from '@wfc/client/src/main/ets/wfc/model/conversationType'
import Message from '@wfc/client/src/main/ets/wfc/messages/message'
import MessageContent from '@wfc/client/src/main/ets/wfc/messages/messageContent'
import MessageStatus from '@wfc/client/src/main/ets/wfc/messages/messageStatus'
import Long from '@wfc/client/src/main/ets/wfc/util/long'
import { _patchToJavaLong, _reverseToJsLongString } from '@wfc/client/src/main/ets/wfc/util/longUtil'
import { preferences } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { Feed, Comment, Profile, UpdateUserProfileType, VisibleScope } from '../model/MomentModel'

const TAG = 'MomentClient'

/**
 * 朋友圈消息内容类型。
 * TODO MomentFeedMessageContent/MomentCommentMessageContent（type 501/502）在
 * client/src/main/ets/wfc_custom_message/ 下实现并导出后，收到消息处可改用 instanceof 判断，
 * 回调参数也可换成具体的内容类。
 */
const MESSAGE_CONTENT_TYPE_MOMENT_FEED = 501
const MESSAGE_CONTENT_TYPE_MOMENT_COMMENT = 502

const MOMENTS_PATH = '/moments'
const MOMENTS_PB_PATH = '/moments_pb'

const PREF_STORE_NAME = 'wfcstore'
const PREF_KEY_LAST_READ_TIME = 'wfc_moment_lastreadtime'
const PREF_KEY_DEFAULT_SCOPE_MODE = 'moment_default_scope_mode'
const PREF_KEY_DEFAULT_SCOPE_USERS = 'moment_default_scope_users'

/** 本地缓存上限：只保留最新 50 条，避免翻页后全量 JSON 重写越来越大。 */
const MAX_CACHE_COUNT = 50

/**
 * int64 id（feedId/commentId）为十进制字符串，避免 JS number 精度丢失。
 */
export type FeedId = string

export type OnReceiveNewCommentCallback = (comment: MessageContent) => void
export type OnReceiveMentionedFeedCallback = (feed: MessageContent) => void
export type MomentPostSuccessCallback = (feedId: FeedId, timestamp: number) => void
export type CommentPostSuccessCallback = (commentId: FeedId, timestamp: number) => void
export type FeedsSuccessCallback = (feeds: Feed[]) => void
export type FeedSuccessCallback = (feed: Feed) => void
export type ProfileCallback = (profile: Profile) => void
export type MomentVoidSuccessCallback = () => void
export type FailureCallback = (errorCode: number) => void
export type MessagesSuccessCallback = (messages: Message[]) => void

/**
 * 发布默认可见范围
 */
export interface DefaultVisibleScope {
    mode: number
    users: string[]
}

/**
 * 序列化请求体。id 字段在模型里是字符串（承载 int64 保证精度），
 * 但服务端字段是 Java long，需要把 JSON 文本中这些字段的引号剥掉，
 * 还原成不带引号的数字字面量（只改文本、不经过 JS number，精度无损）。
 */
function serializeBody(body: Record<string, Object>, idKeys: string[]): string {
    let json = JSON.stringify(body)
    idKeys.forEach(key => {
        json = _patchToJavaLong(json, key)
    })
    return json
}

/**
 * 朋友圈客户端
 */
export class MomentClient {
    private inited = false
    private onReceiveNewCommentCallback?: OnReceiveNewCommentCallback
    private onReceiveMentionedFeedCallback?: OnReceiveMentionedFeedCallback

    /**
     * 使用之前必须初始化。两个回调可通过参数传入，也可之后通过 setter 设置。
     * 重复调用只会更新回调，不会重复注册监听。
     */
    init(newCommentCallback?: OnReceiveNewCommentCallback, mentionedFeedCallback?: OnReceiveMentionedFeedCallback) {
        if (newCommentCallback) {
            this.onReceiveNewCommentCallback = newCommentCallback
        }
        if (mentionedFeedCallback) {
            this.onReceiveMentionedFeedCallback = mentionedFeedCallback
        }
        if (this.inited) {
            return
        }
        this.inited = true

        // 监听 IM 下行消息，过滤出朋友圈相关消息（Single 会话、line=1）。
        wfc.eventEmitter?.on(EventType.ReceiveMessage, this.onReceiveMessage)
        // 连接成功后自动拉取前 20 条朋友圈，与 WFMomentService 行为一致。
        wfc.eventEmitter?.on(EventType.ConnectionStatusChanged, this.onConnectionStatusChanged)
    }

    setOnReceiveNewCommentCallback(callback: OnReceiveNewCommentCallback) {
        this.onReceiveNewCommentCallback = callback
    }

    /**
     * 服务端是否开启朋友圈功能（依赖 IM 连接后下发的配置，未连接时可能为 false）。
     */
    isEnable(): boolean {
        return wfc.isAllowMoments()
    }

    setOnReceiveMentionedFeedCallback(callback: OnReceiveMentionedFeedCallback) {
        this.onReceiveMentionedFeedCallback = callback
    }

    private onReceiveMessage = (messages: Message[]) => {
        messages.forEach(message => {
            if (message.conversation.type !== ConversationType.Single || message.conversation.line !== 1) {
                return
            }
            let contentType = this.messageContentType(message)
            if (contentType === MESSAGE_CONTENT_TYPE_MOMENT_COMMENT && this.onReceiveNewCommentCallback) {
                this.onReceiveNewCommentCallback(message.messageContent)
            } else if (contentType === MESSAGE_CONTENT_TYPE_MOMENT_FEED && this.onReceiveMentionedFeedCallback) {
                this.onReceiveMentionedFeedCallback(message.messageContent)
            }
        })
        // 每次收到消息刷新朋友圈未读数
        AppStorage.setOrCreate<number>('momentUnreadCount', this.getUnreadCount())
    }

    private onConnectionStatusChanged = (status: number) => {
        if (status === ConnectionStatus.ConnectionStatusConnected) {
            this.getFeeds(0, 20, null, () => {
            }, () => {
            })
        }
    }

    /**
     * 解码后内容优先，payload 兜底（内容类未注册时 decode 可能失败）。
     */
    private messageContentType(message: Message): number {
        if (message.messageContent) {
            return message.messageContent.type
        }
        if (message.content) {
            return message.content.type
        }
        return -1
    }

    /**
     * 发布朋友圈
     */
    postFeed(feed: Feed, success: MomentPostSuccessCallback, fail: FailureCallback) {
        // body 为 feed.toMap() 中发布所需字段（不含 feedId/timestamp/comments/hasMore），sender 为当前用户
        let body: Record<string, Object> = {
            'sender': wfc.getUserId(),
            'type': feed.type
        }
        let fullMap = feed.toMap()
        const allowedKeys: string[] = ['text', 'medias', 'mu', 'to', 'ex', 'extra']
        allowedKeys.forEach(key => {
            let value = fullMap[key]
            if (value !== undefined && value !== null) {
                body[key] = value
            }
        })

        wfc.sendMomentsRequest(`${MOMENTS_PATH}/feed/post`, JSON.stringify(body), (errorCode, response) => {
            if (errorCode === 0 && response) {
                // id 是 int64，先转为字符串再解析，避免 JS number 精度丢失
                let map = JSON.parse(_reverseToJsLongString(response, 'id')) as Record<string, Object>
                let feedId = typeof map['id'] === 'string' ? map['id'] as string : ''
                let timestamp = typeof map['timestamp'] === 'number' ? map['timestamp'] as number : 0
                success(feedId, timestamp)
            } else {
                fail(errorCode)
            }
        })
    }

    /**
     * 删除朋友圈，朋友圈必须属于当前用户才能删除
     */
    deleteFeed(feedId: FeedId, success: MomentVoidSuccessCallback, fail: FailureCallback) {
        let body: Record<string, Object> = {
            'id': feedId
        }
        wfc.sendMomentsRequest(`${MOMENTS_PATH}/feed/recall`, serializeBody(body, ['id']), (errorCode, response) => {
            if (errorCode === 0) {
                success()
            } else {
                fail(errorCode)
            }
        })
    }

    /**
     * 批量获取朋友圈。fromIndex == 0 覆盖缓存，否则读缓存追加再写（不去重，对齐 Flutter）
     */
    getFeeds(fromIndex: number | FeedId, count: number, user: string | null, success: FeedsSuccessCallback, fail: FailureCallback) {
        let body: Record<string, Object> = {}
        if (typeof fromIndex === 'string') {
            if (fromIndex.length > 0) {
                body['feedId'] = fromIndex
            }
        } else if (fromIndex > 0) {
            body['feedId'] = fromIndex
        }
        if (count > 0) {
            body['count'] = count
        }
        if (user !== null && user.length > 0) {
            body['user'] = user
        }

        wfc.sendMomentsRequest(`${MOMENTS_PB_PATH}/feed/pull`, serializeBody(body, ['feedId']), (errorCode, response) => {
            if (errorCode === 0 && response) {
                let feeds: Feed[] = []
                // feedId/commentId 是 int64，先转为字符串再解析，避免 JS number 精度丢失
                let json = _reverseToJsLongString(response, 'feedId');
                json = _reverseToJsLongString(json, 'commentId');
                json = _reverseToJsLongString(json, 'replyId');
                let list = JSON.parse(json) as Object
                if (Array.isArray(list)) {
                    let items = list as Object[]
                    items.forEach(item => {
                        feeds.push(Feed.fromMap(item as Record<string, Object>))
                    })
                }
                if (typeof fromIndex === 'string' ? fromIndex.length === 0 : fromIndex === 0) {
                    this.storeFeeds(feeds, user)
                } else {
                    let exist = this.feedsRestore(user)
                    exist.push(...feeds)
                    this.storeFeeds(exist, user)
                }
                success(feeds)
            } else {
                fail(errorCode)
            }
        })
    }

    /**
     * 获取单条朋友圈
     */
    getFeed(feedId: FeedId, success: FeedSuccessCallback, fail: FailureCallback) {
        let body: Record<string, Object> = {
            'feedId': feedId
        }
        wfc.sendMomentsRequest(`${MOMENTS_PB_PATH}/feed/pull_one`, serializeBody(body, ['feedId']), (errorCode, response) => {
            if (errorCode === 0 && response) {
                // feedId/commentId 是 int64，先转为字符串再解析，避免 JS number 精度丢失
                let json = _reverseToJsLongString(response, 'feedId');
                json = _reverseToJsLongString(json, 'commentId');
                json = _reverseToJsLongString(json, 'replyId');
                let map = JSON.parse(json) as Record<string, Object>
                success(Feed.fromMap(map))
            } else {
                fail(errorCode)
            }
        })
    }

    /**
     * 发布评论或点赞
     */
    postComment(comment: Comment, success: CommentPostSuccessCallback, fail: FailureCallback) {
        comment.sender = wfc.getUserId()
        wfc.sendMomentsRequest(`${MOMENTS_PATH}/comment/post`, serializeBody(comment.toMap(), ['feedId', 'commentId', 'replyId']), (errorCode, response) => {
            if (errorCode === 0 && response) {
                // id 是 int64，先转为字符串再解析，避免 JS number 精度丢失
                let map = JSON.parse(_reverseToJsLongString(response, 'id')) as Record<string, Object>
                let commentId = typeof map['id'] === 'string' ? map['id'] as string : ''
                let timestamp = typeof map['timestamp'] === 'number' ? map['timestamp'] as number : 0
                success(commentId, timestamp)
            } else {
                fail(errorCode)
            }
        })
    }

    /**
     * 删除评论或点赞
     */
    deleteComment(commentId: FeedId, feedId: FeedId, success: MomentVoidSuccessCallback, fail: FailureCallback) {
        let body: Record<string, Object> = {
            'id': commentId,
            'id2': feedId
        }
        wfc.sendMomentsRequest(`${MOMENTS_PATH}/comment/recall`, serializeBody(body, ['id', 'id2']), (errorCode, response) => {
            if (errorCode === 0) {
                success()
            } else {
                fail(errorCode)
            }
        })
    }

    /**
     * 获取评论或提醒消息（Single 会话、line=1）。
     * isNew 为 true 时只取未读，否则取全部；fromIndex 非 0 时传当前已加载最后一条的 messageId。
     *
     * 注意：getMessagesExV2/getMessagesByStatusV2 的 fromIndex/before/count 参数文档标注"暂时无效"，
     * 这里按签名传参；若运行时返回全量，则按 messageId < fromIndex 客户端过滤兜底。
     */
    getFeedMessages(fromIndex: number, isNew: boolean): Promise<Message[]> {
        return new Promise((resolve, reject) => {
            let onResult = (messages: Message[]) => {
                let result = messages.filter(message => {
                    let contentType = this.messageContentType(message)
                    return contentType === MESSAGE_CONTENT_TYPE_MOMENT_FEED
                        || contentType === MESSAGE_CONTENT_TYPE_MOMENT_COMMENT
                })
                if (fromIndex > 0) {
                    result = result.filter(message => message.messageId < fromIndex)
                }
                resolve(result)
            }
            let onError = (errorCode: number) => {
                reject(new Error(`getFeedMessages failed: ${errorCode}`))
            }
            if (isNew) {
                wfc.getMessagesByStatusV2(new Conversation(ConversationType.Single, '', 1),
                    [MessageStatus.Unread], fromIndex, true, 100, '', onResult, onError)
            } else {
                wfc.getMessagesExV2([ConversationType.Single], [1], fromIndex, true, 100, '',
                    [MESSAGE_CONTENT_TYPE_MOMENT_FEED, MESSAGE_CONTENT_TYPE_MOMENT_COMMENT], onResult, onError)
            }
        })
    }

    /**
     * 加载远端朋友圈历史消息
     */
    loadRemoteFeedMessages(beforeUid: Long | number, count: number, success: MessagesSuccessCallback, fail: FailureCallback) {
        wfc.loadRemoteMessages(new Conversation(ConversationType.Single, '', 1),
            [MESSAGE_CONTENT_TYPE_MOMENT_FEED, MESSAGE_CONTENT_TYPE_MOMENT_COMMENT],
            Long.fromValue(beforeUid), count, success, fail)
    }

    /**
     * 获取朋友圈消息未读数量
     */
    getUnreadCount(): number {
        return wfc.getUnreadCount([ConversationType.Single], [1]).unread
    }

    /**
     * 清除朋友圈消息未读数量
     */
    clearUnreadStatus() {
        wfc.clearConversationsUnreadStatus([ConversationType.Single], [1])
    }

    /**
     * 记录最后阅读时间（秒级）
     */
    updateLastReadTimestamp() {
        let timestamp = Math.floor(Date.now() / 1000)
        this.putInt(PREF_KEY_LAST_READ_TIME, timestamp)
    }

    /**
     * 获取最后阅读时间（秒级）
     */
    getLastReadTimestamp(): number {
        return this.getInt(PREF_KEY_LAST_READ_TIME, 0)
    }

    /**
     * 发布默认可见范围
     */
    getDefaultVisibleScope(): DefaultVisibleScope {
        let mode = this.getInt(PREF_KEY_DEFAULT_SCOPE_MODE, 0)
        let users: string[] = []
        let usersJson = this.getString(PREF_KEY_DEFAULT_SCOPE_USERS, '[]')
        try {
            let list = JSON.parse(usersJson) as Object
            if (Array.isArray(list)) {
                let items = list as Object[]
                items.forEach(item => {
                    if (typeof item === 'string') {
                        users.push(item)
                    }
                })
            }
        } catch (e) {
            console.error(`${TAG} parse default scope users failed: ${JSON.stringify(e)}`)
        }
        let result: DefaultVisibleScope = { mode: mode, users: users }
        return result
    }

    setDefaultVisibleScope(mode: number, users: string[]) {
        this.putInt(PREF_KEY_DEFAULT_SCOPE_MODE, mode)
        this.putString(PREF_KEY_DEFAULT_SCOPE_USERS, JSON.stringify(users))
    }

    /**
     * 获取朋友圈设置。双回调：先读缓存有则立即回调一次，请求成功写缓存后再回调第二次。
     */
    getUserProfile(userId: string, callback: ProfileCallback, fail?: FailureCallback) {
        let cachedProfile = this.profileFromStore(userId)
        if (cachedProfile) {
            callback(cachedProfile)
        }

        let body: Record<string, Object> = {
            'u': userId
        }
        if (cachedProfile && cachedProfile.updateDt !== undefined && cachedProfile.updateDt !== 0) {
            body['d'] = cachedProfile.updateDt
        }

        wfc.sendMomentsRequest(`${MOMENTS_PATH}/profiles/pull`, JSON.stringify(body), (errorCode, response) => {
            if (errorCode === 0 && response) {
                let map = JSON.parse(response) as Record<string, Object>
                let profile = Profile.fromMap(map)
                this.profileToStore(userId, profile)
                callback(profile)
            } else {
                if (fail) {
                    fail(errorCode)
                }
            }
        })
    }

    /**
     * 更新朋友圈设置
     */
    updateMyProfile(type: UpdateUserProfileType, strValue: string | null, intValue: number | null,
        success: MomentVoidSuccessCallback, fail: FailureCallback) {
        let body: Record<string, Object> = {
            't': type
        }
        if (strValue !== null && strValue.length > 0) {
            body['v'] = strValue
        }
        if (intValue !== null && intValue !== 0) {
            body['i'] = intValue
        }
        wfc.sendMomentsRequest(`${MOMENTS_PATH}/profiles/value/push`, JSON.stringify(body), (errorCode, response) => {
            if (errorCode === 0) {
                // 服务端返回最新 updateDt，同步进本地 profile 缓存：
                // 保证更新（背景等）后立即生效，且不会被 getUserProfile 的旧缓存回调回退。
                let updateDt = 0
                if (response) {
                    try {
                        let map = JSON.parse(response) as Record<string, Object>
                        if (typeof map['updateDt'] === 'number') {
                            updateDt = map['updateDt'] as number
                        }
                    } catch (e) {
                        console.error(`${TAG} parse updateMyProfile response failed: ${JSON.stringify(e)}`)
                    }
                }
                this.applyProfileUpdate(type, strValue, intValue, updateDt)
                success()
            } else {
                fail(errorCode)
            }
        })
    }

    /**
     * 把本次设置合并进本地 profile 缓存（含服务端返回的最新 updateDt）。
     */
    private applyProfileUpdate(type: UpdateUserProfileType, strValue: string | null, intValue: number | null, updateDt: number) {
        let userId = wfc.getUserId()
        let profile = this.profileFromStore(userId)
        if (!profile) {
            profile = new Profile()
        }
        if (type === UpdateUserProfileType.BackgroundUrl && strValue !== null && strValue.length > 0) {
            profile.backgroundUrl = strValue
        } else if (type === UpdateUserProfileType.StrangerVisibleCount && intValue !== null) {
            profile.strangerVisibleCount = intValue
        } else if (type === UpdateUserProfileType.VisibleScope && intValue !== null) {
            profile.visibleScope = intValue as VisibleScope
        }
        if (updateDt !== 0) {
            profile.updateDt = updateDt
        }
        this.profileToStore(userId, profile)
    }

    /**
     * 更新block和black的列表
     */
    updateBlackOrBlockList(isBlock: boolean, addList: string[], removeList: string[],
        success: MomentVoidSuccessCallback, fail: FailureCallback) {
        let body: Record<string, Object> = {
            'b': isBlock
        }
        if (addList.length > 0) {
            body['al'] = addList
        }
        if (removeList.length > 0) {
            body['rl'] = removeList
        }
        wfc.sendMomentsRequest(`${MOMENTS_PATH}/profiles/list/push`, JSON.stringify(body), (errorCode, response) => {
            if (errorCode === 0) {
                success()
            } else {
                fail(errorCode)
            }
        })
    }

    // ---- 缓存 ----

    /**
     * 缓存朋友圈数据（JSON 字符串数组，上限 50 条截断）。
     * feed 按时间倒序，截断尾部即可保留最新条目。
     */
    storeFeeds(feeds: Feed[], userId?: string | null) {
        let list = feeds
        if (list.length > MAX_CACHE_COUNT) {
            list = list.slice(0, MAX_CACHE_COUNT)
        }
        let arr: string[] = []
        list.forEach(feed => {
            arr.push(JSON.stringify(feed.toMap()))
        })
        this.putString(this.feedsCacheKey(userId), JSON.stringify(arr))
    }

    /**
     * 获取缓存的朋友圈数据
     */
    feedsRestore(userId?: string | null): Feed[] {
        let json = this.getString(this.feedsCacheKey(userId), '')
        if (!json) {
            return []
        }
        let feeds: Feed[] = []
        try {
            let list = JSON.parse(json) as Object
            if (Array.isArray(list)) {
                let items = list as Object[]
                items.forEach(item => {
                    if (typeof item === 'string') {
                        feeds.push(Feed.fromMap(JSON.parse(item) as Record<string, Object>))
                    }
                })
            }
        } catch (e) {
            console.error(`${TAG} restore feeds cache failed: ${JSON.stringify(e)}`)
        }
        return feeds
    }

    /**
     * 把单条 feed 合并进本地缓存（按 feedId 替换，不存在则插入头部）。
     * 供详情页互动/刷新后保持列表缓存一致，退出重进时不回退。
     */
    updateFeedCache(feed: Feed, userId?: string | null) {
        let exist = this.feedsRestore(userId)
        let idx = exist.findIndex(f => f.feedId === feed.feedId)
        if (idx !== -1) {
            exist[idx] = feed
        } else {
            exist.unshift(feed)
        }
        this.storeFeeds(exist, userId)
    }

    private feedsCacheKey(userId?: string | null): string {
        if (userId !== undefined && userId !== null && userId.length > 0) {
            return `feeds_${userId}`
        }
        return `feeds_all_${wfc.getUserId()}`
    }

    private profileFromStore(userId: string): Profile | null {
        let json = this.getString(`moment_profile_${userId}`, '')
        if (!json) {
            return null
        }
        try {
            let profile = Profile.fromMap(JSON.parse(json) as Record<string, Object>)
            if (profile.updateDt !== undefined && profile.updateDt !== 0) {
                return profile
            }
        } catch (e) {
            console.error(`${TAG} restore profile cache failed: ${JSON.stringify(e)}`)
        }
        return null
    }

    private profileToStore(userId: string, profile: Profile) {
        if (profile.updateDt !== undefined && profile.updateDt !== 0) {
            this.putString(`moment_profile_${userId}`, JSON.stringify(profile.toMap()))
        }
    }

    // ---- preferences（同步 API，store 名 'wfcstore'） ----

    private getPreferences(): preferences.Preferences | null {
        try {
            let context = AppStorage.get<common.UIAbilityContext>('context')
            if (!context) {
                return null
            }
            return preferences.getPreferencesSync(context.getApplicationContext(), { name: PREF_STORE_NAME })
        } catch (e) {
            console.error(`${TAG} getPreferences failed: ${JSON.stringify(e)}`)
            return null
        }
    }

    private getString(key: string, defValue: string): string {
        let pref = this.getPreferences()
        if (!pref) {
            return defValue
        }
        return pref.getSync(key, defValue) as string
    }

    private putString(key: string, value: string) {
        let pref = this.getPreferences()
        if (!pref) {
            return
        }
        pref.putSync(key, value)
        pref.flush()
    }

    private getInt(key: string, defValue: number): number {
        let pref = this.getPreferences()
        if (!pref) {
            return defValue
        }
        return pref.getSync(key, defValue) as number
    }

    private putInt(key: string, value: number) {
        let pref = this.getPreferences()
        if (!pref) {
            return
        }
        pref.putSync(key, value)
        pref.flush()
    }
}

export const momentClient = new MomentClient()
