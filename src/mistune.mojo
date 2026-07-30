"""Markdown block parsing and HTML rendering over caller-owned UTF-8 buffers."""

comptime BPtr = UnsafePointer[UInt8, UntrackedOrigin[mut=True]]


struct Writer:
    var dst: BPtr
    var capacity: Int
    var position: Int

    def __init__(out self, dst: BPtr, capacity: Int):
        self.dst = dst
        self.capacity = capacity
        self.position = 0

    def byte(mut self, value: UInt8):
        if self.position < self.capacity:
            self.dst[self.position] = value
        self.position += 1

    def literal(mut self, value: StringSlice):
        var data = value.as_bytes()
        for i in range(len(data)):
            self.byte(data[i])

    def source(mut self, src: BPtr, start: Int, end: Int):
        for i in range(start, end):
            self.byte(src[i])


def line_end(src: BPtr, n: Int, start: Int) -> Int:
    var i = start
    while i < n and src[i] != UInt8(10):
        i += 1
    if i > start and src[i - 1] == UInt8(13):
        return i - 1
    return i


def next_line(src: BPtr, n: Int, start: Int) -> Int:
    var i = start
    while i < n and src[i] != UInt8(10):
        i += 1
    return i + 1 if i < n else n


def trim_left(src: BPtr, start: Int, end: Int) -> Int:
    var i = start
    while i < end and (src[i] == UInt8(32) or src[i] == UInt8(9)):
        i += 1
    return i


def trim_right(src: BPtr, start: Int, end: Int) -> Int:
    var i = end
    while i > start and (src[i - 1] == UInt8(32) or src[i - 1] == UInt8(9)):
        i -= 1
    return i


def is_blank(src: BPtr, start: Int, end: Int) -> Bool:
    return trim_left(src, start, end) == end


def lower(c: UInt8) -> UInt8:
    if c >= UInt8(65) and c <= UInt8(90):
        return c + UInt8(32)
    return c


def ascii_equal(src: BPtr, start: Int, end: Int, text: StringSlice) -> Bool:
    var data = text.as_bytes()
    if end - start != len(data):
        return False
    for i in range(len(data)):
        if lower(src[start + i]) != lower(data[i]):
            return False
    return True


def starts_with(src: BPtr, start: Int, end: Int, text: StringSlice) -> Bool:
    var data = text.as_bytes()
    if end - start < len(data):
        return False
    for i in range(len(data)):
        if src[start + i] != data[i]:
            return False
    return True


def starts_with_fold(src: BPtr, start: Int, end: Int, text: StringSlice) -> Bool:
    var data = text.as_bytes()
    if end - start < len(data):
        return False
    for i in range(len(data)):
        if lower(src[start + i]) != lower(data[i]):
            return False
    return True


def put_escaped(mut writer: Writer, c: UInt8):
    if c == UInt8(38):
        writer.literal("&amp;")
    elif c == UInt8(60):
        writer.literal("&lt;")
    elif c == UInt8(62):
        writer.literal("&gt;")
    elif c == UInt8(34):
        writer.literal("&quot;")
    else:
        writer.byte(c)


def render_escaped(mut writer: Writer, src: BPtr, start: Int, end: Int):
    for i in range(start, end):
        put_escaped(writer, src[i])


def is_punctuation(c: UInt8) -> Bool:
    return (
        c == UInt8(33) or c == UInt8(34) or c == UInt8(35) or c == UInt8(36)
        or c == UInt8(37) or c == UInt8(38) or c == UInt8(39) or c == UInt8(40)
        or c == UInt8(41) or c == UInt8(42) or c == UInt8(43) or c == UInt8(44)
        or c == UInt8(45) or c == UInt8(46) or c == UInt8(47) or c == UInt8(58)
        or c == UInt8(59) or c == UInt8(60) or c == UInt8(61) or c == UInt8(62)
        or c == UInt8(63) or c == UInt8(64) or c == UInt8(91) or c == UInt8(92)
        or c == UInt8(93) or c == UInt8(94) or c == UInt8(95) or c == UInt8(96)
        or c == UInt8(123) or c == UInt8(124) or c == UInt8(125) or c == UInt8(126)
    )


def is_alnum(c: UInt8) -> Bool:
    return (
        (c >= UInt8(48) and c <= UInt8(57))
        or (c >= UInt8(65) and c <= UInt8(90))
        or (c >= UInt8(97) and c <= UInt8(122))
    )


def is_alpha(c: UInt8) -> Bool:
    return (
        (c >= UInt8(65) and c <= UInt8(90))
        or (c >= UInt8(97) and c <= UInt8(122))
    )


