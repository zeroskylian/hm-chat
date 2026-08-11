/*
 * 朋友圈媒体上传辅助，对齐 Flutter 版 moment_upload.dart。
 *
 * 统一走 wfc.uploadMediaFile / wfc.uploadMedia，图片会额外生成缩略图
 * （最长边 400px，PNG）并上传，作为九宫格里的缩略展示。
 */
import image from '@ohos.multimedia.image'
import fs from '@ohos.file.fs'
import { common } from '@kit.AbilityKit'
import wfc from '@wfc/client/src/main/ets/wfc/client/wfc'
import MessageContentMediaType from '@wfc/client/src/main/ets/wfc/messages/messageContentMediaType'
import { FeedEntry } from '../model/MomentModel'

const TAG = 'MomentUpload'
const THUMB_MAX_SIDE = 400

/**
 * 相册选择器返回的是 file://media/... 临时授权 URI，request 上传只能使用
 * 应用沙箱（cacheDir）下的文件（与聊天发图片消息的处理一致，见 uikit mediaHelper）。
 * 这里先把外部 URI 拷贝到 cacheDir，返回沙箱路径；已是沙箱路径的原样返回。
 */
function ensureSandboxPath(filePath: string, defaultExt: string): string {
    if (filePath.startsWith('/')) {
        return filePath
    }
    const context = AppStorage.get<common.UIAbilityContext>('context')
    if (!context) {
        return filePath
    }
    // 必须是 applicationContext.cacheDir：client proto 上传时按 internal://cache 映射
    // （见 mediaHelper.sendMediaResult 的注释），模块级 cacheDir 会找不到文件
    const cacheDir = context.getApplicationContext().cacheDir
    let ext = ''
    const dotIndex = filePath.lastIndexOf('.')
    if (dotIndex > 0 && dotIndex > filePath.lastIndexOf('/')) {
        ext = filePath.substring(dotIndex)
    }
    if (!ext) {
        ext = defaultExt
    }
    const dstPath = `${cacheDir}/moment_${Date.now()}_${Math.floor(Math.random() * 100000)}${ext}`
    const srcFile = fs.openSync(filePath)
    const dstFile = fs.openSync(dstPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE)
    fs.copyFileSync(srcFile.fd, dstFile.fd)
    fs.closeSync(srcFile)
    fs.closeSync(dstFile)
    return dstPath
}

/**
 * 上传单个文件并返回远端 URL。
 */
function uploadFile(filePath: string, mediaType: number): Promise<string> {
    return new Promise((resolve, reject) => {
        wfc.uploadMediaFile(filePath, mediaType, (remoteUrl) => {
            resolve(remoteUrl)
        }, (errorCode) => {
            reject(new Error(`upload failed: ${errorCode}`))
        }, (current, total) => {
        })
    })
}

/**
 * 上传内存数据（base64）并返回远端 URL。
 */
function uploadBytes(fileName: string, base64Data: string, mediaType: number): Promise<string> {
    return new Promise((resolve, reject) => {
        wfc.uploadMedia(fileName, base64Data, mediaType, (remoteUrl) => {
            resolve(remoteUrl)
        }, (errorCode) => {
            reject(new Error(`upload failed: ${errorCode}`))
        }, (current, total) => {
        })
    })
}

/**
 * 上传一张图片并生成 FeedEntry（含原图 URL、缩略图 URL、原图宽高）。
 * 缩略图：最长边等比缩放到 THUMB_MAX_SIDE，PNG 编码。
 */
export async function uploadImage(filePath: string): Promise<FeedEntry> {
    const localPath = ensureSandboxPath(filePath, '.jpg')
    let file: fs.File | undefined
    try {
        file = await fs.open(localPath, fs.OpenMode.READ_ONLY)
        const imageSource: image.ImageSource = image.createImageSource(file.fd)
        const imageInfo: image.ImageInfo = await imageSource.getImageInfo()
        const width = imageInfo.size.width
        const height = imageInfo.size.height

        let thumbBase64 = ''
        let pixelMap: image.PixelMap | undefined
        if (width > THUMB_MAX_SIDE || height > THUMB_MAX_SIDE) {
            const scale = THUMB_MAX_SIDE / Math.max(width, height)
            pixelMap = await imageSource.createPixelMap({
                desiredSize: { width: Math.round(width * scale), height: Math.round(height * scale) }
            })
        } else {
            pixelMap = await imageSource.createPixelMap()
        }
        if (pixelMap) {
            const imagePacker = image.createImagePacker()
            const packOpts: image.PackingOption = { format: 'image/png', quality: 100 }
            const data: ArrayBuffer = await imagePacker.packing(pixelMap, packOpts)
            thumbBase64 = wfc.arrayBuffer_to_b64(data)
            pixelMap.release()
        }
        imageSource.release()

        const mediaUrl = await uploadFile(localPath, MessageContentMediaType.Image)
        const thumbUrl = await uploadBytes(`thumb_${Date.now()}.png`, thumbBase64, MessageContentMediaType.Image)

        let entry = new FeedEntry()
        entry.mediaUrl = mediaUrl
        entry.thumbUrl = thumbUrl
        entry.mediaWidth = width
        entry.mediaHeight = height
        return entry
    } finally {
        if (file) {
            fs.closeSync(file)
        }
    }
}

/**
 * 上传一个视频并生成 FeedEntry（无缩略图，九宫格显示播放占位）。
 */
export async function uploadVideo(filePath: string): Promise<FeedEntry> {
    const mediaUrl = await uploadFile(ensureSandboxPath(filePath, '.mp4'), MessageContentMediaType.Video)
    let entry = new FeedEntry()
    entry.mediaUrl = mediaUrl
    return entry
}

/**
 * 上传单个媒体文件并返回远端 URL（背景图等不需要 FeedEntry 的场景）。
 */
export async function uploadMomentMedia(filePath: string): Promise<string> {
    return uploadFile(ensureSandboxPath(filePath, '.jpg'), MessageContentMediaType.Image)
}
