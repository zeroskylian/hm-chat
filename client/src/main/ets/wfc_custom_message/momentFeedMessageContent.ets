import CustomMessageContentType from "./customMessageContentType";

import wfc from '../wfc/client/wfc';
import MessageContent from '../wfc/messages/messageContent'
import MessagePayload from '../wfc/messages/messagePayload';
import { _reverseToJsLongString } from '../wfc/util/longUtil';

/**
 * 朋友圈媒体信息
 */
export class FeedEntry {
    mediaUrl: string = '';
    thumbUrl?: string;
    mediaWidth?: number;
    mediaHeight?: number;
}

/**
 * 朋友圈新动态消息，内容类型 501
 */
export default class MomentFeedMessageContent extends MessageContent {
    // int64 id，必须用字符串承载，避免 JSON.parse 精度丢失
    feedId: string = '';
    // 朋友圈内容类型，0 文本，1 图片，2 视频，3 链接
    feedType: number = 0;
    text?: string;
    medias?: FeedEntry[];
    sender: string = '';
    toUsers?: string[];
    excludeUsers?: string[];

    constructor() {
        super(CustomMessageContentType.MESSAGE_CONTENT_TYPE_FEED);
    }

    digest() {
        return '';
    }

    encode() {
        let payload = super.encode();
        payload.searchableContent = this.text ? this.text : '';

        let obj: Record<string, Object> = {
            'feedId': this.feedId,
            't': this.feedType,
            's': this.sender
        };
        if (this.text) {
            obj['c'] = this.text;
        }
        if (this.medias && this.medias.length > 0) {
            let ms: Record<string, Object>[] = [];
            this.medias.forEach(entry => {
                let e: Record<string, Object> = { 'm': entry.mediaUrl };
                if (entry.thumbUrl) {
                    e['t'] = entry.thumbUrl;
                }
                if (entry.mediaWidth) {
                    e['w'] = entry.mediaWidth;
                }
                if (entry.mediaHeight) {
                    e['h'] = entry.mediaHeight;
                }
                ms.push(e);
            });
            obj['ms'] = ms;
        }
        if (this.toUsers && this.toUsers.length > 0) {
            obj['to'] = this.toUsers;
        }
        if (this.excludeUsers && this.excludeUsers.length > 0) {
            obj['ex'] = this.excludeUsers;
        }
        if (this.extra) {
            obj['e'] = this.extra;
        }
        payload.binaryContent = wfc.utf8_to_b64(JSON.stringify(obj));
        return payload;
    }

    decode(payload: MessagePayload) {
        super.decode(payload);
        if (payload.binaryContent) {
            try {
                // 先把 int64 feedId 转为字符串再解析，避免 JS number 精度丢失
                let json = _reverseToJsLongString(wfc.b64_to_utf8(payload.binaryContent), 'feedId');
                let obj = JSON.parse(json) as FeedData;
                this.feedId = obj.feedId ? String(obj.feedId) : '';
                this.feedType = obj.t || 0;
                this.sender = obj.s || '';
                this.text = obj.c ? obj.c : undefined;
                if (obj.ms && obj.ms.length > 0) {
                    let medias: FeedEntry[] = [];
                    obj.ms.forEach(m => {
                        let entry = new FeedEntry();
                        entry.mediaUrl = m.m || '';
                        entry.thumbUrl = m.t ? m.t : undefined;
                        entry.mediaWidth = m.w ? m.w : undefined;
                        entry.mediaHeight = m.h ? m.h : undefined;
                        medias.push(entry);
                    });
                    this.medias = medias;
                }
                this.toUsers = obj.to && obj.to.length > 0 ? obj.to : undefined;
                this.excludeUsers = obj.ex && obj.ex.length > 0 ? obj.ex : undefined;
                if (obj.e) {
                    this.extra = obj.e;
                }
            } catch (e) {
                console.error('decode MomentFeedMessageContent error', e);
            }
        }
    }
}

class FeedData {
    feedId = 0
    t = 0
    s = ''
    c = ''
    ms: FeedEntryData[] = []
    to: string[] = []
    ex: string[] = []
    e = ''
}

class FeedEntryData {
    m = ''
    t = ''
    w = 0
    h = 0
}
