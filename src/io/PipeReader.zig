const bun = @import("root").bun;
const std = @import("std");
const uv = bun.windows.libuv;
const Source = @import("./source.zig").Source;

const ReadState = @import("./pipes.zig").ReadState;
const FileType = @import("./pipes.zig").FileType;

/// Read a blocking pipe without blocking the current thread.
pub fn PosixPipeReader(
    comptime This: type,
    comptime vtable: struct {
        getFd: *const fn (*This) bun.FileDescriptor,
        getBuffer: *const fn (*This) *std.ArrayList(u8),
        getFileType: *const fn (*This) FileType,
        onReadChunk: ?*const fn (*This, chunk: []u8, state: ReadState) void = null,
        registerPoll: ?*const fn (*This) void = null,
        done: *const fn (*This) void,
        close: *const fn (*This) void,
        onError: *const fn (*This, bun.sys.Error) void,
    },
) type {
    return struct {
        pub fn read(this: *This) void {
            const buffer = vtable.getBuffer(this);
            const fd = vtable.getFd(this);

            switch (vtable.getFileType(this)) {
                .nonblocking_pipe => {
                    readPipe(this, buffer, fd, 0, false);
                    return;
                },
                .file => {
                    readFile(this, buffer, fd, 0, false);
                    return;
                },
                .socket => {
                    readSocket(this, buffer, fd, 0, false);
                    return;
                },
                .pipe => {
                    switch (bun.isReadable(fd)) {
                        .ready => {
                            readFromBlockingPipeWithoutBlocking(this, buffer, fd, 0, false);
                        },
                        .hup => {
                            readFromBlockingPipeWithoutBlocking(this, buffer, fd, 0, true);
                        },
                        .not_ready => {
                            if (comptime vtable.registerPoll) |register| {
                                register(this);
                            }
                        },
                    }
                },
            }
        }

        pub fn onPoll(parent: *This, size_hint: isize, received_hup: bool) void {
            const resizable_buffer = vtable.getBuffer(parent);
            const fd = vtable.getFd(parent);
            bun.sys.syslog("onPoll({d}) = {d}", .{ fd, size_hint });

            switch (vtable.getFileType(parent)) {
                .nonblocking_pipe => {
                    readPipe(parent, resizable_buffer, fd, size_hint, received_hup);
                },
                .file => {
                    readFile(parent, resizable_buffer, fd, size_hint, received_hup);
                },
                .socket => {
                    readSocket(parent, resizable_buffer, fd, size_hint, received_hup);
                },
                .pipe => {
                    readFromBlockingPipeWithoutBlocking(parent, resizable_buffer, fd, size_hint, received_hup);
                },
            }
        }

        const stack_buffer_len = 64 * 1024;

        inline fn drainChunk(parent: *This, chunk: []const u8, hasMore: ReadState) bool {
            if (parent.vtable.isStreamingEnabled()) {
                if (chunk.len > 0) {
                    return parent.vtable.onReadChunk(chunk, hasMore);
                }
            }

            return false;
        }

        fn readFile(parent: *This, resizable_buffer: *std.ArrayList(u8), fd: bun.FileDescriptor, size_hint: isize, received_hup: bool) void {
            return readWithFn(parent, resizable_buffer, fd, size_hint, received_hup, .file, bun.sys.read);
        }

        fn readSocket(parent: *This, resizable_buffer: *std.ArrayList(u8), fd: bun.FileDescriptor, size_hint: isize, received_hup: bool) void {
            return readWithFn(parent, resizable_buffer, fd, size_hint, received_hup, .file, bun.sys.recvNonBlock);
        }

        fn readPipe(parent: *This, resizable_buffer: *std.ArrayList(u8), fd: bun.FileDescriptor, size_hint: isize, received_hup: bool) void {
            return readWithFn(parent, resizable_buffer, fd, size_hint, received_hup, .nonblocking_pipe, bun.sys.readNonblocking);
        }

        fn readBlockingPipe(parent: *This, resizable_buffer: *std.ArrayList(u8), fd: bun.FileDescriptor, size_hint: isize, received_hup: bool) void {
            return readWithFn(parent, resizable_buffer, fd, size_hint, received_hup, .pipe, bun.sys.readNonblocking);
        }

        fn readWithFn(parent: *This, resizable_buffer: *std.ArrayList(u8), fd: bun.FileDescriptor, size_hint: isize, received_hup_: bool, comptime file_type: FileType, comptime sys_fn: *const fn (bun.FileDescriptor, []u8) JSC.Maybe(usize)) void {
            _ = size_hint; // autofix
            const streaming = parent.vtable.isStreamingEnabled();

            var received_hup = received_hup_;

            if (streaming) {
                const stack_buffer = parent.vtable.eventLoop().pipeReadBuffer();
                while (resizable_buffer.capacity == 0) {
                    const stack_buffer_cutoff = stack_buffer.len / 2;
                    var stack_buffer_head = stack_buffer;
                    while (stack_buffer_head.len > 16 * 1024) {
                        var buffer = stack_buffer_head;

                        switch (sys_fn(
                            fd,
                            buffer,
                        )) {
                            .result => |bytes_read| {
                                buffer = stack_buffer_head[0..bytes_read];
                                stack_buffer_head = stack_buffer_head[bytes_read..];

                                if (bytes_read == 0) {
                                    vtable.close(parent);
                                    if (stack_buffer[0 .. stack_buffer.len - stack_buffer_head.len].len > 0)
                                        _ = parent.vtable.onReadChunk(stack_buffer[0 .. stack_buffer.len - stack_buffer_head.len], .eof);
                                    vtable.done(parent);
                                    return;
                                }

                                if (comptime file_type == .pipe) {
                                    if (bun.Environment.isMac or !bun.C.RWFFlagSupport.isMaybeSupported()) {
                                        switch (bun.isReadable(fd)) {
                                            .ready => {},
                                            .hup => {
                                                received_hup = true;
                                            },
                                            .not_ready => {
                                                if (received_hup) {
                                                    vtable.close(parent);
                                                }
                                                defer {
                                                    if (received_hup) {
                                                        vtable.done(parent);
                                                    }
                                                }
                                                if (stack_buffer[0 .. stack_buffer.len - stack_buffer_head.len].len > 0) {
                                                    if (!parent.vtable.onReadChunk(stack_buffer[0 .. stack_buffer.len - stack_buffer_head.len], if (received_hup) .eof else .drained)) {
                                                        return;
                                                    }
                                                }

                                                if (!received_hup) {
                                                    if (comptime vtable.registerPoll) |register| {
                                                        register(parent);
                                                    }
                                                }

                                                return;
                                            },
                                        }
                                    }
                                }

                                if (comptime file_type != .pipe) {
                                    // blocking pipes block a process, so we have to keep reading as much as we can
                                    // otherwise, we do want to stream the data
                                    if (stack_buffer_head.len < stack_buffer_cutoff) {
                                        if (!parent.vtable.onReadChunk(stack_buffer[0 .. stack_buffer.len - stack_buffer_head.len], if (received_hup) .eof else .progress)) {
                                            return;
                                        }
                                        stack_buffer_head = stack_buffer;
                                    }
                                }
                            },
                            .err => |err| {
                                if (err.isRetry()) {
                                    if (comptime file_type == .file) {
                                        bun.Output.debugWarn("Received EAGAIN while reading from a file. This is a bug.", .{});
                                    } else {
                                        if (comptime vtable.registerPoll) |register| {
                                            register(parent);
                                        }
                                    }

                                    if (stack_buffer[0 .. stack_buffer.len - stack_buffer_head.len].len > 0)
                                        _ = parent.vtable.onReadChunk(stack_buffer[0 .. stack_buffer.len - stack_buffer_head.len], .drained);
                                    return;
                                }

                                if (stack_buffer[0 .. stack_buffer.len - stack_buffer_head.len].len > 0)
                                    _ = parent.vtable.onReadChunk(stack_buffer[0 .. stack_buffer.len - stack_buffer_head.len], .progress);
                                vtable.onError(parent, err);
                                return;
                            },
                        }
                    }

                    if (stack_buffer[0 .. stack_buffer.len - stack_buffer_head.len].len > 0) {
                        if (!parent.vtable.onReadChunk(stack_buffer[0 .. stack_buffer.len - stack_buffer_head.len], if (received_hup) .eof else .progress) and !received_hup) {
                            return;
                        }
                    }

                    if (!parent.vtable.isStreamingEnabled()) break;
                }
            }

            while (true) {
                resizable_buffer.ensureUnusedCapacity(16 * 1024) catch bun.outOfMemory();
                var buffer: []u8 = resizable_buffer.unusedCapacitySlice();

                switch (sys_fn(fd, buffer)) {
                    .result => |bytes_read| {
                        buffer = buffer[0..bytes_read];
                        resizable_buffer.items.len += bytes_read;

                        if (bytes_read == 0) {
                            vtable.close(parent);
                            _ = drainChunk(parent, resizable_buffer.items, .eof);
                            vtable.done(parent);
                            return;
                        }

                        if (comptime file_type == .pipe) {
                            if (bun.Environment.isMac or !bun.C.RWFFlagSupport.isMaybeSupported()) {
                                switch (bun.isReadable(fd)) {
                                    .ready => {},
                                    .hup => {
                                        received_hup = true;
                                    },
                                    .not_ready => {
                                        if (received_hup) {
                                            vtable.close(parent);
                                        }
                                        defer {
                                            if (received_hup) {
                                                vtable.done(parent);
                                            }
                                        }

                                        if (parent.vtable.isStreamingEnabled()) {
                                            defer {
                                                resizable_buffer.clearRetainingCapacity();
                                            }
                                            if (!parent.vtable.onReadChunk(resizable_buffer.items, if (received_hup) .eof else .drained) and !received_hup) {
                                                return;
                                            }
                                        }

                                        if (!received_hup) {
                                            if (comptime vtable.registerPoll) |register| {
                                                register(parent);
                                            }
                                        }

                                        return;
                                    },
                                }
                            }
                        }

                        if (comptime file_type != .pipe) {
                            if (parent.vtable.isStreamingEnabled()) {
                                if (resizable_buffer.items.len > 128_000) {
                                    defer {
                                        resizable_buffer.clearRetainingCapacity();
                                    }
                                    if (!parent.vtable.onReadChunk(resizable_buffer.items, .progress)) {
                                        return;
                                    }

                                    continue;
                                }
                            }
                        }
                    },
                    .err => |err| {
                        if (parent.vtable.isStreamingEnabled()) {
                            if (resizable_buffer.items.len > 0) {
                                _ = parent.vtable.onReadChunk(resizable_buffer.items, .drained);
                                resizable_buffer.clearRetainingCapacity();
                            }
                        }

                        if (err.isRetry()) {
                            if (comptime file_type == .file) {
                                bun.Output.debugWarn("Received EAGAIN while reading from a file. This is a bug.", .{});
                            } else {
                                if (comptime vtable.registerPoll) |register| {
                                    register(parent);
                                }
                            }
                            return;
                        }
                        vtable.onError(parent, err);
                        return;
                    },
                }
            }
        }

        fn readFromBlockingPipeWithoutBlocking(parent: *This, resizable_buffer: *std.ArrayList(u8), fd: bun.FileDescriptor, size_hint: isize, received_hup: bool) void {
            if (parent.vtable.isStreamingEnabled()) {
                resizable_buffer.clearRetainingCapacity();
            }

            readBlockingPipe(parent, resizable_buffer, fd, size_hint, received_hup);
        }
    };
}

