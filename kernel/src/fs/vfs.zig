const std = @import("std");
const root = @import("root");
const slab = @import("../memory/paging/slab.zig");

// Node type representing either a directory or a file
const NodeType = enum {
    Directory,
    File,
};

// Structure representing a tree node
const TreeNode = struct {
    name: []const u8,       // Node name
    nodeType: NodeType,     // Type of node (Directory or File)
    children: []TreeNode,   // Children of the directory node
};

// Interface representing a file system
const FileSystem = struct {
    // Function to initialize the file system
    init: fn(this: *FileSystem, vfs: *VFS) anyerror!void,

    // Function to traverse the file system and return the node corresponding to the given path
    getNode: fn(this: *FileSystem, path: []const u8) ?*TreeNode,
};

// File system implementation for DevFS
const DevFS = struct {
    vfs: ?*VFS,
    const Self = @This();

    pub fn init(this: *Self, vfs: *VFS) anyerror!void {
        this.vfs = vfs;
        // Create the root directory
        const devRoot: TreeNode = .{
            .name = "/dev",
            .nodeType = NodeType.Directory,
            .children = []TreeNode{},
        };

        // Create the "/dev/null" file
        const devNull: TreeNode = .{
            .name = "/dev/null",
            .nodeType = NodeType.File,
            .children = []TreeNode{},
        };
        // Create the "/dev/zero" file
        const devZero: TreeNode = .{
            .name = "/dev/zero",
            .nodeType = NodeType.File,
            .children = []TreeNode{},
        };

        // Add the files to the root directory
        devRoot.children = &[_]TreeNode{devNull, devZero};

        // Register the root directory in the VFS
        try vfs.getRoot().addNode(devRoot);
    }

    pub fn getNode(this: *Self, path: []const u8) ?*TreeNode {
        const vfs = this.vfs.?;

        // Use the traversal algorithm to find the node based on the path
        return vfs.?.traverseTree(path);
    }
};


// Structure representing the Virtual File System
const VFS = struct {
    root: TreeNode,         // Root directory of the VFS
    fileSystems: []FileSystem,  // Registered file systems
    
    const Self = @This();
    // Function to create a new VFS
    pub fn createVFS() VFS {
        var vfs: VFS = undefined;

        // Initialize the root directory
        vfs.root = .{
            .name = "/",
            .nodeType = NodeType.Directory,
            .children = []TreeNode{},
        };

        return vfs;
    }

    // Function to register a file system in the VFS
    pub fn registerFileSystem(vfs: *Self, fs: FileSystem) void {
        vfs.fileSystems |= &[_]FileSystem{fs};
        fs.init(&vfs);
    }

    // Function to get the root directory of the VFS
    pub fn getRoot(vfs: *Self) *TreeNode {
        return &vfs.root;
    }

    // Function to traverse the tree based on a given path
    pub fn traverseTree(root: &TreeNode, path: []const u8) ?*TreeNode {
        if path.len == 0 {
            return root;
        }

        // Split the path into segments
        const segments = std.mem.split(u8, path, '/');
        var currentNode: *TreeNode = root;

        // Iterate over each segment in the path
        for (segments) |segment| {
            if segment.len == 0 {
                continue; // Skip empty segments
            }

            var foundNode: ?*TreeNode = null;

            // Search for the segment in the current node's children
            for currentNode.children |child| {
                if std.mem.eql(u8, child.name, segment) {
                    foundNode = &child;
                    break;
                }
            }

            // If the segment was not found, return null
            if (foundNode) :?*TreeNode == null {
                return null;
            }

            currentNode = foundNode;
        }

        return currentNode;
    }
};