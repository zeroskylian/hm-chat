import CustomMessageContentType from "./customMessageContentType";

import wfc from '../wfc/client/wfc';
import MessageContent from '../wfc/messages/messageContent'
import MessagePayload from '../wfc/messages/messagePayload';
import { FeedEntry } from './momentFeedMessageContent';

/**
 * 朋友圈评论/点赞消息，内容类型 502
 */
export default class MomentCommentMessageContent extends MessageContent {
    feedId: number = 0;
    commentId: number = 0;
    replyCommentId?: number;
    sender: string = '';
    // 评论类型，0 评论，1 点赞
    commentType: number = 0;
    text?: string;
    replyTo?: string;
    serverTime: number = 0;

    // 冗余的动态摘要信息
    feedType: number = 0;
    feedSender: string = '';
    feedText?: string;
    feedMedias?: FeedEntry[];

    constructor() {
        super(CustomMessageContentType.MESSAGE_CONTENT_TYPE_COMMENT);
    }

    digest() {
        return '';
    }

    encode() {
        let payload = super.encode();
        payload.searchableContent = this.text ? this.text : '';

        let obj: Record<string, Object> = {
            'feedId': this.feedId,
            'commentId': this.commentId,
            'type': this.commentType,
            'sender': this.sender,
            'serverTime': this.serverTime,
            'ftype': this.feedType,
            'fsender': this.feedSender
        };
        if (this.text) {
            obj['text'] = this.text;
        }
        if (this.replyCommentId) {
            obj['replyId'] = this.replyCommentId;
        }
        if (this.replyTo) {
            obj['replyTo'] = this.replyTo;
        }
        if (this.feedText) {
            obj['fcontent'] = this.feedText;
        }
        if (this.feedMedias && this.feedMedias.length > 0) {
            let ms: Record<string, Object>[] = [];
            this.feedMedias.forEach(entry => {
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
            obj['fmedias'] = ms;
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
                let obj = JSON.parse(wfc.b64_to_utf8(payload.binaryContent)) as CommentData;
                this.feedId = obj.feedId || 0;
                this.commentId = obj.commentId || 0;
                this.replyCommentId = obj.replyId ? obj.replyId : undefined;
                this.serverTime = obj.serverTime || 0;
                this.commentType = obj.type || 0;
                this.sender = obj.sender || '';
                this.text = obj.text ? obj.text : undefined;
                this.replyTo = obj.replyTo ? obj.replyTo : undefined;
                if (obj.e) {
                    this.extra = obj.e;
                }

                this.feedType = obj.ftype || 0;
                this.feedSender = obj.fsender || '';
                this.feedText = obj.fcontent ? obj.fcontent : undefined;
                if (obj.fmedias && obj.fmedias.length > 0) {
                    let feedMedias: FeedEntry[] = [];
                    obj.fmedias.forEach(m => {
                        let entry = new FeedEntry();
                        entry.mediaUrl = m.m || '';
                        entry.thumbUrl = m.t ? m.t : undefined;
                        entry.mediaWidth = m.w ? m.w : undefined;
                        entry.mediaHeight = m.h ? m.h : undefined;
                        feedMedias.push(entry);
                    });
                    this.feedMedias = feedMedias;
                }
            } catch (e) {
                console.error('decode MomentCommentMessageContent error', e);
            }
        }
        // 与 Flutter 版本保持一致，text 以 searchableContent 为准
        this.text = payload.searchableContent;
    }
}

class CommentData {
    feedId = 0
    commentId = 0
    replyId = 0
    serverTime = 0
    type = 0
    sender = ''
    text = ''
    replyTo = ''
    e = ''
    ftype = 0
    fsender = ''
    fcontent = ''
    fmedias: FeedEntryData[] = []
}

class FeedEntryData {
    m = ''
    t = ''
    w = 0
    h = 0
}