const PollOrFd = @import("./pipes.zig").PollOrFd;

pub fn WindowsPipeReader(
    comptime This: type,
    comptime _: anytype,
    comptime getBuffer: fn (*This) *std.ArrayList(u8),
    comptime onReadChunk: fn (*This, chunk: []u8, ReadState) bool,
    comptime registerPoll: ?fn (*This) void,
    comptime done: fn (*This) void,
    comptime onError: fn (*This, bun.sys.Error) void,
) type {
    return struct {
        fn onStreamAlloc(handle: *uv.Handle, suggested_size: usize, buf: *uv.uv_buf_t) callconv(.C) void {
            var this = bun.cast(*This, handle.data);
            const result = this.getReadBufferWithStableMemoryAddress(suggested_size);
            buf.* = uv.uv_buf_t.init(result);
        }

        fn onStreamRead(stream: *uv.uv_stream_t, nread: uv.ReturnCodeI64, buf: *const uv.uv_buf_t) callconv(.C) void {
            var this = bun.cast(*This, stream.data);

            const nread_int = nread.int();
            //NOTE: pipes/tty need to call stopReading on errors (yeah)
            switch (nread_int) {
                0 => {
                    // EAGAIN or EWOULDBLOCK or canceled  (buf is not safe to access here)
                    return this.onRead(.{ .result = 0 }, "", .drained);
                },
                uv.UV_EOF => {
                    _ = this.stopReading();
                    // EOF (buf is not safe to access here)
                    return this.onRead(.{ .result = 0 }, "", .eof);
                },
                else => {
                    if (nread.toError(.recv)) |err| {
                        _ = this.stopReading();
                        // ERROR (buf is not safe to access here)
                        this.onRead(.{ .err = err }, "", .progress);
                        return;
                    }
                    // we got some data we can slice the buffer!
                    const len: usize = @intCast(nread_int);
                    var slice = buf.slice();
                    this.onRead(.{ .result = len }, slice[0..len], .progress);
                },
            }
        }

        fn onFileRead(fs: *uv.fs_t) callconv(.C) void {
            var this: *This = bun.cast(*This, fs.data);
            const nread_int = fs.result.int();
            const continue_reading = !this.is_paused;
            this.is_paused = true;

            switch (nread_int) {
                // 0 actually means EOF too
                0, uv.UV_EOF => {
                    this.onRead(.{ .result = 0 }, "", .eof);
                },
                uv.UV_ECANCELED => {
                    this.onRead(.{ .result = 0 }, "", .drained);
                },
                else => {
                    if (fs.result.toError(.recv)) |err| {
                        this.onRead(.{ .err = err }, "", .progress);
                        return;
                    }
                    // continue reading
                    defer {
                        if (continue_reading) {
                            _ = this.startReading();
                        }
                    }

                    const len: usize = @intCast(nread_int);
                    // we got some data lets get the current iov
                    if (this.source) |source| {
                        if (source == .file) {
                            var buf = source.file.iov.slice();
                            return this.onRead(.{ .result = len }, buf[0..len], .progress);
                        }
                    }
                    // ops we should not hit this lets fail with EPIPE
                    std.debug.assert(false);
                    return this.onRead(.{ .err = bun.sys.Error.fromCode(bun.C.E.PIPE, .read) }, "", .progress);
                },
            }
        }

        pub fn startReading(this: *This) bun.JSC.Maybe(void) {
            if (!this.is_paused) return .{ .result = {} };
            this.is_paused = false;
            const source: Source = this.source orelse return .{ .err = bun.sys.Error.fromCode(bun.C.E.BADF, .read) };

            switch (source) {
                .file => |file| {
                    file.fs.deinit();
                    const buf = this.getReadBufferWithStableMemoryAddress(64 * 1024);
                    file.iov = uv.uv_buf_t.init(buf);
                    if (uv.uv_fs_read(uv.Loop.get(), &file.fs, file.file, @ptrCast(&file.iov), 1, -1, onFileRead).toError(.write)) |err| {
                        return .{ .err = err };
                    }
                },
                else => {
                    if (uv.uv_read_start(source.toStream(), &onStreamAlloc, @ptrCast(&onStreamRead)).toError(.open)) |err| {
                        return .{ .err = err };
                    }
                },
            }

            return .{ .result = {} };
        }

        pub fn stopReading(this: *This) bun.JSC.Maybe(void) {
            if (this.is_paused) return .{ .result = {} };
            this.is_paused = true;
            const source = this.source orelse return .{ .result = {} };
            switch (source) {
                .file => |file| {
                    file.fs.cancel();
                },
                else => {
                    source.toStream().readStop();
                },
            }
            return .{ .result = {} };
        }

        pub fn close(this: *This) void {
            _ = this.stopReading();
            if (this.source) |source| {
                if (source == .file) {
                    source.file.fs.deinit();
                    // TODO: handle this error instead of ignoring it
                    _ = uv.uv_fs_close(uv.Loop.get(), &source.file.fs, source.file.file, @ptrCast(&onCloseSource));
                    return;
                }
                source.getHandle().close(onCloseSource);
            }
        }

        const vtable = .{
            .getBuffer = getBuffer,
            .registerPoll = registerPoll,
            .done = done,
            .onError = onError,
        };

        fn onCloseSource(handle: *uv.Handle) callconv(.C) void {
            const this = bun.cast(*This, handle.data);
            switch (this.source.?) {
                .file => |file| {
                    file.fs.deinit();
                    // mark "closed"
                    this.source.?.file.file = -1;
                },
                else => {},
            }
            done(this);
        }

        pub fn onRead(this: *This, amount: bun.JSC.Maybe(usize), slice: []u8, hasMore: ReadState) void {
            if (amount == .err) {
                onError(this, amount.err);
                return;
            }

            switch (hasMore) {
                .eof => {
                    // we call report EOF and close
                    _ = onReadChunk(this, slice, hasMore);
                    close(this);
                },
                .drained => {
                    // we call drained so we know if we should stop here
                    const keep_reading = onReadChunk(this, slice, hasMore);
                    if (!keep_reading) {
                        close(this);
                    }
                },
                else => {
                    var buffer = getBuffer(this);
                    if (comptime bun.Environment.allow_assert) {
                        if (slice.len > 0 and !bun.isSliceInBuffer(slice, buffer.allocatedSlice())) {
                            @panic("uv_read_cb: buf is not in buffer! This is a bug in bun. Please report it.");
                        }
                    }
                    // move cursor foward
                    buffer.items.len += amount.result;
                    const keep_reading = onReadChunk(this, slice, hasMore);
                    if (!keep_reading) {
                        close(this);
                    }
                },
            }
        }

        pub fn pause(this: *This) void {
            const pipe = this._pipe() orelse return;
            if (pipe.isActive()) {
                this.stopReading().unwrap() catch unreachable;
            }
        }

        pub fn unpause(this: *This) void {
            _ = this.startReading();
        }

        pub fn read(this: *This) void {
            // we cannot sync read pipes on Windows so we just check if we are paused to resume the reading
            this.unpause();
        }
    };
}

