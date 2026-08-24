/*
 * 朋友圈数据模型，对齐 Flutter 版 momentclient.dart 的协议字段定义。
 */
import wfc from '@wfc/client/src/main/ets/wfc/client/wfc'

/**
 * 朋友圈内容类型
 */
export enum FeedContentType {
    Text = 0,
    Image = 1,
    Video = 2,
    Link = 3
}

/**
 * 评论类型
 */
export enum FeedCommentType {
    Comment = 0,
    Thumbup = 1
}

/**
 * 修改朋友圈设置属性
 */
export enum UpdateUserProfileType {
    BackgroundUrl = 0,
    StrangerVisibleCount = 1,
    VisibleScope = 2
}

/**
 * 朋友圈可视范围
 */
export enum VisibleScope {
    NoLimit = 0,
    ThreeDays = 1,
    OneMonth = 2,
    SixMonths = 3
}

// ---- JSON 解析辅助（ArkTS 严格模式，避免 any） ----

function optString(value: Object): string | undefined {
    return typeof value === 'string' ? value : undefined
}

function optNumber(value: Object): number | undefined {
    return typeof value === 'number' ? value : undefined
}

/**
 * 把 id 字段规范化为精确的十进制字符串。
 * 服务端 feedId/commentId 是 int64（约 5e17~7e18），远超 JS 安全整数 2^53，
 * 协议层已把大整数按字符串下发（见 longUtil._reverseToJsLongString）；
 * 这里兼容字符串与安全范围内的数字两种形态，避免任何一处精度丢失。
 */
function optIdString(value: Object): string | undefined {
    if (typeof value === 'string' && value.length > 0 && value !== '0') {
        return value
    }
    // 兼容安全范围内的数字（2^53 以内）；int64 id 已由协议层转为字符串
    if (typeof value === 'number' && value > 0 && value <= 9007199254740991) {
        return value.toString()
    }
    return undefined
}

function optStringArray(value: Object): string[] | undefined {
    if (!Array.isArray(value)) {
        return undefined
    }
    let result: string[] = []
    let list = value as Object[]
    list.forEach(item => {
        if (typeof item === 'string') {
            result.push(item)
        }
    })
    return result
}

/**
 * 媒体信息
 */
export class FeedEntry {
    mediaUrl: string = ''
    thumbUrl?: string
    mediaWidth?: number
    mediaHeight?: number

    toMap(): Record<string, Object> {
        let map: Record<string, Object> = {
            'm': this.mediaUrl
        }
        if (this.thumbUrl !== undefined) {
            map['t'] = this.thumbUrl
        }
        if (this.mediaWidth !== undefined) {
            map['w'] = this.mediaWidth
        }
        if (this.mediaHeight !== undefined) {
            map['h'] = this.mediaHeight
        }
        return map
    }

    static fromMap(map: Record<string, Object>): FeedEntry {
        let entry = new FeedEntry()
        entry.mediaUrl = optString(map['m']) ?? ''
        entry.thumbUrl = optString(map['t'])
        entry.mediaWidth = optNumber(map['w'])
        entry.mediaHeight = optNumber(map['h'])
        return entry
    }
}

/**
 * 朋友圈条目
 */
export class Feed {
    // int64 id，用字符串承载避免精度丢失
    feedId?: string
    sender: string = ''
    type: FeedContentType = FeedContentType.Text
    text?: string
    medias?: FeedEntry[]
    mentionedUsers?: string[]
    toUsers?: string[]
    excludeUsers?: string[]
    serverTime?: number
    extra?: string
    comments?: Comment[]
    hasMoreComments: boolean = false

    toMap(): Record<string, Object> {
        let map: Record<string, Object> = {
            'sender': this.sender,
            'type': this.type,
            'hasMore': this.hasMoreComments
        }
        if (this.feedId !== undefined) {
            map['feedId'] = this.feedId
        }
        if (this.text !== undefined) {
            map['text'] = this.text
        }
        if (this.medias !== undefined) {
            let list: Record<string, Object>[] = []
            this.medias.forEach(entry => {
                list.push(entry.toMap())
            })
            map['medias'] = list
        }
        if (this.mentionedUsers !== undefined) {
            map['mu'] = this.mentionedUsers
        }
        if (this.toUsers !== undefined) {
            map['to'] = this.toUsers
        }
        if (this.excludeUsers !== undefined) {
            map['ex'] = this.excludeUsers
        }
        if (this.serverTime !== undefined) {
            map['timestamp'] = this.serverTime
        }
        if (this.extra !== undefined) {
            map['extra'] = this.extra
        }
        if (this.comments !== undefined) {
            let list: Record<string, Object>[] = []
            this.comments.forEach(comment => {
                list.push(comment.toMap())
            })
            map['comments'] = list
        }
        return map
    }

