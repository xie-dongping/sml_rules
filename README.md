Bazel SML Rules
===============

[Bazel](https://bazel.build/) SML rules provide the necessary rules to build and test SML (Standard ML) applications using Bazel.

## Introduction

Bazel SML rules are a set of rules for the Bazel build system that allow you to compile and test SML (Standard ML) code. The `sml` files are concatenated together and built by the [MLton compiler](https://github.com/MLton/mlton).

Currently, the rules include `sml_library`, `sml_cc_src`, `sml_binary`, and `sml_test`:

* `sml_library`: This rule takes a list of `.sml` files as input and produces an SML library as output. The library can be used as a dependency in other rules.
* `sml_cc_src`: This rule transpiles SML code into C code using the MLton compiler.
* `sml_binary`: This rule creates a binary executable from SML code. It is a thin wrapper of `cc_binary` combined with `sml_cc_src`.
* `sml_test`: This rule is used for running tests written in SML. It is a thin wrapper of `cc_binary` combined with `sml_cc_src`.

Please refer to the source code for exact implementation.

## Limitations

These rules are currently designed to work with the MLton compiler using its C code generation. The `sml` files are concatenated according to the dependencies defined in the build process, but I haven't tested it in large projects, so your mileage may vary.

`MLton` may generate multiple C files from the Standard ML source code. The current default value is set at `20`, as `bazel` requires a static build graph. If it is not enough, error would be thrown and the user has to increase the limit by setting the `max_files` attribute of the rules.

These rules are built and tested for x64 Linux (my own computer). They may not work correctly on other operating systems or architectures.

Error handling and messaging may not be fully refined yet. Use at your own risk.

## Disclaimer

This package is currently in an alpha stage and its usage is at the user's own risk.

Please note that I am developing this project for my own personal needs and for fun. Therefore, I cannot guarantee any specific features or provide any support beyond what I find personally useful. Please do not expect any additional contributions or updates from me.

## Usage

To use these rules (provided that bazel/[bazelisk](https://github.com/bazelbuild/bazelisk/releases) is installed), include the following in your WORKSPACE file:

```python
load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")

git_repository(
    name = "sml_rules",
    remote = "https://github.com/xie-dongping/sml_rules.git",
    branch = "main", # don't specify the `branch`, use `commit` to ensure hermetic build
    # commit = "sha_hash", # please use the `commit` field to pin a certain commit
)

load("@sml_rules//:rules.bzl", "sml_repository")
sml_repository()
```

After downloading the rules, you may load and use the rules.

```python

load("@sml_rules//:sml_rules.bzl", "sml_library", "sml_binary", "sml_test")

sml_library(
    name = "mylib",
    srcs = ["mylib.sml"],
)

sml_binary(
    name = "mybinary",
    srcs = ["main.sml"],
    deps = [":mylib"],
)

sml_test(
    name = "mytest",
    srcs = ["mylib.test.sml"],
    deps = [":mylib"],
)
```

Then you may test your code with `bazel test ...` (to test all available test targets) or `bazel test //:mytest`.


An example is also available in `examples` folder.