def put_codepoint(mut writer: Writer, cp: Int):
    if cp == 38:
        writer.literal("&amp;")
    elif cp == 60:
        writer.literal("&lt;")
    elif cp == 62:
        writer.literal("&gt;")
    elif cp == 34:
        writer.literal("&quot;")
    elif cp <= 0x7F:
        writer.byte(UInt8(cp))
    elif cp <= 0x7FF:
        writer.byte(UInt8(0xC0 | (cp >> 6)))
        writer.byte(UInt8(0x80 | (cp & 0x3F)))
    elif cp <= 0xFFFF:
        writer.byte(UInt8(0xE0 | (cp >> 12)))
        writer.byte(UInt8(0x80 | ((cp >> 6) & 0x3F)))
        writer.byte(UInt8(0x80 | (cp & 0x3F)))
    else:
        writer.byte(UInt8(0xF0 | (cp >> 18)))
        writer.byte(UInt8(0x80 | ((cp >> 12) & 0x3F)))
        writer.byte(UInt8(0x80 | ((cp >> 6) & 0x3F)))
        writer.byte(UInt8(0x80 | (cp & 0x3F)))


def render_entity(mut writer: Writer, src: BPtr, start: Int, end: Int) -> Int:
    var semi = start + 1
    while semi < end and semi - start <= 32 and src[semi] != UInt8(59):
        semi += 1
    if semi >= end or src[semi] != UInt8(59):
        return start
    if ascii_equal(src, start + 1, semi, "amp"):
        writer.literal("&amp;")
    elif ascii_equal(src, start + 1, semi, "lt"):
        writer.literal("&lt;")
    elif ascii_equal(src, start + 1, semi, "gt"):
        writer.literal("&gt;")
    elif ascii_equal(src, start + 1, semi, "quot"):
        writer.literal("&quot;")
    elif ascii_equal(src, start + 1, semi, "apos"):
        writer.byte(UInt8(39))
    elif ascii_equal(src, start + 1, semi, "copy"):
        put_codepoint(writer, 0xA9)
    elif ascii_equal(src, start + 1, semi, "reg"):
        put_codepoint(writer, 0xAE)
    elif ascii_equal(src, start + 1, semi, "nbsp"):
        put_codepoint(writer, 0xA0)
    elif start + 2 < semi and src[start + 1] == UInt8(35):
        var i = start + 2
        var base = 10
        if i < semi and (src[i] == UInt8(120) or src[i] == UInt8(88)):
            base = 16
            i += 1
        var cp = 0
        var valid = i < semi
        while i < semi:
            var digit: Int
            if src[i] >= UInt8(48) and src[i] <= UInt8(57):
                digit = Int(src[i] - UInt8(48))
            elif base == 16 and src[i] >= UInt8(65) and src[i] <= UInt8(70):
                digit = Int(src[i] - UInt8(65)) + 10
            elif base == 16 and src[i] >= UInt8(97) and src[i] <= UInt8(102):
                digit = Int(src[i] - UInt8(97)) + 10
            else:
                valid = False
                break
            cp = cp * base + digit
            i += 1
        if not valid:
            return start
        # HTML numeric references outside the Unicode scalar-value range use
        # U+FFFD. In particular, never encode UTF-16 surrogates as UTF-8.
        if cp <= 0 or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF):
            cp = 0xFFFD
        put_codepoint(writer, cp)
    else:
        return start
    return semi + 1


def find_bytes(
    src: BPtr, start: Int, end: Int, marker: UInt8, count: Int
) -> Int:
    var i = start
    while i + count <= end:
        var matched = True
        for j in range(count):
            if src[i + j] != marker:
                matched = False
        if matched:
            return i
        i += 1
    return -1


def is_safe_url(src: BPtr, start: Int, end: Int) -> Bool:
    var s = trim_left(src, start, end)
    var colon = -1
    var slash = end
    for i in range(s, end):
        if src[i] == UInt8(47) and slash == end:
            slash = i
        if src[i] == UInt8(58):
            colon = i
            break
    if colon < 0 or colon > slash:
        return True
    return (
        ascii_equal(src, s, colon + 1, "http:")
        or ascii_equal(src, s, colon + 1, "https:")
        or ascii_equal(src, s, colon + 1, "mailto:")
        or ascii_equal(src, s, colon + 1, "tel:")
        or ascii_equal(src, s, colon + 1, "ftp:")
        or ascii_equal(src, s, colon + 1, "ftps:")
        or ascii_equal(src, s, colon + 1, "irc:")
        or ascii_equal(src, s, colon + 1, "ircs:")
        or starts_with(src, s, end, "data:image/gif;")
        or starts_with(src, s, end, "data:image/png;")
        or starts_with(src, s, end, "data:image/jpeg;")
        or starts_with(src, s, end, "data:image/webp;")
    )


