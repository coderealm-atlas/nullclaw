const std = @import("std");
const root = @import("root.zig");
const config_types = @import("../config_types.zig");

const log = std.log.scoped(.sms);

/// SMS channel — send-only HTTP bridge.
pub const SmsChannel = struct {
    allocator: std.mem.Allocator,
    config: config_types.SmsConfig,

    pub fn init(allocator: std.mem.Allocator, config: config_types.SmsConfig) SmsChannel {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn initFromConfig(allocator: std.mem.Allocator, cfg: config_types.SmsConfig) SmsChannel {
        return init(allocator, cfg);
    }

    pub fn deinit(_: *SmsChannel) void {}

    pub fn channelName(_: *SmsChannel) []const u8 {
        return "sms";
    }

    pub fn healthCheck(self: *SmsChannel) bool {
        return std.mem.startsWith(u8, self.config.endpoint, "https://");
    }

    pub fn sendMessage(self: *SmsChannel, target: []const u8, message: []const u8) !void {
        if (!std.mem.startsWith(u8, self.config.endpoint, "https://")) {
            return error.InvalidEndpoint;
        }

        const phone = std.mem.trim(u8, target, " \t\r\n");
        if (phone.len == 0) return error.InvalidTarget;

        const body = try buildRequestBody(self.allocator, phone, message, self.config.sender);
        defer self.allocator.free(body);

        var timeout_buf: [16]u8 = undefined;
        const timeout_arg = std.fmt.bufPrint(&timeout_buf, "{d}", .{self.config.timeout_secs}) catch "30";

        var header_storage: ?[]u8 = null;
        defer if (header_storage) |h| self.allocator.free(h);

        const headers: []const []const u8 = if (self.config.api_key) |api_key| blk: {
            header_storage = try std.fmt.allocPrint(
                self.allocator,
                "{s}: {s}{s}",
                .{ self.config.api_key_header, self.config.api_key_prefix, api_key },
            );
            break :blk &.{header_storage.?};
        } else &.{};

        const resp = root.http_util.curlPostWithStatusAndTimeout(
            self.allocator,
            self.config.endpoint,
            body,
            headers,
            timeout_arg,
        ) catch |err| {
            log.err("sms send failed: {}", .{err});
            return error.SmsApiError;
        };
        defer self.allocator.free(resp.body);

        if (resp.status_code < 200 or resp.status_code >= 300) {
            log.err("sms send returned HTTP status {d}, body={f}", .{ resp.status_code, std.json.fmt(resp.body, .{}) });
            return error.SmsApiError;
        }
    }

    fn vtableStart(_: *anyopaque) anyerror!void {}

    fn vtableStop(_: *anyopaque) void {}

    fn vtableSend(ptr: *anyopaque, target: []const u8, message: []const u8, _: []const []const u8) anyerror!void {
        const self: *SmsChannel = @ptrCast(@alignCast(ptr));
        try self.sendMessage(target, message);
    }

    fn vtableName(ptr: *anyopaque) []const u8 {
        const self: *SmsChannel = @ptrCast(@alignCast(ptr));
        return self.channelName();
    }

    fn vtableHealthCheck(ptr: *anyopaque) bool {
        const self: *SmsChannel = @ptrCast(@alignCast(ptr));
        return self.healthCheck();
    }

    pub const vtable = root.Channel.VTable{
        .start = &vtableStart,
        .stop = &vtableStop,
        .send = &vtableSend,
        .name = &vtableName,
        .healthCheck = &vtableHealthCheck,
    };

    pub fn channel(self: *SmsChannel) root.Channel {
        return .{ .ptr = @ptrCast(self), .vtable = &vtable };
    }
};

fn buildRequestBody(
    allocator: std.mem.Allocator,
    target: []const u8,
    message: []const u8,
    sender: ?[]const u8,
) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    try out.append(allocator, '{');
    {
        var w = out.writer(allocator);
        try w.writeAll("\"to\":");
        try root.appendJsonStringW(w, target);
        try w.writeAll(",\"message\":");
        try root.appendJsonStringW(w, message);
    }
    if (sender) |from| {
        var w = out.writer(allocator);
        try w.writeAll(",\"from\":");
        try root.appendJsonStringW(w, from);
    }
    try out.append(allocator, '}');

    return out.toOwnedSlice(allocator);
}

test "sms build request body includes sender" {
    const allocator = std.testing.allocator;
    const body = try buildRequestBody(allocator, "+15550001", "hello", "bot");
    defer allocator.free(body);

    try std.testing.expectEqualStrings(
        "{\"to\":\"+15550001\",\"message\":\"hello\",\"from\":\"bot\"}",
        body,
    );
}

test "sms build request body escapes payload" {
    const allocator = std.testing.allocator;
    const body = try buildRequestBody(allocator, "+1555\"0002", "line\\ntext", null);
    defer allocator.free(body);

    try std.testing.expectEqualStrings(
        "{\"to\":\"+1555\\\"0002\",\"message\":\"line\\\\ntext\"}",
        body,
    );
}
