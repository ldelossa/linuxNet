//! The Graph module implements a directed network graph comprised
//! of NetworkNode graph nodes.
//!
//! The Graph is a parsed and connected representation of a Topology.
//! It can be used to understand which networks in a Topology can reach others
//! and how to configure network connectivity to achieve this.
const std = @import("std");
const topology = @import("./topology.zig");
const mem = std.mem;
const testing = std.testing;
const log = std.log.scoped(.graph);
const Allocator = std.mem.Allocator;

// A Node within our network Graph.
// Each NetworkNode is indexed by a unique name
// Each NetworkNode 'owns' a unique and non-overlapping IPv4/6 prefix
// Each NetworkNode maintains a list of egress and ingress connections to other
// NetworkNodes by way of a slice of poiners for each.
const NetworkNode = struct { name: []u8, prefix: []u8, ingressAdj: std.ArrayList(*NetworkNode), egressAdj: std.ArrayList(*NetworkNode) };

// Graph is a directed graph of NetworkNodes.
// Each NetworkNode defines a IPv4/6 Network.
// NetworkNodes have ingress and egress adjacencies to other NetworkNodes
// creating a directed network graph.
const Graph = @This();

// unique name of graph
name: []const u8,
// allocator used during an instantiated Graph instance
allocator: Allocator,
// flat array of NeworkNodes within the Graph.
// Graphs are static after initializaion.
nodes: []NetworkNode,
// maps NetworkNode.name => *NetworkNode
map: std.StringHashMap(*NetworkNode),

// Given an initialized graph and the Topology which defined it,
// links the egress and ingress connections between NetworkNodes.
fn initLinkNodes(topo: *const topology.Topology, graph: *Graph) !void {
    var err = false;
    for (topo.networks) |net| {
        // Grab the NetworkNode which represens the current Topology network.
        const node: *NetworkNode = graph.map.get(net.name) orelse {
            log.err("topology network {s} not in graph", .{net.name});
            err = true;
            continue;
        };

        // Link adjacencies.
        // A network in the topology
        for (net.adjacencies) |adj| {
            const adj_node: *NetworkNode = graph.map.get(adj.name) orelse {
                log.err("topology adjacency {s} not in graph", .{adj.name});
                err = true;
                continue;
            };
            try node.egressAdj.append(adj_node);
            try adj_node.ingressAdj.append(node);
        }
    }
}

// Initialize a Graph from a pointer to a Topology.
// The Topology may be freed once the Graph, or an error, is returned.
pub fn init(alloc: Allocator, topo: *const topology.Topology) !Graph {
    // alloc our graph's name and copy it so Topology can be freed.
    const name: []u8 = try alloc.alloc(u8, topo.name.len);
    @memcpy(name, topo.name);

    if (topo.networks.len == 0) {
        log.err("No networks defined in topology.", .{});
        return error.GraphNoNetworks;
    }

    // alloc and register our NetworkNodes.
    var map = std.StringHashMap(*NetworkNode).init(alloc);
    var nodes = try alloc.alloc(NetworkNode, topo.networks.len);
    for (topo.networks, 0..) |net, i| {
        var net_name: []u8 = try alloc.alloc(u8, net.name.len);
        var prefix: []u8 = try alloc.alloc(u8, net.prefix.len);

        @memcpy(net_name, net.name);
        @memcpy(prefix, net.prefix);

        nodes[i] = .{
            .name = net_name,
            .prefix = prefix,
            .ingressAdj = std.ArrayList(*NetworkNode).init(alloc),
            .egressAdj = std.ArrayList(*NetworkNode).init(alloc),
        };
        try map.put(net_name, &nodes[i]);
    }
    var g = Graph{ .allocator = alloc, .name = name, .nodes = nodes, .map = map };
    try initLinkNodes(topo, &g);
    return g;
}

// Initialize a Graph from a path to a topology.json file
pub fn initFromJSON(alloc: Allocator, path: []u8) !Graph {
    log.info("Initializing graph from: {s}\n", .{path});

    const file = std.fs.openFileAbsolute(path, .{ .mode = .read_only }) catch |err| {
        log.err("failed to open file {s}: {}", .{ path, err });
        return err;
    };
    defer file.close();

    var reader = std.json.reader(alloc, file.reader());
    defer reader.deinit();

    const parsed = try topology.initFromJSON(alloc, path);
    defer parsed.deinit();

    return init(alloc, &parsed.value);
}

pub fn deinit(self: *Graph) void {
    self.allocator.free(self.name);
    for (self.nodes) |node| {
        self.allocator.free(node.name);
        self.allocator.free(node.prefix);
        node.egressAdj.deinit();
        node.ingressAdj.deinit();
    }
    self.allocator.free(self.nodes);
    self.map.deinit();
}

// test graph initialization from json.
// this test depends on 'graph-topology-json' test passing.
test "graph-init-simple-topo" {
    const alloc = std.testing.allocator;
    var buf: [256]u8 = undefined;
    const path = try std.fs.cwd().realpathZ("./src/graph_testing/simple_topology.json", &buf);
    const parsed = try topology.initFromJSON(alloc, path);
    defer parsed.deinit();
    const topo = parsed.value;
    var graph = try initFromJSON(alloc, path);
    defer graph.deinit();

    // ensure graph name is copied.
    try testing.expectEqualStrings(topo.name, graph.name);

    // ensure NetworkNodes are parsed correctly
    try testing.expect((graph.nodes.len == 2));

    for (graph.nodes, 0..) |node, i| {
        try testing.expectEqualStrings(topo.networks[i].name, node.name);
        try testing.expectEqualStrings(topo.networks[i].prefix, node.prefix);
    }

    // specific to the test, we want to ensure net1 has an egressAdj to
    // net2 and that net2 has an ingressAdj to net1
    const net1 = &graph.nodes[0];
    const net2 = &graph.nodes[1];
    try testing.expect((net1.egressAdj.items.len == 1));
    try testing.expect(net1.egressAdj.items[0] == net2);
    try testing.expect((net1.ingressAdj.items.len == 0));

    try testing.expect((net2.egressAdj.items.len == 0));
    try testing.expect((net2.ingressAdj.items.len == 1));
    try testing.expect(net2.ingressAdj.items[0] == net1);
}
