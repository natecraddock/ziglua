const std = @import("std");

const Build = std.Build;
const Step = std.Build.Step;

const PatchFile = struct {
    run: *Step.Run,
    output: Build.LazyPath,
};

pub fn applyPatchToFile(
    b: *Build,
    target: Build.ResolvedTarget,
    file: Build.LazyPath,
    patch_file: Build.LazyPath,
    output_file: []const u8,
) PatchFile {
    const patch = b.addExecutable(.{
        .name = "patch",
        .root_source_file = b.path("build/patch.zig"),
        .target = target,
    });

    const patch_run = b.addRunArtifact(patch);
    patch_run.addFileArg(file);
    patch_run.addFileArg(patch_file);

    const out = patch_run.addOutputFileArg(output_file);

    return .{
        .run = patch_run,
        .output = out,
    };
}
