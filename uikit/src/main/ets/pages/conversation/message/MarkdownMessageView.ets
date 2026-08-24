/*
 * 轻量 Markdown 渲染组件（无第三方依赖）。
 * 用于 AI 流式回复等含 Markdown 格式的文本消息。
 * 支持：标题(#1-6)、粗体(**)、斜体(*)、行内代码(`)、代码块(```)、
 * 无序列表(-、*、+)、有序列表(1.)、引用(>)、分隔线(---)、链接([text](url))。
 * 流式场景容错：未闭合的代码块、行内标记按字面渲染，不崩溃。
 */
import { FontSize } from '../../../common/design/Tokens'

export interface MdSpanData {
    text: string
    bold: boolean
    italic: boolean
    code: boolean
    link: boolean
    url: string
}

export interface MdBlockData {
    // heading / code / quote / list / hr / paragraph
    type: string
    // heading 级别 1-6
    level: number
    // 列表是否有序
    ordered: boolean
    // 列表标记（无序点号，有序序号）
    marker: string
    text: string
}

// ArkTS 不支持正则字面量，统一用 new RegExp
const RE_HEADING = new RegExp('^(#{1,6})\\s+(.*)$')
const RE_HR = new RegExp('^([-*_])\\1{2,}$')
const RE_QUOTE = new RegExp('^>\\s?')
const RE_UL = new RegExp('^[-*+]\\s+')
const RE_OL = new RegExp('^\\d+[.)]\\s+')
const RE_UL_ITEM = new RegExp('^[-*+]\\s+(.*)$')
const RE_OL_ITEM = new RegExp('^(\\d+)[.)]\\s+(.*)$')

@Component
export struct MarkdownMessageView {
    @Prop markdownText: string
    onLinkClick: (url: string) => void = () => {};

    build() {
        Column() {
            ForEach(this.parseBlocks(this.markdownText), (block: MdBlockData, index: number) => {
                this.buildBlock(block, index)
            }, (block: MdBlockData, index: number) => `md_${block.type}_${index}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
    }

    // ===== 块渲染 =====

    @Builder
    private buildBlock(block: MdBlockData, index: number) {
        if (block.type === 'heading') {
            Text() {
                this.buildSpans(block.text)
            }
            .fontSize(block.level === 1 ? 20 : block.level === 2 ? 18 : block.level === 3 ? 16 : 15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.wf_primary_text'))
            .width('100%')
            .margin({ top: 4, bottom: 2 })
        } else if (block.type === 'code') {
            Column() {
                Text(block.text)
                    .fontSize(13)
                    .fontColor($r('app.color.wf_primary_text'))
                    .fontFamily('monospace')
                    .width('100%')
            }
            .width('100%')
            .padding(8)
            .borderRadius(6)
            .backgroundColor($r('app.color.wf_secondary_background'))
            .margin({ top: 2, bottom: 2 })
        } else if (block.type === 'quote') {
            Row() {
                Column()
                    .width(3)
                    .height('100%')
                    .borderRadius(2)
                    .backgroundColor($r('app.color.wf_tertiary_text'))
                Text() {
                    this.buildSpans(block.text)
                }
                .fontSize(14)
                .fontColor($r('app.color.wf_secondary_text'))
                .layoutWeight(1)
                .margin({ left: 8 })
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            .margin({ top: 2, bottom: 2 })
        } else if (block.type === 'list') {
            Row() {
                Text(block.marker)
                    .fontSize(14)
                    .fontColor($r('app.color.wf_primary_text'))
                    .margin({ right: 6 })
                Text() {
                    this.buildSpans(block.text)
                }
                .fontSize(14)
                .fontColor($r('app.color.wf_primary_text'))
                .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            .margin({ top: 1, bottom: 1 })
        } else if (block.type === 'hr') {
            Divider()
                .color($r('app.color.wf_divider'))
                .strokeWidth(0.5)
                .margin({ top: 6, bottom: 6 })
        } else {
            Text() {
                this.buildSpans(block.text)
            }
            .fontSize(14)
            .fontColor($r('app.color.wf_primary_text'))
            .width('100%')
            .margin({ top: 1, bottom: 1 })
        }
    }

    @Builder
    private buildSpans(text: string) {
        ForEach(this.parseInline(text), (span: MdSpanData, index: number) => {
            if (span.link) {
                Span(span.text)
                    .fontColor($r('app.color.wf_link'))
                    .decoration({ type: TextDecorationType.Underline })
                    .onClick(() => this.onLinkClick(span.url))
            } else if (span.code) {
                Span(span.text)
                    .fontColor($r('app.color.wf_primary_text'))
                    .fontFamily('monospace')
                    .fontSize(13)
            } else {
                Span(span.text)
                    .fontWeight(span.bold ? FontWeight.Bold : FontWeight.Normal)
                    .fontStyle(span.italic ? FontStyle.Italic : FontStyle.Normal)
            }
        }, (span: MdSpanData, index: number) => `sp_${index}`)
    }

    // ===== 块解析 =====

    private parseBlocks(markdown: string): MdBlockData[] {
        let blocks: MdBlockData[] = []
        if (!markdown) {
            return blocks
        }
        let lines = markdown.split('\n')
        let i = 0
        while (i < lines.length) {
            let line = lines[i]
            let trimmed = line.trim()
            // 代码块
            if (trimmed.startsWith('```')) {
                let codeLines: string[] = []
                i++
                while (i < lines.length && !lines[i].trim().startsWith('```')) {
                    codeLines.push(lines[i])
                    i++
                }
                i++ // 跳过结束标记（不存在则自然结束）
                blocks.push({ type: 'code', level: 0, ordered: false, marker: '', text: codeLines.join('\n') })
                continue
            }
            // 标题
            let heading = RE_HEADING.exec(trimmed)
            if (heading && heading.length >= 3 && heading[2].length > 0) {
                blocks.push({ type: 'heading', level: heading[1].length, ordered: false, marker: '', text: heading[2] })
                i++
                continue
            }
            // 分隔线
            if (RE_HR.test(trimmed)) {
                blocks.push({ type: 'hr', level: 0, ordered: false, marker: '', text: '' })
                i++
                continue
            }
            // 引用：合并连续 > 行
            if (trimmed.startsWith('>')) {
                let quoteLines: string[] = []
                while (i < lines.length && lines[i].trim().startsWith('>')) {
                    quoteLines.push(lines[i].trim().replace(RE_QUOTE, ''))
                    i++
                }
                blocks.push({ type: 'quote', level: 0, ordered: false, marker: '', text: quoteLines.join('\n') })
                continue
            }
            // 列表：合并连续列表行
            if (RE_UL.test(trimmed) || RE_OL.test(trimmed)) {
                while (i < lines.length) {
                    let t = lines[i].trim()
                    let um = RE_UL_ITEM.exec(t)
                    let om = RE_OL_ITEM.exec(t)
                    if (um) {
                        blocks.push({ type: 'list', level: 0, ordered: false, marker: '•', text: um[1] })
                        i++
                    } else if (om) {
                        blocks.push({ type: 'list', level: 0, ordered: true, marker: `${om[1]}.`, text: om[2] })
                        i++
                    } else {
                        break
                    }
                }
                continue
            }
            // 空行
            if (trimmed.length === 0) {
                i++
                continue
            }
            // 普通段落：合并到空行或下一个特殊块前
            let paraLines: string[] = []
            while (i < lines.length) {
                let t = lines[i].trim()
                if (t.length === 0 || t.startsWith('```') || RE_HEADING.test(t)
                    || RE_UL.test(t) || RE_OL.test(t) || t.startsWith('>')
                    || RE_HR.test(t)) {
                    break
                }
                paraLines.push(lines[i])
                i++
            }
            blocks.push({ type: 'paragraph', level: 0, ordered: false, marker: '', text: paraLines.join('\n') })
        }
        return blocks
    }

