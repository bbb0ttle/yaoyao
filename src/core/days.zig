//! Day-counter text formatting: "123.4567890123 DAYS".

/// Format a day count as "<int>.<10-digit fraction> DAYS" into `buf`,
/// followed by a NUL when room allows. Returns the text length excluding
/// the NUL. The fraction is truncated, not rounded. Buffer overruns are
/// silently clipped — callers size the buffer for the longest expected
/// input.
pub fn format_days(buf: []u8, diff_days: f64) usize {
    var len: usize = 0;
    const int_part: u64 = @intFromFloat(@floor(diff_days));
    const frac: f64 = diff_days - @floor(diff_days);

    format_uint(buf, &len, int_part);

    if (len < buf.len) {
        buf[len] = '.';
        len += 1;
    }

    var f = frac;
    var digits: usize = 0;
    while (digits < 10) : (digits += 1) {
        f *= 10.0;
        const d: u8 = @intFromFloat(@floor(f));
        f -= @floor(f);
        if (len < buf.len) {
            buf[len] = '0' + d;
            len += 1;
        }
    }

    const suffix = " DAYS";
    for (suffix) |byte| {
        if (len < buf.len) {
            buf[len] = byte;
            len += 1;
        }
    }

    if (len < buf.len) {
        buf[len] = 0;
    }
    return len;
}

fn format_uint(buf: []u8, len: *usize, n: u64) void {
    if (n == 0) {
        if (len.* < buf.len) {
            buf[len.*] = '0';
            len.* += 1;
        }
        return;
    }
    var tmp: [20]u8 = undefined;
    var tlen: usize = 0;
    var v = n;
    while (v > 0) : (v /= 10) {
        tmp[tlen] = @as(u8, @intCast(v % 10)) + '0';
        tlen += 1;
    }
    var j: usize = tlen;
    while (j > 0) {
        j -= 1;
        if (len.* < buf.len) {
            buf[len.*] = tmp[j];
            len.* += 1;
        }
    }
}
