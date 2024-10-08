/*
 * Copyright (c) 2020 WildFireChat. All rights reserved.
 */

import wfc from '../../client/wfc'
import MessageContentType from '../messageContentType';
import MessagePayload from '../messagePayload';
import GroupNotificationContent from './groupNotification';

export default class AddGroupMemberNotification extends GroupNotificationContent {
    invitor = '';
    invitees = [] as string[];
    ex?: object | string

    constructor(invitor: string = '', invitees: string[] = []) {
        super(MessageContentType.AddGroupMember_Notification);
        this.invitor = invitor;
        this.invitees = invitees;
    }

    formatNotification() {
        let notifyStr: string;
        if (this.invitees.length === 1 && this.invitees[0] === this.invitor) {
            if (this.fromSelf) {
                return '您加入了群组';
            } else {
                return wfc.getGroupMemberDisplayName(this.groupId, this.invitor) + ' 加入了群组';
            }
        }

        if (this.fromSelf) {
            notifyStr = '您邀请:';
        } else {
            notifyStr = wfc.getGroupMemberDisplayName(this.groupId, this.invitor) + '邀请:';
        }

        let membersStr = '';
        let userInfos = wfc.getUserInfos(this.invitees, this.groupId);
        userInfos.forEach(m => {
            membersStr += ' ' + m.displayName;
        });

        return notifyStr + membersStr + '加入了群组';
    }

    encode() {
        let payload = super.encode();
        let obj = {
            g: this.groupId,
            o: this.invitor,
            ms: this.invitees,
            ex: this.ex
        } as Data;
        payload.binaryContent = wfc.utf8_to_b64(JSON.stringify(obj));
        return payload;
    }

    decode(payload: MessagePayload) {
        super.decode(payload);
        let json = wfc.b64_to_utf8(payload.binaryContent);
        let obj = JSON.parse(json) as Data;
        this.groupId = obj.g;
        this.invitor = obj.o;
        this.invitees = obj.ms;
        this.ex = obj.ex
    }
}

class Data {
    g = '';
    o = '';
    ms = [] as string[]
    ex?: object | string
}
