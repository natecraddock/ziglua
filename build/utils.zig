const std = @import("std");

const Build = std.Build;
const Step = std.Build.Step;

const RunOutput = struct {
    run: *Step.Run,
    output: Build.LazyPath,
};

pub fn applyPatchToFile(
    b: *Build,
    target: Build.ResolvedTarget,
    file: Build.LazyPath,
    patch_file: Build.LazyPath,
    output_file: []const u8,
) RunOutput {
    const patch = b.addExecutable(.{
        .name = "patch",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/patch.zig"),
            .target = target,
        }),
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

pub fn concatenateFiles(
    b: *Build,
    target: Build.ResolvedTarget,
    file1: Build.LazyPath,
    file2: Build.LazyPath,
    output_file: []const u8,
) RunOutput {
    const concatenate = b.addExecutable(.{
        .name = "concat",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/header_gen.zig"),
            .target = target,
        }),
    });

    const concatenate_run = b.addRunArtifact(concatenate);
    concatenate_run.addFileArg(file1);
    concatenate_run.addFileArg(file2);

    const out = concatenate_run.addOutputFileArg(output_file);

    return .{
        .run = concatenate_run,
        .output = out,
    };
}
