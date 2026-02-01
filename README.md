# Deprecated / *Moved to codeberg*

`zdap` is deprecated.
  
However, `plz`, a similar but more powerful alternative for zig 0.16.0, is available on [Codeberg](https://codeberg.org/GasInfinity/plz)

# zdap

![Zig support](https://img.shields.io/badge/Zig-0.15.x-color?logo=zig&color=%23f3ab20)

Opinionated fork from the awesome [flags](https://github.com/joegm/flags) library by @joegm, its main purpose is to serve as the argument parser library for [zitrus](https://github.com/GasInfinity/zitrus) tools.
     
It's pretty much the same except that I change some special field names `command, positional, trailing -> @"-", @"--", @"..."`, add some restrictions and support for optional commands based on them.
  
---

An effortless command-line argument parser for Zig.
  
Simply declare a struct and flags will inspect the fields at compile-time to determine how arguments are parsed:

```zig
pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    defer _ = debug_allocator.deinit();
    const gpa = debug_allocator.allocator();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    const cli = zdap.parse(
        args,
        "my-program",
        struct {
            username: []const u8,
        },
        .{},
    );

    std.debug.print("Hello, {s}!\n", .{cli.username});
}

const std = @import("std");
const zdap = @import("zdap");
```

## Features

- Zero allocations.
- Cross platform.
- Single-function, declarative API.
- Multi-level subcommands.
- Automatic help message generation at comptime.
- Customisable terminal coloring.

## Getting Started

zdap is intended to be used with the latest Zig release. If zdap is out of date, please open an issue.
To import zdap to your project, run the following command:

```
zig fetch --save git+https://github.com/GasInfinity/zdap
```

Then set up the dependency in your `build.zig`:

```zig
    const flags_dep = b.dependency("zdap", .{
        .target = target,
        .optimize = optimize,
    })

    exe.root_module.addImport("zdap", flags_dep.module("zdap"));
```

See the [examples](examples/) for basic usage.