    static fromMap(map: Record<string, Object>): Feed {
        let feed = new Feed()
        feed.text = optString(map['text'])
        feed.serverTime = optNumber(map['timestamp'])
        let type = optNumber(map['type'])
        feed.type = type !== undefined ? type as FeedContentType : FeedContentType.Text
        feed.feedId = optIdString(map['feedId'])
        feed.sender = optString(map['sender']) ?? wfc.getUserId()
        let medias = map['medias']
        if (Array.isArray(medias)) {
            let list: FeedEntry[] = []
            let items = medias as Object[]
            items.forEach(item => {
                list.push(FeedEntry.fromMap(item as Record<string, Object>))
            })
            feed.medias = list
        }
        feed.toUsers = optStringArray(map['to'])
        feed.excludeUsers = optStringArray(map['ex'])
        feed.mentionedUsers = optStringArray(map['mu'])
        feed.extra = optString(map['extra'])
        let comments = map['comments']
        if (Array.isArray(comments)) {
            let list: Comment[] = []
            let items = comments as Object[]
            items.forEach(item => {
                list.push(Comment.fromMap(item as Record<string, Object>))
            })
            feed.comments = list
        }
        // JSON 接口返回 bool，protobuf 解码（usePB）返回 int（0/1），兼容两种形态。
        let hasMore = map['hasMore']
        if (typeof hasMore === 'boolean') {
            feed.hasMoreComments = hasMore
        } else if (typeof hasMore === 'number') {
            feed.hasMoreComments = hasMore !== 0
        }
        return feed
    }
}

/**
 * 朋友圈评论
 */
export class Comment {
    // int64 id，用字符串承载避免精度丢失
    feedId: string = ''
    commentId?: string
    replyCommentId?: string
    sender: string = ''
    type: FeedCommentType = FeedCommentType.Comment
    text?: string
    replyTo?: string
    serverTime?: number
    extra?: string

    toMap(): Record<string, Object> {
        let map: Record<string, Object> = {
            'feedId': this.feedId,
            'sender': this.sender,
            'type': this.type
        }
        if (this.commentId !== undefined) {
            map['commentId'] = this.commentId
        }
        if (this.replyCommentId !== undefined) {
            map['replyId'] = this.replyCommentId
        }
        if (this.text !== undefined) {
            map['text'] = this.text
        }
        if (this.replyTo !== undefined) {
            map['replyTo'] = this.replyTo
        }
        if (this.serverTime !== undefined) {
            map['serverTime'] = this.serverTime
        }
        if (this.extra !== undefined) {
            map['extra'] = this.extra
        }
        return map
    }

    static fromMap(map: Record<string, Object>): Comment {
        let comment = new Comment()
        comment.text = optString(map['text'])
        comment.serverTime = optNumber(map['serverTime'])
        let type = optNumber(map['type'])
        comment.type = type !== undefined ? type as FeedCommentType : FeedCommentType.Comment
        comment.feedId = optIdString(map['feedId']) ?? ''
        comment.commentId = optIdString(map['commentId'])
        comment.sender = optString(map['sender']) ?? wfc.getUserId()
        comment.extra = optString(map['extra'])
        comment.replyTo = optString(map['replyTo'])
        comment.replyCommentId = optIdString(map['replyId'])
        return comment
    }
}

/**
 * 朋友圈设置
 */
export class Profile {
    backgroundUrl?: string
    blackList?: string[]
    blockList?: string[]
    strangerVisibleCount?: number
    visibleScope?: VisibleScope
    updateDt?: number

    /**
     * null 省略、svc/updateDt 为 0 省略、bgUrl 空串省略
     */
    toMap(): Record<string, Object> {
        let map: Record<string, Object> = {}
        if (this.backgroundUrl !== undefined && this.backgroundUrl.length > 0) {
            map['bgUrl'] = this.backgroundUrl
        }
        if (this.blackList !== undefined) {
            map['blackList'] = this.blackList
        }
        if (this.blockList !== undefined) {
            map['blockList'] = this.blockList
        }
        if (this.strangerVisibleCount !== undefined && this.strangerVisibleCount !== 0) {
            map['svc'] = this.strangerVisibleCount
        }
        if (this.visibleScope !== undefined) {
            map['visiableScope'] = this.visibleScope
        }
        if (this.updateDt !== undefined && this.updateDt !== 0) {
            map['updateDt'] = this.updateDt
        }
        return map
    }

    static fromMap(map: Record<string, Object>): Profile {
        let profile = new Profile()
        profile.backgroundUrl = optString(map['bgUrl'])
        profile.blackList = optStringArray(map['blackList'])
        profile.blockList = optStringArray(map['blockList'])
        profile.strangerVisibleCount = optNumber(map['svc'])
        let scope = optNumber(map['visiableScope'])
        if (scope !== undefined) {
            profile.visibleScope = scope as VisibleScope
        }
        profile.updateDt = optNumber(map['updateDt'])
        return profile
    }
}
