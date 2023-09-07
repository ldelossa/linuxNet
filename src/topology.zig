//! A Topology is a user-facing description of a desired network topology.
//! It defines the topology as a set of networks, each of which own a IP prefix
//! and declare their neighboring networks.
//!
//! The Topology is a 1:1 model with a topology.json file provided by a user and
//! a topology.json file can be parsed directly into a Topology structure.
const std = @import("std");
const log = @import("log.zig").get(.topology);
const mem = std.mem;
const Allocator = std.mem.Allocator;

pub const Topology = @This();

// The unique name for the Topology as a whole.
name: []const u8,
// A set of TopologyNetworks defining each network desired in the Topology and
// their connectivity.
networks: []Network,

pub const ValidationError = error{ NoTopologyName, DuplicateNetworkName, DuplicateNetworkPrefix, NetworkAdjSelf, NetworkAdjNotFound };

// Validate the Topology given the following rules:
// - Topology must have a name
// - Each Network must have a unique name
// - Each Network must have a unique and non-overlapping prefix
// - Each Network can only declare adjacencies to other Network names in the
//   Topology.
// - Each Network must list valid adjacencies once.
// - A Network cannot define itself as an Adjacency.
pub fn validate(self: *const Topology) ValidationError!void {
    if (self.name.len == 0) {
        log.err("Topology must have a name", .{});
        return ValidationError.NoTopologyName;
    }
    for (self.networks, 0..) |net_a, i| {
        for (self.networks, 0..) |net_b, j| {
            if (i == j) {
                continue;
            }
            // confirm each network name is unique.
            if (mem.eql(u8, net_a.name, net_b.name)) {
                log.err("Cannot have duplicate network names: {s}\n", .{net_a.name});
                return ValidationError.DuplicateNetworkName;
            }
            // confirm each prefix is unique
            // TODO: ensure prefixes do not overlap either
            if (mem.eql(u8, net_a.prefix, net_b.prefix)) {
                log.err("Network {s} and {s} cannot have the same prefix {s}", .{ net_a.name, net_b.name, net_a.prefix });
                return ValidationError.DuplicateNetworkPrefix;
            }
        }
        for (net_a.adjacencies) |adj| {
            // confirm network does not list itself as an adjacency.
            if (mem.eql(u8, net_a.name, adj.name)) {
                log.err("Network {s} cannot specify itself as an adjacency", .{net_a.name});
                return ValidationError.NetworkAdjSelf;
            }
            // confirm network lists only valid networks as adjacencies.
            var found = false;
            for (self.networks) |net| {
                if (mem.eql(u8, net.name, adj.name)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                log.err("Network {s} declares adjacency to {s} which is not in the topology", .{ net_a.name, adj.name });
                return ValidationError.NetworkAdjNotFound;
            }
        }
    }
}

// A Network within the Topology.
pub const Network = struct {
    name: []const u8,
    prefix: []const u8,
    adjacencies: []Adjacency,
};

// The declaration of a Network's adjacency.
// This declares the 'directly attached' neighboring network.
pub const Adjacency = struct {
    name: []const u8,
};

// Parses the absolute fs path into a Topology and returns the json.Parsed
// sructure.
//
// The caller is responsible for freeing the returned json.Parsed when they
// no longer need the Topology.
pub fn initFromJSON(alloc: Allocator, path: []u8) !std.json.Parsed(Topology) {
    const file = std.fs.openFileAbsolute(path, .{ .mode = .read_only }) catch |err| {
        std.log.err("[graph] failed to open file {s}: {}", .{ path, err });
        return err;
    };
    defer file.close();

    var reader = std.json.reader(alloc, file.reader());
    defer reader.deinit();

    const parsed = std.json.parseFromTokenSource(Topology, alloc, &reader, .{}) catch |err| {
        std.log.err("[graph] failed to parse Topology: {}", .{err});
        return err;
    };
    return parsed;
}

// Test that a Topology is correctly parsed from a simple topology.json file.
test "graph-topology" {
    const alloc = std.testing.allocator;
    var buf: [256]u8 = undefined;
    const path = try std.fs.cwd().realpathZ("./src/graph_testing/simple_topology.json", &buf);
    const parsed = try initFromJSON(alloc, path);
    defer parsed.deinit();
    const topo = parsed.value;

    // check topo name.
    try std.testing.expect(std.mem.eql(u8, topo.name, "simple topology"));
    // TODO continue checking topology
}

test "topology-validation-error-no-name" {
    const t: Topology = .{
        .name = undefined,
        .networks = undefined,
    };
    const err = t.validate();
    try std.testing.expect(err == ValidationError.NoTopologyName);
}

test "topology-validation-dup-network" {
    var nets = [_]Network{ .{
        .name = "net1",
        .prefix = undefined,
        .adjacencies = undefined,
    }, .{
        .name = "net1",
        .prefix = undefined,
        .adjacencies = undefined,
    } };
    const t: Topology = .{ .name = "dup", .networks = nets[0..] };
    const err = t.validate();
    try std.testing.expect(err == ValidationError.DuplicateNetworkName);
}
