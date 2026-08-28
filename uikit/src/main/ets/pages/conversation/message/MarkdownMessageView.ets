/*
 * 轻量 Markdown 渲染组件（无第三方依赖）。
 * 用于 AI 流式回复等含 Markdown 格式的文本消息。
 * 支持：标题(#1-6)、粗体(**)、斜体(*)、粗斜体(***)、删除线(~~)、行内代码(`)、
 * 代码块(```)、无序列表(-、*、+)、有序列表(1.、1)、嵌套列表(缩进 2 空格一级)、
 * 引用(>)、分隔线(---)、链接([text](url))、裸链接自动识别、表格(| + |---|)。
 * 排版：段间距体系（段落 6 / 标题 10+4 / 列表项 4 / 代码块·引用·表格 8 / 分割线 16）。
 * 流式场景容错：未闭合的代码块、行内标记按字面渲染，不崩溃；
 * 流式中表格只出现表头（无分隔行）时按普通段落渲染。
 */
export interface MdSpanData {
    text: string
    bold: boolean
    italic: boolean
    code: boolean
    link: boolean
    url: string
    // 删除线（~~text~~），可选以兼容既有构造点
    strike?: boolean
}

export interface MdBlockData {
    // heading / code / quote / list / table / hr / paragraph
    type: string
    // heading 级别 1-6；list 为嵌套层级 0-4
    level: number
    // 列表是否有序
    ordered: boolean
    // 列表标记（无序点号，有序序号）
    marker: string
    text: string
    // 表格：rows[0] 为表头，其余为数据行
    rows?: string[][]
    // 表格各列对齐：left / center / right
    aligns?: string[]
}

// ArkTS 不支持正则字面量，统一用 new RegExp
const RE_HEADING = new RegExp('^(#{1,6})\\s+(.*)$')
const RE_TRAIL_HASH = new RegExp('\\s+#+\\s*$')
const RE_HR = new RegExp('^([-*_])\\1{2,}$')
const RE_QUOTE = new RegExp('^>\\s?')
const RE_UL = new RegExp('^[-*+]\\s+')
const RE_OL = new RegExp('^\\d{1,3}[.)]\\s+')
const RE_UL_ITEM = new RegExp('^[-*+]\\s+(.*)$')
const RE_OL_ITEM = new RegExp('^(\\d{1,3})[.)]\\s+(.*)$')
// 表格分隔行：| --- | :---: | 等，仅由 | : - 空格组成且至少两列
const RE_TABLE_SEP = new RegExp('^\\s*\\|?\\s*:?-+:?\\s*(\\|\\s*:?-+:?\\s*)+\\|?\\s*$')
// 列表项缩进续行：2 个及以上前导空白
const RE_INDENTED = new RegExp('^\\s{2,}[^\\s]')
// 裸链接：仅 ASCII 合法字符，避免把后续中文吞进链接
const RE_URL = new RegExp("https?://[A-Za-z0-9._~:/?#%@!$&'()*+,;=%\\-\\[\\]]+", 'g')
// 表格单元格内转义竖线的占位符
const ESC_PIPE_PLACEHOLDER = '\u0001'
// 表格列数上限：超过则整块降级为段落
const TABLE_MAX_COLS = 8
// 列表嵌套层级上限
const LIST_MAX_LEVEL = 4

function mkPlain(text: string): MdSpanData {
    return { text: text, bold: false, italic: false, code: false, link: false, url: '' }
}