def render_url(mut writer: Writer, src: BPtr, start: Int, end: Int):
    if not is_safe_url(src, start, end):
        writer.literal("#harmful-link")
        return
    for i in range(start, end):
        if src[i] == UInt8(32):
            writer.literal("%20")
        else:
            put_escaped(writer, src[i])


def find_closing_bracket(src: BPtr, start: Int, end: Int) -> Int:
    var depth = 0
    var i = start
    while i < end:
        if src[i] == UInt8(92):
            i += 2
            continue
        if src[i] == UInt8(91):
            depth += 1
        elif src[i] == UInt8(93):
            if depth == 0:
                return i
            depth -= 1
        i += 1
    return -1


def render_inline(
    mut writer: Writer,
    src: BPtr,
    start: Int,
    end: Int,
    escape_html: Bool,
    hard_wrap: Bool,
    strike: Bool,
    plain: Bool = False,
):
    var i = start
    while i < end:
        var c = src[i]

        if plain and (
            c == UInt8(42) or c == UInt8(95) or c == UInt8(126) or c == UInt8(96)
        ):
            i += 1
            continue

        if plain and c == UInt8(60):
            var plain_close = find_bytes(src, i + 1, end, UInt8(62), 1)
            if plain_close >= 0:
                i = plain_close + 1
                continue

        if c == UInt8(92) and i + 1 < end:
            if src[i + 1] == UInt8(10):
                if plain:
                    writer.byte(UInt8(10))
                else:
                    writer.literal("<br />\n")
                i += 2
                continue
            if is_punctuation(src[i + 1]):
                put_escaped(writer, src[i + 1])
                i += 2
                continue

        if not plain and c == UInt8(96):
            var ticks = 1
            while i + ticks < end and src[i + ticks] == UInt8(96):
                ticks += 1
            var close = find_bytes(src, i + ticks, end, UInt8(96), ticks)
            if close >= 0:
                var a = i + ticks
                var b = close
                if b - a >= 2 and src[a] == UInt8(32) and src[b - 1] == UInt8(32):
                    a += 1
                    b -= 1
                writer.literal("<code>")
                for j in range(a, b):
                    put_escaped(writer, UInt8(32) if src[j] == UInt8(10) else src[j])
                writer.literal("</code>")
                i = close + ticks
                continue

        var image = False
        var label_start = i + 1
        if not plain and c == UInt8(33) and i + 1 < end and src[i + 1] == UInt8(91):
            image = True
            label_start = i + 2
        if not plain and (c == UInt8(91) or image):
            var close_label = find_closing_bracket(src, label_start, end)
            if close_label >= 0 and close_label + 1 < end and src[close_label + 1] == UInt8(40):
                var close_dest = close_label + 2
                var quote = UInt8(0)
                var parens = 0
                while close_dest < end:
                    if quote != UInt8(0):
                        if src[close_dest] == quote:
                            quote = UInt8(0)
                    elif src[close_dest] == UInt8(34) or src[close_dest] == UInt8(39):
                        quote = src[close_dest]
                    elif src[close_dest] == UInt8(40):
                        parens += 1
                    elif src[close_dest] == UInt8(41):
                        if parens == 0:
                            break
                        parens -= 1
                    close_dest += 1
                if close_dest < end:
                    var ds = trim_left(src, close_label + 2, close_dest)
                    var de = trim_right(src, ds, close_dest)
                    if ds < de and src[ds] == UInt8(60) and src[de - 1] == UInt8(62):
                        ds += 1
                        de -= 1
                    var title_start = -1
                    var title_end = -1
                    var k = ds
                    while k < de:
                        if src[k] == UInt8(32) or src[k] == UInt8(9):
                            var t = trim_left(src, k, de)
                            if t < de and (src[t] == UInt8(34) or src[t] == UInt8(39)):
                                var q = src[t]
                                if de > t + 1 and src[de - 1] == q:
                                    title_start = t + 1
                                    title_end = de - 1
                                    de = trim_right(src, ds, k)
                            break
                        k += 1
                    if image:
                        writer.literal("<img src=\"")
                        render_url(writer, src, ds, de)
                        writer.literal("\" alt=\"")
                        render_inline(writer, src, label_start, close_label, True, False, strike, True)
                        writer.literal("\"")
                    else:
                        writer.literal("<a href=\"")
                        render_url(writer, src, ds, de)
                        writer.literal("\"")
                    if title_start >= 0:
                        writer.literal(" title=\"")
                        render_escaped(writer, src, title_start, title_end)
                        writer.literal("\"")
                    if image:
                        writer.literal(" />")
                    else:
                        writer.literal(">")
                        render_inline(
                            writer, src, label_start, close_label,
                            escape_html, hard_wrap, strike
                        )
                        writer.literal("</a>")
                    i = close_dest + 1
                    continue

        if not plain and c == UInt8(60):
            var close = find_bytes(src, i + 1, end, UInt8(62), 1)
            if close >= 0:
                var at = -1
                var colon = -1
                for j in range(i + 1, close):
                    if src[j] == UInt8(64):
                        at = j
                    if src[j] == UInt8(58) and colon < 0:
                        colon = j
                if colon > i + 1:
                    writer.literal("<a href=\"")
                    render_url(writer, src, i + 1, close)
                    writer.literal("\">")
                    render_escaped(writer, src, i + 1, close)
                    writer.literal("</a>")
                    i = close + 1
                    continue
                if at > i + 1 and at < close - 1:
                    writer.literal("<a href=\"mailto:")
                    render_escaped(writer, src, i + 1, close)
                    writer.literal("\">")
                    render_escaped(writer, src, i + 1, close)
                    writer.literal("</a>")
                    i = close + 1
                    continue
                var tag_pos = i + 1
                if tag_pos < close and src[tag_pos] == UInt8(47):
                    tag_pos += 1
                var valid_html = tag_pos < close and (
                    is_alpha(src[tag_pos]) or src[tag_pos] == UInt8(33)
                    or src[tag_pos] == UInt8(63)
                )
                if not escape_html and valid_html:
                    writer.source(src, i, close + 1)
                    i = close + 1
                    continue

        if not plain and c == UInt8(95) and i > start and is_alnum(src[i - 1]):
            var underscores = 1
            while i + underscores < end and src[i + underscores] == c and underscores < 3:
                underscores += 1
            writer.source(src, i, i + underscores)
            i += underscores
            continue

        if not plain and (c == UInt8(42) or c == UInt8(95)):
            var run = 1
            while i + run < end and src[i + run] == c and run < 3:
                run += 1
            var close = find_bytes(src, i + run, end, c, run)
            if close > i + run:
                if run == 3:
                    writer.literal("<em><strong>")
                elif run == 2:
                    writer.literal("<strong>")
                else:
                    writer.literal("<em>")
                render_inline(
                    writer, src, i + run, close,
                    escape_html, hard_wrap, strike
                )
                if run == 3:
                    writer.literal("</strong></em>")
                elif run == 2:
                    writer.literal("</strong>")
                else:
                    writer.literal("</em>")
                i = close + run
                continue

        if not plain and strike and c == UInt8(126) and i + 1 < end and src[i + 1] == UInt8(126):
            var close = find_bytes(src, i + 2, end, UInt8(126), 2)
            if close > i + 2:
                writer.literal("<del>")
                render_inline(
                    writer, src, i + 2, close,
                    escape_html, hard_wrap, strike
                )
                writer.literal("</del>")
                i = close + 2
                continue

        if c == UInt8(32):
            var spaces = 1
            while i + spaces < end and src[i + spaces] == UInt8(32):
                spaces += 1
            if i + spaces < end and src[i + spaces] == UInt8(10):
                if plain:
                    writer.byte(UInt8(10))
                elif spaces >= 2 or hard_wrap:
                    writer.literal("<br />\n")
                else:
                    writer.byte(UInt8(10))
                i += spaces + 1
                continue

        if c == UInt8(10):
            if plain:
                writer.byte(c)
            elif hard_wrap:
                writer.literal("<br />\n")
            else:
                writer.byte(c)
            i += 1
            continue

        if c == UInt8(38) and not escape_html:
            var after_entity = render_entity(writer, src, i, end)
            if after_entity > i:
                i = after_entity
                continue

        if c == UInt8(38) or c == UInt8(60) or c == UInt8(62) or c == UInt8(34):
            put_escaped(writer, c)
        else:
            writer.byte(c)
        i += 1


