const builtin = @import("builtin");

extern fn oayao_swift_bootstrap() void;

pub fn bootstrap() void {
    if (builtin.os.tag == .ios) {
        oayao_swift_bootstrap();
    }
}