function mkLink(text: string, url: string): MdSpanData {
    return { text: text, bold: false, italic: false, code: false, link: true, url: url }
}

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
                this.buildSpans(block.text, false)
            }
            .fontSize(block.level === 1 ? 20 : block.level === 2 ? 18 : block.level === 3 ? 16 : 15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.wf_primary_text'))
            .width('100%')
            .margin({ top: 10, bottom: 4 })
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
            .margin({ top: 4, bottom: 4 })
        } else if (block.type === 'table') {
            this.buildTable(block)
        } else if (block.type === 'quote') {
            Row() {
                Column()
                    .width(3)
                    .height('100%')
                    .borderRadius(2)
                    .backgroundColor($r('app.color.wf_tertiary_text'))
                Text() {
                    this.buildSpans(block.text, false)
                }
                .fontSize(14)
                .fontColor($r('app.color.wf_secondary_text'))
                .layoutWeight(1)
                .margin({ left: 8 })
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            .margin({ top: 4, bottom: 4 })
        } else if (block.type === 'list') {
            Row() {
                Text(block.marker)
                    .fontSize(14)
                    .fontColor($r('app.color.wf_primary_text'))
                    .margin({ right: 6 })
                Text() {
                    this.buildSpans(block.text, false)
                }
                .fontSize(14)
                .fontColor($r('app.color.wf_primary_text'))
                .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            .padding({ left: block.level * 12 })
            .margin({ top: 2, bottom: 2 })
        } else if (block.type === 'hr') {
            Divider()
                .color($r('app.color.wf_divider'))
                .strokeWidth(0.5)
                .margin({ top: 8, bottom: 8 })
        } else {
            Text() {
                this.buildSpans(block.text, false)
            }
            .fontSize(14)
            .fontColor($r('app.color.wf_primary_text'))
            .width('100%')
            .margin({ top: 3, bottom: 3 })
        }
    }

    @Builder
    private buildTable(block: MdBlockData) {
        Column() {
            // 表头
            Row() {
                ForEach((block.rows && block.rows.length > 0 ? block.rows[0] : []), (cell: string, ci: number) => {
                    Text() {
                        this.buildSpans(cell, true)
                    }
                    .fontSize(13)
                    .fontColor($r('app.color.wf_primary_text'))
                    .textAlign(this.alignOf(block.aligns, ci))
                    .constraintSize({ minWidth: 40 })
                    .layoutWeight(1)
                    .padding(6)
                }, (cell: string, ci: number) => `th_${ci}`)
            }
            .width('100%')
            .backgroundColor($r('app.color.wf_secondary_background'))
            .alignItems(VerticalAlign.Center)

            // 数据行
            ForEach((block.rows ?? []).slice(1), (row: string[], ri: number) => {
                Row() {
                    ForEach(row, (cell: string, ci: number) => {
                        Text() {
                            this.buildSpans(cell, false)
                        }
                        .fontSize(13)
                        .fontColor($r('app.color.wf_primary_text'))
                        .textAlign(this.alignOf(block.aligns, ci))
                        .constraintSize({ minWidth: 40 })
                        .layoutWeight(1)
                        .padding(6)
                    }, (cell: string, ci: number) => `td_${ri}_${ci}`)
                }
                .width('100%')
                .alignItems(VerticalAlign.Top)
                .border({ width: { top: 0.5 }, color: { top: $r('app.color.wf_divider') } })
            }, (row: string[], ri: number) => `tr_${ri}`)
        }
        .width('100%')
        .border({ width: 0.5, color: $r('app.color.wf_divider') })
        .borderRadius(6)
        .margin({ top: 4, bottom: 4 })
    }

    @Builder
    private buildSpans(text: string, boldAll: boolean) {
        ForEach(this.parseInline(text), (span: MdSpanData, index: number) => {
            if (span.link) {
                Span(span.text)
                    .fontColor($r('app.color.wf_link'))
                    .decoration({ type: TextDecorationType.Underline })
                    .fontWeight(boldAll || span.bold ? FontWeight.Bold : FontWeight.Normal)
                    .onClick(() => this.onLinkClick(span.url))
            } else if (span.code) {
                Span(span.text)
                    .fontColor($r('app.color.wf_primary_text'))
                    .fontFamily('monospace')
                    .fontSize(13)
            } else if (span.strike) {
                Span(span.text)
                    .fontWeight(boldAll || span.bold ? FontWeight.Bold : FontWeight.Normal)
                    .fontStyle(span.italic ? FontStyle.Italic : FontStyle.Normal)
                    .decoration({ type: TextDecorationType.LineThrough })
            } else {
                Span(span.text)
                    .fontWeight(boldAll || span.bold ? FontWeight.Bold : FontWeight.Normal)
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
            // 表格：当前行含 | 且下一行是分隔行
            if (trimmed.indexOf('|') >= 0 && i + 1 < lines.length && RE_TABLE_SEP.test(lines[i + 1])) {
                let header = this.splitTableRow(trimmed)
                if (header.length >= 2 && header.length <= TABLE_MAX_COLS) {
                    let aligns = this.splitTableRow(lines[i + 1]).map((c: string) => this.alignOfCell(c))
                    i += 2
                    let rows: string[][] = [header]
                    while (i < lines.length) {
                        let t = lines[i].trim()
                        if (t.length === 0 || t.indexOf('|') < 0) {
                            break
                        }
                        rows.push(this.splitTableRow(t))
                        i++
                    }
                    blocks.push({ type: 'table', level: 0, ordered: false, marker: '', text: '', rows: rows, aligns: aligns })
                    continue
                } else {
                    // 列数不支持：整块降级为普通段落，避免死循环
                    let fallback: string[] = [line, lines[i + 1]]
                    i += 2
                    while (i < lines.length && lines[i].trim().length > 0 && lines[i].indexOf('|') >= 0) {
                        fallback.push(lines[i])
                        i++
                    }
                    blocks.push({ type: 'paragraph', level: 0, ordered: false, marker: '', text: fallback.join('\n') })
                    continue
                }
            }
            // 标题
            let heading = RE_HEADING.exec(trimmed)
            if (heading && heading.length >= 3 && heading[2].length > 0) {
                // 容错 GFM 收尾 #：## 标题 ##
                let hText = heading[2].replace(RE_TRAIL_HASH, '')
                blocks.push({ type: 'heading', level: heading[1].length, ordered: false, marker: '', text: hText })
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
            // 列表：合并连续列表行（支持缩进嵌套与缩进续行）
            if (RE_UL.test(trimmed) || RE_OL.test(trimmed)) {
                while (i < lines.length) {
                    let raw = lines[i]
                    let t = raw.trim()
                    let um = RE_UL_ITEM.exec(t)
                    let om = RE_OL_ITEM.exec(t)
                    if (um) {
                        blocks.push({
                            type: 'list', level: this.listLevel(raw), ordered: false, marker: '•', text: um[1]
                        })
                        i++
                    } else if (om) {
                        blocks.push({
                            type: 'list', level: this.listLevel(raw), ordered: true, marker: `${om[1]}.`, text: om[2]
                        })
                        i++
                    } else if (t.length > 0 && RE_INDENTED.test(raw) && blocks.length > 0
                        && blocks[blocks.length - 1].type === 'list') {
                        // 缩进续行：并入上一个列表项
                        let lastBlk = blocks[blocks.length - 1]
                        lastBlk.text = lastBlk.text + '\n' + t
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
                // 段落中途出现表格头（| 行 + 分隔行）：断开段落交给表格分支
                if (t.indexOf('|') >= 0 && i + 1 < lines.length && RE_TABLE_SEP.test(lines[i + 1])) {
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
                spans.push(mkPlain(plain))
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
                    spans.push({
                        text: text.substring(i + 1, end), bold: false, italic: false,
                        code: true, link: false, url: ''
                    })
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
                        spans.push(mkLink(text.substring(i + 1, close), url))
                        i = end + 1
                        continue
                    }
                }
            }
            // 粗斜体 ***text***
            if (text.startsWith('***', i)) {
                let end = text.indexOf('***', i + 3)
                if (end > i + 3) {
                    flushPlain()
                    spans.push({
                        text: text.substring(i + 3, end), bold: true, italic: true,
                        code: false, link: false, url: ''
                    })
                    i = end + 3
                    continue
                }
            }
            // 粗体 **text**
            if (text.startsWith('**', i)) {
                let end = text.indexOf('**', i + 2)
                if (end > i + 2) {
                    flushPlain()
                    spans.push({
                        text: text.substring(i + 2, end), bold: true, italic: false,
                        code: false, link: false, url: ''
                    })
                    i = end + 2
                    continue
                }
            }
            // 斜体 *text*
            if (c === '*') {
                let end = text.indexOf('*', i + 1)
                if (end > i + 1) {
                    flushPlain()
                    spans.push({
                        text: text.substring(i + 1, end), bold: false, italic: true,
                        code: false, link: false, url: ''
                    })
                    i = end + 1
                    continue
                }
            }
            // 删除线 ~~text~~
            if (text.startsWith('~~', i)) {
                let end = text.indexOf('~~', i + 2)
                if (end > i + 2) {
                    flushPlain()
                    spans.push({
                        text: text.substring(i + 2, end), bold: false, italic: false,
                        code: false, link: false, url: '', strike: true
                    })
                    i = end + 2
                    continue
                }
            }
            // 普通字符
            plain = plain + c
            i++
        }
        flushPlain()
        return this.linkify(spans)
    }

    /** 裸链接识别：把纯文本 span 中的 URL 拆分为可点击链接。 */
    private linkify(spans: MdSpanData[]): MdSpanData[] {
        let out: MdSpanData[] = []
        for (let s of spans) {
            if (s.link || s.code || s.text.indexOf('http') < 0) {
                out.push(s)
                continue
            }
            RE_URL.lastIndex = 0
            let last = 0
            let m = RE_URL.exec(s.text)
            while (m !== null) {
                if (m.index > last) {
                    out.push(mkPlain(s.text.substring(last, m.index)))
                }
                let url = this.trimUrlTail(m[0])
                if (url.length > 0) {
                    out.push(mkLink(url, url))
                }
                last = m.index + url.length
                RE_URL.lastIndex = m.index + url.length
                m = RE_URL.exec(s.text)
            }
            if (last < s.text.length) {
                out.push(mkPlain(s.text.substring(last)))
            }
        }
        RE_URL.lastIndex = 0
        return out
    }

    /** 去掉 URL 尾部常见标点与未配对的右括号。 */
    private trimUrlTail(u: string): string {
        let url = u
        while (url.length > 0) {
            let c = url.charAt(url.length - 1)
            if ('.,;:!?…。，；：！？'.indexOf(c) >= 0) {
                url = url.substring(0, url.length - 1)
                continue
            }
            if (c === ')') {
                let opens = 0
                let closes = 0
                for (let k = 0; k < url.length; k++) {
                    if (url.charAt(k) === '(') {
                        opens++
                    } else if (url.charAt(k) === ')') {
                        closes++
                    }
                }
                if (closes > opens) {
                    url = url.substring(0, url.length - 1)
                    continue
                }
            }
            break
        }
        return url
    }

    // ===== 表格辅助 =====

    /** 拆分表格行为单元格：去首尾 |，按 | 分割（容忍 \| 转义），逐格 trim。 */
    private splitTableRow(line: string): string[] {
        let t = line.trim()
        if (t.startsWith('|')) {
            t = t.substring(1)
        }
        if (t.endsWith('|')) {
            t = t.substring(0, t.length - 1)
        }
        // 先把转义竖线 \| 换成占位符再分割
        let safe = ''
        for (let k = 0; k < t.length; k++) {
            if (t.charAt(k) === '\\' && k + 1 < t.length && t.charAt(k + 1) === '|') {
                safe = safe + ESC_PIPE_PLACEHOLDER
                k++
            } else {
                safe = safe + t.charAt(k)
            }
        }
        return safe.split('|').map((c: string) => c.trim().split(ESC_PIPE_PLACEHOLDER).join('|'))
    }

    /** 分隔行单元格 → 对齐方式。 */
    private alignOfCell(cell: string): string {
        let s = cell.trim()
        if (s.startsWith(':') && s.endsWith(':')) {
            return 'center'
        }
        if (s.endsWith(':')) {
            return 'right'
        }
        return 'left'
    }

    private alignOf(aligns: string[] | undefined, index: number): TextAlign {
        let a = aligns && index < aligns.length ? aligns[index] : 'left'
        if (a === 'center') {
            return TextAlign.Center
        }
        if (a === 'right') {
            return TextAlign.End
        }
        return TextAlign.Start
    }

    // ===== 列表辅助 =====

    /** 按前导空白计算嵌套层级：2 空格一级，封顶 LIST_MAX_LEVEL。 */
    private listLevel(line: string): number {
        let spaces = 0
        for (let k = 0; k < line.length; k++) {
            let c = line.charAt(k)
            if (c === ' ') {
                spaces++
            } else if (c === '\t') {
                spaces += 2
            } else {
                break
            }
        }
        return Math.min(Math.floor(spaces / 2), LIST_MAX_LEVEL)
    }
}