def heading_level(src: BPtr, start: Int, end: Int) -> Int:
    var i = start
    while i < end and src[i] == UInt8(32) and i - start < 3:
        i += 1
    var level = 0
    while i < end and src[i] == UInt8(35) and level < 7:
        level += 1
        i += 1
    if level < 1 or level > 6:
        return 0
    if i < end and src[i] != UInt8(32) and src[i] != UInt8(9):
        return 0
    return level


def heading_content_start(src: BPtr, start: Int, end: Int) -> Int:
    var i = start
    while i < end and src[i] == UInt8(32):
        i += 1
    while i < end and src[i] == UInt8(35):
        i += 1
    return trim_left(src, i, end)


def heading_content_end(src: BPtr, start: Int, end: Int) -> Int:
    var i = trim_right(src, start, end)
    var hashes = i
    while hashes > start and src[hashes - 1] == UInt8(35):
        hashes -= 1
    if hashes < i and hashes > start and src[hashes - 1] == UInt8(32):
        return trim_right(src, start, hashes)
    return i


def thematic_break(src: BPtr, start: Int, end: Int) -> Bool:
    var i = trim_left(src, start, end)
    if i >= end:
        return False
    var marker = src[i]
    if marker != UInt8(42) and marker != UInt8(45) and marker != UInt8(95):
        return False
    var count = 0
    while i < end:
        if src[i] == marker:
            count += 1
        elif src[i] != UInt8(32) and src[i] != UInt8(9):
            return False
        i += 1
    return count >= 3