    // ===== 行内解析 =====

    private parseInline(text: string): MdSpanData[] {
        let spans: MdSpanData[] = []
        if (!text) {
            return spans
        }
        let plain: string = ''
        let flushPlain = () => {
            if (plain.length > 0) {
                spans.push({ text: plain, bold: false, italic: false, code: false, link: false, url: '' })
                plain = ''
            }
        }
        let i = 0
        while (i < text.length) {
            let c = text.charAt(i)
            // 行内代码 `code`
            if (c === '`') {
                let end = text.indexOf('`', i + 1)
                if (end > i) {
                    flushPlain()
                    spans.push({ text: text.substring(i + 1, end), bold: false, italic: false, code: true, link: false, url: '' })
                    i = end + 1
                    continue
                }
            }
            // 链接 [label](url)
            if (c === '[') {
                let close = text.indexOf(']', i + 1)
                if (close > i && text.charAt(close + 1) === '(') {
                    let end = text.indexOf(')', close + 2)
                    if (end > close + 2) {
                        flushPlain()
                        let url = text.substring(close + 2, end)
                        spans.push({ text: text.substring(i + 1, close), bold: false, italic: false, code: false, link: true, url: url })
                        i = end + 1
                        continue
                    }
                }
            }
            // 粗体 **text**
            if (text.startsWith('**', i)) {
                let end = text.indexOf('**', i + 2)
                if (end > i + 2) {
                    flushPlain()
                    spans.push({ text: text.substring(i + 2, end), bold: true, italic: false, code: false, link: false, url: '' })
                    i = end + 2
                    continue
                }
            }
            // 斜体 *text*
            if (c === '*') {
                let end = text.indexOf('*', i + 1)
                if (end > i + 1) {
                    flushPlain()
                    spans.push({ text: text.substring(i + 1, end), bold: false, italic: true, code: false, link: false, url: '' })
                    i = end + 1
                    continue
                }
            }
            // 普通字符
            plain = plain + c
            i++
        }
        flushPlain()
        return spans
    }
}
