export default class CustomMessageContentType {
    // 朋友圈消息，与其他端协议保持一致，使用 1000 以下的类型值
    static MESSAGE_CONTENT_TYPE_FEED = 501;
    static MESSAGE_CONTENT_TYPE_COMMENT = 502;
    // 1000 以下为内部消息保留，自定义消息需使用 1000 以上的数字
    static MESSAGE_CONTENT_TYPE_CUSTOM_MESSAGE_TEST = 1001;
    static MESSAGE_CONTENT_TYPE_CUSTOM_MESSAGE_TEST_NOTIFICATION = 1002;
    // 添加更多自定义消息
}