def setext_level(src: BPtr, start: Int, end: Int) -> Int:
    var a = trim_left(src, start, end)
    var b = trim_right(src, a, end)
    if a >= b:
        return 0
    var marker = src[a]
    if marker != UInt8(61) and marker != UInt8(45):
        return 0
    for i in range(a, b):
        if src[i] != marker:
            return 0
    return 1 if marker == UInt8(61) else 2


def fence_size(src: BPtr, start: Int, end: Int) -> Int:
    var i = start
    while i < end and src[i] == UInt8(32) and i - start < 3:
        i += 1
    if i >= end or (src[i] != UInt8(96) and src[i] != UInt8(126)):
        return 0
    var marker = src[i]
    var count = 0
    while i < end and src[i] == marker:
        count += 1
        i += 1
    return count if count >= 3 else 0


def fence_start(src: BPtr, start: Int, end: Int) -> Int:
    var i = start
    while i < end and src[i] == UInt8(32):
        i += 1
    while i < end and (src[i] == UInt8(96) or src[i] == UInt8(126)):
        i += 1
    return trim_left(src, i, end)


def list_kind(src: BPtr, start: Int, end: Int) -> Int:
    var i = start
    while i < end and src[i] == UInt8(32) and i - start < 3:
        i += 1
    if i + 1 < end and (
        src[i] == UInt8(45) or src[i] == UInt8(43) or src[i] == UInt8(42)
    ) and (src[i + 1] == UInt8(32) or src[i + 1] == UInt8(9)):
        return 1
    var digits = 0
    while i < end and src[i] >= UInt8(48) and src[i] <= UInt8(57) and digits < 9:
        digits += 1
        i += 1
    if digits > 0 and i + 1 < end and (
        src[i] == UInt8(46) or src[i] == UInt8(41)
    ) and (src[i + 1] == UInt8(32) or src[i + 1] == UInt8(9)):
        return 2
    return 0


def list_start_number(src: BPtr, start: Int, end: Int) -> Int:
    var i = trim_left(src, start, end)
    var value = 0
    while i < end and src[i] >= UInt8(48) and src[i] <= UInt8(57):
        value = value * 10 + Int(src[i] - UInt8(48))
        i += 1
    return value


def list_content_start(src: BPtr, start: Int, end: Int) -> Int:
    var i = trim_left(src, start, end)
    if src[i] == UInt8(45) or src[i] == UInt8(43) or src[i] == UInt8(42):
        i += 1
    else:
        while i < end and src[i] >= UInt8(48) and src[i] <= UInt8(57):
            i += 1
        i += 1
    return trim_left(src, i, end)


def quote_content_start(src: BPtr, start: Int, end: Int) -> Int:
    var i = start
    while i < end and src[i] == UInt8(32) and i - start < 3:
        i += 1
    if i < end and src[i] == UInt8(62):
        i += 1
        if i < end and src[i] == UInt8(32):
            i += 1
        return i
    return -1


