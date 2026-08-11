import wfc from './src/main/ets/wfc/client/wfc'

// 导出备份恢复模块
export * as backup from './src/main/ets/wfc/backup';

// 导出朋友圈消息内容类，供 moment 模块做 instanceof 判断
export {
    default as MomentFeedMessageContent,
    FeedEntry
} from './src/main/ets/wfc_custom_message/momentFeedMessageContent';
export { default as MomentCommentMessageContent } from './src/main/ets/wfc_custom_message/momentCommentMessageContent';

export default wfc