pub const PipeReader = if (bun.Environment.isWindows) WindowsPipeReader else PosixPipeReader;
const Async = bun.Async;

// This is a runtime type instead of comptime due to bugs in Zig.
// https://github.com/ziglang/zig/issues/18664
const BufferedReaderVTable = struct {
    parent: *anyopaque = undefined,
    fns: *const Fn = undefined,

    pub fn init(comptime Type: type) BufferedReaderVTable {
        return .{
            .fns = Fn.init(Type),
        };
    }

    pub const Fn = struct {
        onReadChunk: ?*const fn (*anyopaque, chunk: []const u8, hasMore: ReadState) bool = null,
        onReaderDone: *const fn (*anyopaque) void,
        onReaderError: *const fn (*anyopaque, bun.sys.Error) void,
        loop: *const fn (*anyopaque) *Async.Loop,
        eventLoop: *const fn (*anyopaque) JSC.EventLoopHandle,

        pub fn init(comptime Type: type) *const BufferedReaderVTable.Fn {
            const loop_fn = &struct {
                pub fn loop_fn(this: *anyopaque) *Async.Loop {
                    return Type.loop(@alignCast(@ptrCast(this)));
                }
            }.loop_fn;

            const eventLoop_fn = &struct {
                pub fn eventLoop_fn(this: *anyopaque) JSC.EventLoopHandle {
                    return JSC.EventLoopHandle.init(Type.eventLoop(@alignCast(@ptrCast(this))));
                }
            }.eventLoop_fn;
            return comptime &BufferedReaderVTable.Fn{
                .onReadChunk = if (@hasDecl(Type, "onReadChunk")) @ptrCast(&Type.onReadChunk) else null,
                .onReaderDone = @ptrCast(&Type.onReaderDone),
                .onReaderError = @ptrCast(&Type.onReaderError),
                .eventLoop = eventLoop_fn,
                .loop = loop_fn,
            };
        }
    };

    pub fn eventLoop(this: @This()) JSC.EventLoopHandle {
        return this.fns.eventLoop(this.parent);
    }

    pub fn loop(this: @This()) *Async.Loop {
        return this.fns.loop(this.parent);
    }

    pub fn isStreamingEnabled(this: @This()) bool {
        return this.fns.onReadChunk != null;
    }

    /// When the reader has read a chunk of data
    /// and hasMore is true, it means that there might be more data to read.
    ///
    /// Returning false prevents the reader from reading more data.
    pub fn onReadChunk(this: @This(), chunk: []const u8, hasMore: ReadState) bool {
        return this.fns.onReadChunk.?(this.parent, chunk, hasMore);
    }

    pub fn onReaderDone(this: @This()) void {
        this.fns.onReaderDone(this.parent);
    }

    pub fn onReaderError(this: @This(), err: bun.sys.Error) void {
        this.fns.onReaderError(this.parent, err);
    }
};

