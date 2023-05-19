load(
    "@bazel_tools//tools/build_defs/repo:http.bzl",
    "http_archive"
)

SmlLibraryInfo = provider(fields=["srcs"])

def _sml_library_impl(ctx):
    srcs = ctx.files.srcs
    deps = depset(transitive=[dep[SmlLibraryInfo].srcs for dep in ctx.attr.deps])
    all_srcs = deps.to_list() + srcs
    temp_sml = ctx.actions.declare_file(ctx.label.name + "_temp.sml")
    error_log = ctx.actions.declare_file(ctx.label.name + "_error.log")

    ctx.actions.run(
        inputs = all_srcs,
        outputs = [temp_sml],
        executable = "bash",
        arguments = ["-c", "cat {} > {}".format(" ".join([f.path for f in all_srcs]), temp_sml.path)],
    )
    ctx.actions.run_shell(
        inputs = [temp_sml],
        outputs = [error_log],
        tools = [ctx.executable._mlton],
        command = "set -e;{mlton} -stop tc {src}".format(
            mlton=ctx.executable._mlton.path, src=temp_sml.path),
    )

    return [SmlLibraryInfo(srcs = depset(srcs + all_srcs))]

sml_library = rule(
    implementation = _sml_library_impl,
    attrs = {
        "_mlton": attr.label(default = "@mlton_binary//:mlton_wrapper", executable=True, cfg="exec"),
        "srcs": attr.label_list(allow_files=True),
        "deps": attr.label_list(providers=[SmlLibraryInfo]),
    },
)


def _sml_cc_src_impl(ctx):
    srcs = ctx.files.srcs
    deps = depset(transitive=[dep[SmlLibraryInfo].srcs for dep in ctx.attr.deps])
    all_srcs = deps.to_list() + srcs
    temp_sml = ctx.actions.declare_file(ctx.label.name + "_temp.sml")
    output_c_files = [ctx.actions.declare_file(ctx.label.name + ".{}.c".format(i)) for i in range(ctx.attr.max_files)]

    base_name = temp_sml.path.rsplit('.sml', 1)[0]
    base_path_c = temp_sml.path.rsplit('_temp.sml', 1)[0]  # remove the "_temp.sml" suffix
    ctx.actions.run_shell(
        inputs = all_srcs,
        outputs = [temp_sml] + output_c_files,
        tools = [ctx.executable._mlton,],
        command = """
            set -e
            cat {srcs} > {out_src}
            {mlton} -codegen c -stop g {out_src}
            file_count=0
            for i in $(seq 0 {max_files}); do
                if [ -f {base_name}.$i.c ]; then
                    file_count=$((file_count+1))
                    if [ $i -eq $((max_files-1)) ] && [ -f {base_name}.$((i+1)).c ]; then
                        echo "Error: More than {max_files} C files generated, increase the limit."
                        exit 1
                    fi
                    mv {base_name}.$i.c {base_path_c}.$i.c
                else
                    touch {base_path_c}.$i.c
                fi
            done
            if [ $file_count -eq 0 ]; then
                echo "Error: No C files were generated"
                exit 1
            fi
        """.format(srcs=" ".join([f.path for f in all_srcs]),
                   out_src=temp_sml.path, mlton=ctx.executable._mlton.path,
                   max_files=ctx.attr.max_files,
                   base_path_c=base_path_c, base_name=base_name)
    )

    return [DefaultInfo(files = depset(direct = output_c_files))]

sml_cc_src = rule(
    implementation = _sml_cc_src_impl,
    attrs = {
        "_mlton": attr.label(default="@mlton_binary//:mlton_wrapper", executable=True, cfg="exec"),
        "srcs": attr.label_list(allow_files=True),
        "deps": attr.label_list(providers=[SmlLibraryInfo]),
        "max_files": attr.int(default = 20),
    },
)

def sml_binary(name, srcs, max_files = 20, deps = [], **kwargs):
    sml_cc_name = name + "_sml_cc"

    sml_cc_src(
        name = sml_cc_name,
        srcs = srcs,
        deps = deps,
        max_files = max_files,
    )

    native.cc_binary(
        name = name,
        srcs = [sml_cc_name],
        deps = [
            "@mlton_binary//:mlton_c_deps",
            "@mlton_binary//:libmlton",
            "@mlton_binary//:libgdtoa",
        ],
        **kwargs,
    )

def sml_test(name, srcs, max_files = 20, deps = [], **kwargs):
    sml_cc_name = name + "_sml_cc"

    sml_cc_src(
        name = sml_cc_name,
        srcs = srcs,
        deps = deps,
        max_files = max_files,
    )

    native.cc_test(
        name = name,
        srcs = [sml_cc_name],
        deps = [
            "@mlton_binary//:mlton_c_deps",
            "@mlton_binary//:libmlton",
            "@mlton_binary//:libgdtoa",
        ],
        **kwargs,
    )

def sml_repository(
    mlton_urls = ["https://github.com/MLton/mlton/releases/download/on-20210117-release/mlton-20210117-1.amd64-linux-glibc2.31.tgz"],
    mlton_strip_prefix = "mlton-20210117-1.amd64-linux-glibc2.31",
    mlton_sha256 = "749cb59d6baccd644143709be866105228d2b6dcd40c507a90b89c9b5e0f45d2",
):
    http_archive(
        name = "mlton_binary",
        urls = mlton_urls,
        strip_prefix = mlton_strip_prefix ,
        sha256 = mlton_sha256,
        build_file_content = """
load("@rules_cc//cc:defs.bzl", "cc_import", "cc_library")

cc_import(
    name = "libgdtoa",
    static_library = "lib/mlton/targets/self/libgdtoa-pic.a",
    visibility = ["//visibility:public"],
)

cc_import(
    name = "libmlton",
    static_library = "lib/mlton/targets/self/libmlton-pic.a",
    visibility = ["//visibility:public"],
)

filegroup(
    name = "all_headers",
    srcs = glob([
        "lib/mlton/include/**/*.h",
        "lib/mlton/targets/self/include/**/*.h",
        "lib/mlton/include/platform/**/*.h",
    ]),
)

cc_library(
    name = "mlton_c_deps",
    hdrs = [":all_headers"],
    includes = [
        "lib/mlton/include/",
        "lib/mlton/targets/self/include/",
        "lib/mlton/include/platform/",
    ],
    deps = [
        ":libgdtoa",
        ":libmlton",
    ],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "mlton_files",
    srcs = glob(["**"]),
    visibility = ["//visibility:public"],
)

genrule(
    name = "mlton_gen",
    srcs = [":mlton_files"],
    outs = ["mlton_gen.sh"],
    cmd = \"""
        echo '#!/bin/bash' > $@
        echo 'BINARY=$${BASH_SOURCE[0]}.runfiles/mlton_binary/bin/mlton' >> $@
        echo 'exec "$$BINARY" "$$@"'  >> $@
    \""",
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "mlton_wrapper",
    srcs = ["mlton_gen.sh"],
    data = [
        ":mlton_files",
    ],
    visibility = ["//visibility:public"],
)
""",

    )