def html_block_start(src: BPtr, start: Int, end: Int) -> Bool:
    var i = trim_left(src, start, end)
    for j in range(i, end):
        if src[j] == UInt8(64):
            return False
    return (
        starts_with_fold(src, i, end, "<address")
        or starts_with_fold(src, i, end, "<article")
        or starts_with_fold(src, i, end, "<aside")
        or starts_with_fold(src, i, end, "<base")
        or starts_with_fold(src, i, end, "<blockquote")
        or starts_with_fold(src, i, end, "<body")
        or starts_with_fold(src, i, end, "<caption")
        or starts_with_fold(src, i, end, "<center")
        or starts_with_fold(src, i, end, "<col")
        or starts_with_fold(src, i, end, "<dd")
        or starts_with_fold(src, i, end, "<details")
        or starts_with_fold(src, i, end, "<dialog")
        or starts_with_fold(src, i, end, "<dir")
        or starts_with_fold(src, i, end, "<div")
        or starts_with_fold(src, i, end, "<dl")
        or starts_with_fold(src, i, end, "<dt")
        or starts_with_fold(src, i, end, "<fieldset")
        or starts_with_fold(src, i, end, "<figcaption")
        or starts_with_fold(src, i, end, "<figure")
        or starts_with_fold(src, i, end, "<footer")
        or starts_with_fold(src, i, end, "<form")
        or starts_with_fold(src, i, end, "<h1")
        or starts_with_fold(src, i, end, "<h2")
        or starts_with_fold(src, i, end, "<h3")
        or starts_with_fold(src, i, end, "<h4")
        or starts_with_fold(src, i, end, "<h5")
        or starts_with_fold(src, i, end, "<h6")
        or starts_with_fold(src, i, end, "<header")
        or starts_with_fold(src, i, end, "<hr")
        or starts_with_fold(src, i, end, "<html")
        or starts_with_fold(src, i, end, "<iframe")
        or starts_with_fold(src, i, end, "<legend")
        or starts_with_fold(src, i, end, "<li")
        or starts_with_fold(src, i, end, "<link")
        or starts_with_fold(src, i, end, "<main")
        or starts_with_fold(src, i, end, "<menu")
        or starts_with_fold(src, i, end, "<nav")
        or starts_with_fold(src, i, end, "<ol")
        or starts_with_fold(src, i, end, "<p")
        or starts_with_fold(src, i, end, "<pre")
        or starts_with_fold(src, i, end, "<script")
        or starts_with_fold(src, i, end, "<section")
        or starts_with_fold(src, i, end, "<style")
        or starts_with_fold(src, i, end, "<summary")
        or starts_with_fold(src, i, end, "<table")
        or starts_with_fold(src, i, end, "<tbody")
        or starts_with_fold(src, i, end, "<td")
        or starts_with_fold(src, i, end, "<tfoot")
        or starts_with_fold(src, i, end, "<th")
        or starts_with_fold(src, i, end, "<thead")
        or starts_with_fold(src, i, end, "<title")
        or starts_with_fold(src, i, end, "<tr")
        or starts_with_fold(src, i, end, "<track")
        or starts_with_fold(src, i, end, "<ul")
        or starts_with_fold(src, i, end, "<!--")
        or starts_with_fold(src, i, end, "<?")
        or starts_with_fold(src, i, end, "<![CDATA[")
    )


def table_row_bounds(src: BPtr, start: Int, end: Int) -> Tuple[Int, Int]:
    var a = trim_left(src, start, end)
    var b = trim_right(src, a, end)
    if a < b and src[a] == UInt8(124):
        a += 1
    if b > a and src[b - 1] == UInt8(124) and (
        b < 2 or src[b - 2] != UInt8(92)
    ):
        b -= 1
    return Tuple(a, b)


def table_cell_count(src: BPtr, start: Int, end: Int) -> Int:
    var bounds = table_row_bounds(src, start, end)
    var a = bounds[0]
    var b = bounds[1]
    if a >= b:
        return 0
    var count = 1
    for i in range(a, b):
        if src[i] == UInt8(124) and (i == a or src[i - 1] != UInt8(92)):
            count += 1
    return count


def table_cell_start(src: BPtr, start: Int, end: Int, index: Int) -> Int:
    var bounds = table_row_bounds(src, start, end)
    var a = bounds[0]
    var b = bounds[1]
    var current = 0
    var i = a
    while i < b and current < index:
        if src[i] == UInt8(124) and (i == a or src[i - 1] != UInt8(92)):
            current += 1
            a = i + 1
        i += 1
    return trim_left(src, a, b)


def table_cell_end(src: BPtr, start: Int, end: Int, index: Int) -> Int:
    var a = table_cell_start(src, start, end, index)
    var bounds = table_row_bounds(src, start, end)
    var b = bounds[1]
    var i = a
    while i < b:
        if src[i] == UInt8(124) and (i == a or src[i - 1] != UInt8(92)):
            return trim_right(src, a, i)
        i += 1
    return trim_right(src, a, b)


def table_alignment(src: BPtr, start: Int, end: Int, index: Int) -> Int:
    var a = table_cell_start(src, start, end, index)
    var b = table_cell_end(src, start, end, index)
    var left = a < b and src[a] == UInt8(58)
    var right = a < b and src[b - 1] == UInt8(58)
    if left:
        a += 1
    if right:
        b -= 1
    if b - a < 3:
        return -1
    for i in range(a, b):
        if src[i] != UInt8(45):
            return -1
    if left and right:
        return 2
    if left:
        return 1
    if right:
        return 3
    return 0


def table_delimiter(src: BPtr, start: Int, end: Int, columns: Int) -> Bool:
    if columns < 1 or table_cell_count(src, start, end) != columns:
        return False
    for i in range(columns):
        if table_alignment(src, start, end, i) < 0:
            return False
    return True


def table_has_pipe(src: BPtr, start: Int, end: Int) -> Bool:
    for i in range(start, end):
        if src[i] == UInt8(124) and (i == start or src[i - 1] != UInt8(92)):
            return True
    return False


def table_style(mut writer: Writer, alignment: Int):
    if alignment == 1:
        writer.literal(" style=\"text-align:left\"")
    elif alignment == 2:
        writer.literal(" style=\"text-align:center\"")
    elif alignment == 3:
        writer.literal(" style=\"text-align:right\"")