const PosixBufferedReader = struct {
    handle: PollOrFd = .{ .closed = {} },
    _buffer: std.ArrayList(u8) = std.ArrayList(u8).init(bun.default_allocator),
    vtable: BufferedReaderVTable,
    flags: Flags = .{},

    const Flags = packed struct {
        is_done: bool = false,
        pollable: bool = false,
        nonblocking: bool = false,
        received_eof: bool = false,
        closed_without_reporting: bool = false,
    };

    pub fn init(comptime Type: type) PosixBufferedReader {
        return .{
            .vtable = BufferedReaderVTable.init(Type),
        };
    }

    pub fn updateRef(this: *const PosixBufferedReader, value: bool) void {
        const poll = this.handle.getPoll() orelse return;
        poll.setKeepingProcessAlive(this.vtable.eventLoop(), value);
    }

    pub inline fn isDone(this: *const PosixBufferedReader) bool {
        return this.flags.is_done or this.flags.received_eof or this.flags.closed_without_reporting;
    }

    pub fn from(to: *@This(), other: *PosixBufferedReader, parent_: *anyopaque) void {
        to.* = .{
            .handle = other.handle,
            ._buffer = other.buffer().*,
            .flags = other.flags,
            .vtable = .{
                .fns = to.vtable.fns,
                .parent = parent_,
            },
        };
        other.buffer().* = std.ArrayList(u8).init(bun.default_allocator);
        other.flags.is_done = true;
        other.handle = .{ .closed = {} };
        to.handle.setOwner(to);
        if (to._buffer.items.len > 0) {
            _ = to.drainChunk(to._buffer.items[0..], .progress);
        }
    }

    pub fn setParent(this: *PosixBufferedReader, parent_: *anyopaque) void {
        this.vtable.parent = parent_;
        this.handle.setOwner(this);
    }

    pub usingnamespace PosixPipeReader(@This(), .{
        .getFd = @ptrCast(&getFd),
        .getBuffer = @ptrCast(&buffer),
        .onReadChunk = @ptrCast(&_onReadChunk),
        .registerPoll = @ptrCast(&registerPoll),
        .done = @ptrCast(&done),
        .close = @ptrCast(&closeWithoutReporting),
        .onError = @ptrCast(&onError),
        .getFileType = @ptrCast(&getFileType),
    });

    fn getFileType(this: *const PosixBufferedReader) FileType {
        if (this.flags.pollable) {
            if (this.flags.nonblocking) {
                return .nonblocking_pipe;
            }

            return .pipe;
        }

        return .file;
    }

    pub fn close(this: *PosixBufferedReader) void {
        this.closeHandle();
    }

    fn closeWithoutReporting(this: *PosixBufferedReader) void {
        if (this.getFd() != bun.invalid_fd) {
            std.debug.assert(!this.flags.closed_without_reporting);
            this.flags.closed_without_reporting = true;
            this.handle.close(this, {});
        }
    }

    fn _onReadChunk(this: *PosixBufferedReader, chunk: []u8, hasMore: ReadState) bool {
        if (hasMore == .eof) {
            this.flags.received_eof = true;
        }

        return this.vtable.onReadChunk(chunk, hasMore);
    }

    pub fn getFd(this: *PosixBufferedReader) bun.FileDescriptor {
        return this.handle.getFd();
    }

    // No-op on posix.
    pub fn pause(this: *PosixBufferedReader) void {
        _ = this; // autofix

    }

    pub fn buffer(this: *PosixBufferedReader) *std.ArrayList(u8) {
        return &@as(*PosixBufferedReader, @alignCast(@ptrCast(this)))._buffer;
    }

    pub fn disableKeepingProcessAlive(this: *@This(), event_loop_ctx: anytype) void {
        _ = event_loop_ctx; // autofix
        this.updateRef(false);
    }

    pub fn enableKeepingProcessAlive(this: *@This(), event_loop_ctx: anytype) void {
        _ = event_loop_ctx; // autofix
        this.updateRef(true);
    }

    fn finish(this: *PosixBufferedReader) void {
        if (this.handle != .closed or this.flags.closed_without_reporting) {
            this.closeHandle();
            return;
        }

        std.debug.assert(!this.flags.is_done);
        this.flags.is_done = true;
    }

    fn closeHandle(this: *PosixBufferedReader) void {
        if (this.flags.closed_without_reporting) {
            this.flags.closed_without_reporting = false;
            this.done();
            return;
        }

        this.handle.close(this, done);
    }

    pub fn done(this: *PosixBufferedReader) void {
        if (this.handle != .closed) {
            this.closeHandle();
            return;
        } else if (this.flags.closed_without_reporting) {
            this.flags.closed_without_reporting = false;
        }
        this.finish();
        this.vtable.onReaderDone();
    }

    pub fn deinit(this: *PosixBufferedReader) void {
        this.buffer().clearAndFree();
        this.closeHandle();
    }

    pub fn onError(this: *PosixBufferedReader, err: bun.sys.Error) void {
        this.vtable.onReaderError(err);
    }

    pub fn registerPoll(this: *PosixBufferedReader) void {
        const poll = this.handle.getPoll() orelse brk: {
            if (this.handle == .fd and this.flags.pollable) {
                this.handle = .{ .poll = Async.FilePoll.init(this.eventLoop(), this.handle.fd, .{}, @This(), this) };
                break :brk this.handle.poll;
            }

            return;
        };
        poll.owner.set(this);

        if (!poll.flags.contains(.was_ever_registered))
            poll.enableKeepingProcessAlive(this.eventLoop());

        switch (poll.registerWithFd(this.loop(), .readable, .dispatch, poll.fd)) {
            .err => |err| {
                this.onError(err);
            },
            .result => {},
        }
    }

    pub fn start(this: *PosixBufferedReader, fd: bun.FileDescriptor, is_pollable: bool) bun.JSC.Maybe(void) {
        if (!is_pollable) {
            this.buffer().clearRetainingCapacity();
            this.flags.is_done = false;
            this.handle.close(null, {});
            this.handle = .{ .fd = fd };
            return .{ .result = {} };
        }
        this.flags.pollable = true;
        if (this.getFd() != fd) {
            this.handle = .{ .fd = fd };
        }
        this.registerPoll();

        return .{
            .result = {},
        };
    }

    // Exists for consistentcy with Windows.
    pub fn hasPendingRead(this: *const PosixBufferedReader) bool {
        return this.handle == .poll and this.handle.poll.isRegistered();
    }

    pub fn watch(this: *PosixBufferedReader) void {
        if (this.flags.pollable) {
            this.registerPoll();
        }
    }

    pub fn hasPendingActivity(this: *const PosixBufferedReader) bool {
        return switch (this.handle) {
            .poll => |poll| poll.isActive(),
            .fd => true,
            else => false,
        };
    }

    pub fn loop(this: *const PosixBufferedReader) *Async.Loop {
        return this.vtable.loop();
    }

    pub fn eventLoop(this: *const PosixBufferedReader) JSC.EventLoopHandle {
        return this.vtable.eventLoop();
    }
};

