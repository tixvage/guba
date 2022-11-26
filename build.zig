const std = @import("std");
const freetype = @import("libs/mach-freetype/build.zig");
const SDL = @import("libs/SDL.zig/Sdk.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();
    const sdk = SDL.init(b);
    const exe = b.addExecutable("guba", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addPackage(freetype.pkg);
    exe.addPackage(sdk.getNativePackage("sdl2"));
    freetype.link(b, exe, .{});
    sdk.link(exe, .dynamic);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