def render_table_row(
    mut writer: Writer,
    src: BPtr,
    start: Int,
    end: Int,
    delimiter_start: Int,
    delimiter_end: Int,
    columns: Int,
    header: Bool,
    escape_html: Bool,
    hard_wrap: Bool,
    strike: Bool,
):
    writer.literal("<tr>\n")
    for i in range(columns):
        writer.literal("  <th" if header else "  <td")
        table_style(
            writer,
            table_alignment(src, delimiter_start, delimiter_end, i),
        )
        writer.literal(">")
        if i < table_cell_count(src, start, end):
            render_inline(
                writer,
                src,
                table_cell_start(src, start, end, i),
                table_cell_end(src, start, end, i),
                escape_html,
                hard_wrap,
                strike,
            )
        writer.literal("</th>\n" if header else "</td>\n")
    writer.literal("</tr>\n")


def starts_block(src: BPtr, n: Int, start: Int) -> Bool:
    var end = line_end(src, n, start)
    if is_blank(src, start, end):
        return True
    if heading_level(src, start, end) > 0 or thematic_break(src, start, end):
        return True
    if fence_size(src, start, end) > 0 or list_kind(src, start, end) > 0:
        return True
    if quote_content_start(src, start, end) >= 0:
        return True
    return False


def render_document(
    mut writer: Writer,
    src: BPtr,
    n: Int,
    escape_html: Bool,
    hard_wrap: Bool,
    strike: Bool,
    tables: Bool,
):
    var pos = 0
    while pos < n:
        var end = line_end(src, n, pos)
        if is_blank(src, pos, end):
            pos = next_line(src, n, pos)
            continue

        var level = heading_level(src, pos, end)
        if level > 0:
            var a = heading_content_start(src, pos, end)
            var b = heading_content_end(src, a, end)
            writer.literal("<h")
            writer.byte(UInt8(48 + level))
            writer.literal(">")
            render_inline(writer, src, a, b, escape_html, hard_wrap, strike)
            writer.literal("</h")
            writer.byte(UInt8(48 + level))
            writer.literal(">\n")
            pos = next_line(src, n, pos)
            continue

        if thematic_break(src, pos, end):
            writer.literal("<hr />\n")
            pos = next_line(src, n, pos)
            continue

        if not escape_html and html_block_start(src, pos, end):
            while pos < n:
                end = line_end(src, n, pos)
                if is_blank(src, pos, end):
                    break
                writer.source(src, pos, end)
                writer.byte(UInt8(10))
                pos = next_line(src, n, pos)
            writer.byte(UInt8(10))
            continue

        var fsize = fence_size(src, pos, end)
        if fsize > 0:
            var marker_pos = trim_left(src, pos, end)
            var marker = src[marker_pos]
            var info = fence_start(src, pos, end)
            writer.literal("<pre><code")
            if info < end:
                writer.literal(" class=\"language-")
                var info_end = info
                while info_end < end and src[info_end] != UInt8(32) and src[info_end] != UInt8(9):
                    info_end += 1
                render_escaped(writer, src, info, info_end)
                writer.literal("\"")
            writer.literal(">")
            pos = next_line(src, n, pos)
            while pos < n:
                end = line_end(src, n, pos)
                var close_start = trim_left(src, pos, end)
                var count = 0
                while close_start + count < end and src[close_start + count] == marker:
                    count += 1
                if count >= fsize and trim_left(src, close_start + count, end) == end:
                    pos = next_line(src, n, pos)
                    break
                render_escaped(writer, src, pos, end)
                if next_line(src, n, pos) > end:
                    writer.byte(UInt8(10))
                pos = next_line(src, n, pos)
            writer.literal("</code></pre>\n")
            continue

        var qstart = quote_content_start(src, pos, end)
        if qstart >= 0:
            writer.literal("<blockquote>\n<p>")
            var first = True
            while pos < n:
                end = line_end(src, n, pos)
                qstart = quote_content_start(src, pos, end)
                if qstart < 0:
                    break
                if not first:
                    writer.byte(UInt8(10))
                render_inline(writer, src, qstart, end, escape_html, hard_wrap, strike)
                first = False
                pos = next_line(src, n, pos)
            writer.literal("</p>\n</blockquote>\n")
            continue

        var kind = list_kind(src, pos, end)
        if kind > 0:
            var marker_byte = src[trim_left(src, pos, end)]
            if kind == 1:
                writer.literal("<ul>\n")
            else:
                var number = list_start_number(src, pos, end)
                if number != 1:
                    writer.literal("<ol start=\"")
                    var hundreds = number // 100
                    var tens = (number // 10) % 10
                    if hundreds > 0:
                        writer.byte(UInt8(48 + hundreds))
                    if hundreds > 0 or tens > 0:
                        writer.byte(UInt8(48 + tens))
                    writer.byte(UInt8(48 + number % 10))
                    writer.literal("\">\n")
                else:
                    writer.literal("<ol>\n")
            while pos < n:
                end = line_end(src, n, pos)
                if list_kind(src, pos, end) != kind:
                    break
                if kind == 1 and src[trim_left(src, pos, end)] != marker_byte:
                    break
                writer.literal("<li>")
                var content = list_content_start(src, pos, end)
                render_inline(writer, src, content, end, escape_html, hard_wrap, strike)
                pos = next_line(src, n, pos)
                while pos < n:
                    end = line_end(src, n, pos)
                    if is_blank(src, pos, end) or list_kind(src, pos, end) > 0:
                        break
                    var continuation = trim_left(src, pos, end)
                    if continuation == pos:
                        break
                    writer.byte(UInt8(10))
                    render_inline(
                        writer, src, continuation, end,
                        escape_html, hard_wrap, strike
                    )
                    pos = next_line(src, n, pos)
                writer.literal("</li>\n")
            writer.literal("</ul>\n" if kind == 1 else "</ol>\n")
            continue

        if end - pos >= 4 and (
            src[pos] == UInt8(32) and src[pos + 1] == UInt8(32)
            and src[pos + 2] == UInt8(32) and src[pos + 3] == UInt8(32)
        ):
            writer.literal("<pre><code>")
            var first = True
            while pos < n:
                end = line_end(src, n, pos)
                if end - pos < 4 or not (
                    src[pos] == UInt8(32) and src[pos + 1] == UInt8(32)
                    and src[pos + 2] == UInt8(32) and src[pos + 3] == UInt8(32)
                ):
                    break
                if not first:
                    writer.byte(UInt8(10))
                render_escaped(writer, src, pos + 4, end)
                first = False
                pos = next_line(src, n, pos)
            writer.literal("</code></pre>\n")
            continue

        var following = next_line(src, n, pos)
        if following < n:
            var following_end = line_end(src, n, following)
            var columns = table_cell_count(src, pos, end)
            if tables and (
                table_has_pipe(src, pos, end)
                or table_has_pipe(src, following, following_end)
            ) and table_delimiter(
                src, following, following_end, columns
            ):
                writer.literal("<table>\n<thead>\n")
                render_table_row(
                    writer, src, pos, end, following, following_end, columns,
                    True, escape_html, hard_wrap, strike
                )
                writer.literal("</thead>\n")
                pos = next_line(src, n, following)
                writer.literal("<tbody>\n")
                while pos < n:
                    end = line_end(src, n, pos)
                    if is_blank(src, pos, end) or table_cell_count(src, pos, end) < 1:
                        break
                    render_table_row(
                        writer, src, pos, end, following, following_end, columns,
                        False, escape_html, hard_wrap, strike
                    )
                    pos = next_line(src, n, pos)
                writer.literal("</tbody>\n")
                writer.literal("</table>\n")
                continue
            level = setext_level(src, following, following_end)
            if level > 0:
                writer.literal("<h")
                writer.byte(UInt8(48 + level))
                writer.literal(">")
                render_inline(
                    writer, src, trim_left(src, pos, end), trim_right(src, pos, end),
                    escape_html, hard_wrap, strike
                )
                writer.literal("</h")
                writer.byte(UInt8(48 + level))
                writer.literal(">\n")
                pos = next_line(src, n, following)
                continue

        writer.literal("<p>")
        var paragraph_start = pos
        var paragraph_end = end
        pos = next_line(src, n, pos)
        while pos < n and not starts_block(src, n, pos):
            paragraph_end = line_end(src, n, pos)
            pos = next_line(src, n, pos)
        render_inline(
            writer, src, trim_left(src, paragraph_start, paragraph_end),
            trim_right(src, paragraph_start, paragraph_end),
            escape_html, hard_wrap, strike
        )
        writer.literal("</p>\n")


@export("mmt_render_html")
def mmt_render_html(
    src_addr: Int,
    n: Int,
    dst_addr: Int,
    capacity: Int,
    escape_html: Int,
    hard_wrap: Int,
    features: Int,
) abi("C") -> Int:
    # The C ABI cannot express pointer validity. Reject malformed calls before
    # constructing Mojo's non-nullable UnsafePointer values.
    if n < 0 or capacity <= 0:
        return -1
    if n == 0:
        return 0
    if src_addr <= 0 or dst_addr <= 0:
        return -1
    var src = BPtr(unsafe_from_address=src_addr)
    var dst = BPtr(unsafe_from_address=dst_addr)
    var writer = Writer(dst, capacity)
    render_document(
        writer, src, n, escape_html != 0, hard_wrap != 0,
        (features & 1) != 0, (features & 2) != 0
    )
    return writer.position