const JSC = bun.JSC;

const WindowsOutputReaderVTable = struct {
    onReaderDone: *const fn (*anyopaque) void,
    onReaderError: *const fn (*anyopaque, bun.sys.Error) void,
    onReadChunk: ?*const fn (
        *anyopaque,
        chunk: []const u8,
        hasMore: ReadState,
    ) bool = null,
};

pub const WindowsBufferedReader = struct {
    /// The pointer to this pipe must be stable.
    /// It cannot change because we don't know what libuv will do with it.
    source: ?Source = null,
    _buffer: std.ArrayList(u8) = std.ArrayList(u8).init(bun.default_allocator),
    // for compatibility with Linux
    flags: Flags = .{},

    has_inflight_read: bool = false,
    is_paused: bool = true,
    parent: *anyopaque = undefined,
    vtable: WindowsOutputReaderVTable = undefined,
    ref_count: u32 = 1,
    pub usingnamespace bun.NewRefCounted(@This(), deinit);

    const WindowsOutputReader = @This();

    const Flags = packed struct {
        is_done: bool = false,
        pollable: bool = false,
        nonblocking: bool = false,
        received_eof: bool = false,
        closed_without_reporting: bool = false,
    };

    pub fn init(comptime Type: type) WindowsOutputReader {
        return .{
            .vtable = .{
                .onReadChunk = if (@hasDecl(Type, "onReadChunk")) @ptrCast(&Type.onReadChunk) else null,
                .onReaderDone = @ptrCast(&Type.onReaderDone),
                .onReaderError = @ptrCast(&Type.onReaderError),
            },
        };
    }

    pub inline fn isDone(this: *WindowsOutputReader) bool {
        return this.flags.is_done or this.flags.received_eof or this.flags.closed_without_reporting;
    }

    pub fn from(to: *WindowsOutputReader, other: anytype, parent: anytype) void {
        std.debug.assert(other.source != null and to.source == null);
        to.* = .{
            .vtable = to.vtable,
            .flags = other.flags,
            ._buffer = other.buffer().*,
            .has_inflight_read = other.has_inflight_read,
            .source = other.source,
        };
        other.flags.is_done = true;
        other.source = null;
        to.setParent(parent);
    }

    pub fn getFd(this: *const WindowsOutputReader) bun.FileDescriptor {
        const source = this.source orelse return bun.invalid_fd;
        return source.getFd();
    }

    pub fn watch(_: *WindowsOutputReader) void {
        // No-op on windows.
    }

    pub fn setParent(this: *WindowsOutputReader, parent: anytype) void {
        this.parent = parent;
        if (!this.flags.is_done) {
            if (this.source) |source| {
                source.setData(this);
            }
        }
    }

    pub fn updateRef(this: *WindowsOutputReader, value: bool) void {
        if (this.source) |source| {
            if (value) {
                source.ref();
            } else {
                source.unref();
            }
        }
    }

    pub fn enableKeepingProcessAlive(this: *WindowsOutputReader, _: anytype) void {
        this.updateRef(true);
    }

    pub fn disableKeepingProcessAlive(this: *WindowsOutputReader, _: anytype) void {
        this.updateRef(false);
    }

    pub usingnamespace WindowsPipeReader(
        @This(),
        {},
        buffer,
        _onReadChunk,
        null,
        done,
        onError,
    );

    pub fn buffer(this: *WindowsOutputReader) *std.ArrayList(u8) {
        return &this._buffer;
    }

    pub fn hasPendingActivity(this: *const WindowsOutputReader) bool {
        const source = this.source orelse return false;
        return !source.isClosed();
    }

    pub fn hasPendingRead(this: *const WindowsOutputReader) bool {
        return this.has_inflight_read;
    }

    fn _onReadChunk(this: *WindowsOutputReader, buf: []u8, hasMore: ReadState) bool {
        this.has_inflight_read = false;
        if (hasMore == .eof) {
            this.flags.received_eof = true;
        }

        const onReadChunkFn = this.vtable.onReadChunk orelse return true;
        return onReadChunkFn(this.parent, buf, hasMore);
    }

    fn finish(this: *WindowsOutputReader) void {
        std.debug.assert(!this.flags.is_done);
        this.has_inflight_read = false;
        this.flags.is_done = true;
    }

    pub fn done(this: *WindowsOutputReader) void {
        std.debug.assert(if (this.source) |source| source.isClosed() else true);

        this.finish();

        this.vtable.onReaderDone(this.parent);
    }

    pub fn onError(this: *WindowsOutputReader, err: bun.sys.Error) void {
        this.finish();
        this.vtable.onReaderError(this.parent, err);
    }

    pub fn getReadBufferWithStableMemoryAddress(this: *WindowsOutputReader, suggested_size: usize) []u8 {
        this.has_inflight_read = true;
        this._buffer.ensureUnusedCapacity(suggested_size) catch bun.outOfMemory();
        const res = this._buffer.allocatedSlice()[this._buffer.items.len..];
        return res;
    }

    pub fn startWithCurrentPipe(this: *WindowsOutputReader) bun.JSC.Maybe(void) {
        std.debug.assert(this.source != null);
        this.buffer().clearRetainingCapacity();
        this.flags.is_done = false;
        this.unpause();
        return .{ .result = {} };
    }

    pub fn startWithPipe(this: *WindowsOutputReader, pipe: *uv.Pipe) bun.JSC.Maybe(void) {
        std.debug.assert(this.source == null);
        this.source = .{ .pipe = pipe };
        return this.startWithCurrentPipe();
    }

    pub fn start(this: *WindowsOutputReader, fd: bun.FileDescriptor, _: bool) bun.JSC.Maybe(void) {
        std.debug.assert(this.source == null);
        const source = switch (Source.open(uv.Loop.get(), fd)) {
            .err => |err| return .{ .err = err },
            .result => |source| source,
        };
        source.setData(this);
        this.source = source;
        return this.startWithCurrentPipe();
    }

    pub fn deinit(this: *WindowsOutputReader) void {
        this.buffer().deinit();
        const source = this.source orelse return;
        std.debug.assert(source.isClosed());
        this.source = null;
        switch (source) {
            inline else => |ptr| bun.default_allocator.destroy(ptr),
        }
    }
};

pub const BufferedReader = if (bun.Environment.isPosix)
    PosixBufferedReader
else if (bun.Environment.isWindows)
    WindowsBufferedReader
else
    @compileError("Unsupported platform");
