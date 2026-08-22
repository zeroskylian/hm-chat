import Message from "./message";
import MessageContent from "./messageContent";
import MessageContentType from "./messageContentType";
import MessagePayload from "./messagePayload";

/**
 * 流式文本取消消息（20）：生成无产出/失败时由机器人发送，携带 streamId。
 * 客户端按 streamId 找到对应的 generating(14)/generated(15) 消息并从消息列表删除，
 * 取消消息自身不显示任何内容、不落库（Transparent）。
 */
export default class StreamingTextCancelledMessageContent extends MessageContent {
    text: string = '';
    streamId: string = '';

    constructor() {
        super(MessageContentType.Streaming_Text_Cancelled);
    }

    encode(): MessagePayload {
        let payload = super.encode();
        payload.searchableContent = this.text;
        payload.content = this.streamId;
        return payload;
    }

    decode(payload: MessagePayload): void {
        super.decode(payload);
        this.text = payload.searchableContent;
        this.streamId = payload.content;
    }

    digest(message?: Message | undefined): string {
        return this.text;
    }
}
