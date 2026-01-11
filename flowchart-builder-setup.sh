#!/bin/bash

set -e

echo "🚀 Setting up Flowchart Editor..."

# Create project directory
cd ~
mkdir -p flowchart-builder/src
cd flowchart-builder

echo "📝 Creating package.json..."
cat << 'EOF' > package.json
{
  "name": "flowchart-builder",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "npx vite",
    "build": "npx vite build",
    "preview": "npx vite preview"
  },
  "dependencies": {
    "react": "18.3.1",
    "react-dom": "18.3.1",
    "reactflow": "11.10.0"
  },
  "devDependencies": {
    "vite": "5.4.10",
    "@vitejs/plugin-react": "4.2.1"
  }
}
EOF

echo "📝 Creating vite.config.js..."
cat << 'EOF' > vite.config.js
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { spawn } from 'child_process';

export default defineConfig({
  plugins: [
    react(),
    {
      name: 'flowchart-api',
      configureServer(server) {
        server.middlewares.use(async (req, res, next) => {
          if (req.url === '/api/generate-flowchart' && req.method === 'POST') {
            let body = '';
            
            req.on('data', chunk => {
              body += chunk.toString();
            });
            
            req.on('end', () => {
              const python = spawn('python3', ['generate_flowchart.py']);
              
              python.stdin.write(body);
              python.stdin.end();
              
              const chunks = [];
              python.stdout.on('data', chunk => {
                chunks.push(chunk);
              });
              
              python.stderr.on('data', data => {
                console.error('Python error:', data.toString());
              });
              
              python.on('close', code => {
                if (code !== 0) {
                  res.statusCode = 500;
                  res.end('Error generating flowchart');
                  return;
                }
                
                const pngBuffer = Buffer.concat(chunks);
                res.setHeader('Content-Type', 'image/png');
                res.setHeader('Content-Disposition', 'attachment; filename="flowchart.png"');
                res.end(pngBuffer);
              });
            });
          } else {
            next();
          }
        });
      }
    }
  ],
});
EOF

echo "📝 Creating index.html..."
cat << 'EOF' > index.html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <title>Flowchart Editor</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  </head>
  <body style="margin:0;">
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
EOF

echo "📝 Creating src/main.jsx..."
cat << 'EOF' > src/main.jsx
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App.jsx';
import 'reactflow/dist/style.css';

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
EOF

echo "📝 Creating src/App.jsx..."
cat << 'EOF' > src/App.jsx
import React, {
  useCallback,
  useMemo,
  useState
} from 'react';
import ReactFlow, {
  Background,
  Controls,
  MiniMap,
  addEdge,
  useEdgesState,
  useNodesState
} from 'reactflow';

let idCounter = 1;
const getId = () => `n_${idCounter++}`;

const initialNodes = [
  {
    id: 'root',
    position: { x: 0, y: 0 },
    data: { label: '' },
    type: 'default'
  }
];

const initialEdges = [];

// Build JSON for Python flowchart renderer
function buildJson(nodes, edges) {
  if (!nodes.length) {
    return {
      total_columns: 95,
      col_width: 0.15,
      row_height: 1.2,
      row_gap: 0.6,
      output_file: "flowchart.png",
      rows: [],
      special_children: [],
      edges: []
    };
  }

  const nodeMap = {};
  nodes.forEach(n => (nodeMap[n.id] = n));

  const childrenMap = {};
  const parentCount = {};
  nodes.forEach(n => {
    childrenMap[n.id] = [];
    parentCount[n.id] = 0;
  });

  edges.forEach(e => {
    childrenMap[e.source].push(e);
    parentCount[e.target] = (parentCount[e.target] || 0) + 1;
  });

  // Root = node with no incoming edges
  let rootId = nodes[0].id;
  for (const [id, cnt] of Object.entries(parentCount)) {
    if (cnt === 0) {
      rootId = id;
      break;
    }
  }

  // BFS assign depth and stable slot positions
  const depthMap = {};
  const slotMap = {}; // Stable position within each depth level
  depthMap[rootId] = 0;
  slotMap[rootId] = 0; // Root is at slot 0
  const queue = [rootId];

  while (queue.length) {
    const cur = queue.shift();
    const depth = depthMap[cur];
    const slot = slotMap[cur];
    const childs = childrenMap[cur] || [];
    
    // Sort children by x position to maintain left-to-right order
    const sortedChildren = childs.slice().sort((a, b) => {
      const nodeA = nodeMap[a.target];
      const nodeB = nodeMap[b.target];
      return nodeA.position.x - nodeB.position.x;
    });
    
    sortedChildren.forEach((e, idx) => {
      const cid = e.target;
      if (depthMap[cid] == null) {
        depthMap[cid] = depth + 1;
        // Binary tree slot assignment: left child = 2*parent, right = 2*parent + 1
        slotMap[cid] = slot * 2 + idx;
        queue.push(cid);
      }
    });
  }

  // Group nodes by depth
  const depthNodes = {};
  Object.entries(depthMap).forEach(([id, depth]) => {
    if (!depthNodes[depth]) depthNodes[depth] = [];
    depthNodes[depth].push({ id, slot: slotMap[id] });
  });

  const sortedDepths = Object.keys(depthNodes)
    .map(Number)
    .sort((a, b) => a - b);

  const rows = [];

  sortedDepths.forEach((depth, idx) => {
    let branchFromPrev = false;
    if (idx > 0) {
      const prevDepth = sortedDepths[idx - 1];
      const prevNodes = depthNodes[prevDepth];
      // if any node at previous level has >= 2 children, branch
      branchFromPrev = prevNodes.some(
        ({id}) => (childrenMap[id] || []).length >= 2
      );
    }

    // Sort nodes by slot position
    const sortedNodes = depthNodes[depth].slice().sort((a, b) => a.slot - b.slot);

    rows.push({
      branch_from_prev: branchFromPrev,
      nodes: sortedNodes.map(({id, slot}) => {
        const node = nodeMap[id];
        const label = node?.data?.label || "";
        const entry = { id, label, slot }; // Include slot in output
        if (label.trim().toLowerCase() === 'end') entry.color = "lightcoral";
        if (id === rootId && label.trim().toLowerCase() !== 'end') entry.color = "lightblue";
        return entry;
      })
    });
  });

  const edgesJson = edges.map(e => {
    const obj = { from: e.source, to: e.target };
    if (e.label) obj.label = e.label;
    return obj;
  });

  // special_children: auto left/right for 2-child parents
  const specialChildren = [];
  for (const [pid, list] of Object.entries(childrenMap)) {
    if (list.length === 2) {
      // Sort by x position to determine left/right
      const sorted = list.slice().sort((a, b) => {
        const nodeA = nodeMap[a.target];
        const nodeB = nodeMap[b.target];
        return nodeA.position.x - nodeB.position.x;
      });
      
      specialChildren.push({
        child: sorted[0].target,
        parent: pid,
        side: "left"
      });
      specialChildren.push({
        child: sorted[1].target,
        parent: pid,
        side: "right"
      });
    }
  }

  return {
    total_columns: 95,
    col_width: 0.15,
    row_height: 1.2,
    row_gap: 0.6,
    output_file: "flowchart.png",
    rows,
    special_children: specialChildren,
    edges: edgesJson
  };
}

export default function App() {
  const [nodes, setNodes, onNodesChange] = useNodesState(initialNodes);
  const [edges, setEdges, onEdgesChange] = useEdgesState(initialEdges);
  const [selectedNodeId, setSelectedNodeId] = useState("root");
  const [labelInput, setLabelInput] = useState('');
  const [exportedJson, setExportedJson] = useState("");
  const [isGenerating, setIsGenerating] = useState(false);

  const onConnect = useCallback(
    params => setEdges(eds => addEdge(params, eds)),
    []
  );

  const onNodeClick = useCallback((_, node) => {
    setSelectedNodeId(node.id);
    setLabelInput(node.data?.label || "");
  }, []);

  const selectedNode = useMemo(
    () => nodes.find(n => n.id === selectedNodeId),
    [nodes, selectedNodeId]
  );

  const updateSelectedLabel = useCallback(
    (value) => {
      setLabelInput(value);
      setNodes(nds =>
        nds.map(n =>
          n.id === selectedNodeId
            ? { ...n, data: { ...n.data, label: value } }
            : n
        )
      );
    },
    [selectedNodeId, setNodes]
  );

  const addChild = useCallback(
    (isDecision = false) => {
      if (!selectedNode) return;
      const parent = selectedNode;
      const baseX = parent.position.x;
      const baseY = parent.position.y + 120;

      if (!isDecision) {
        const newId = getId();
        const newNode = {
          id: newId,
          position: { x: baseX, y: baseY },
          data: { label: "New node" },
          type: "default"
        };
        setNodes(nds => nds.concat(newNode));
        setEdges(eds =>
          eds.concat({
            id: `e_${parent.id}_${newId}`,
            source: parent.id,
            target: newId
          })
        );
        setSelectedNodeId(newId);
        setLabelInput("New node");
      } else {
        const leftId = getId();
        const rightId = getId();

        const leftNode = {
          id: leftId,
          position: { x: baseX - 150, y: baseY },
          data: { label: "No branch" },
          type: "default"
        };
        const rightNode = {
          id: rightId,
          position: { x: baseX + 150, y: baseY },
          data: { label: "Yes branch" },
          type: "default"
        };

        setNodes(nds => nds.concat(leftNode, rightNode));
        setEdges(eds =>
          eds.concat(
            {
              id: `e_${parent.id}_${leftId}`,
              source: parent.id,
              target: leftId,
              label: "No"
            },
            {
              id: `e_${parent.id}_${rightId}`,
              source: parent.id,
              target: rightId,
              label: "Yes"
            }
          )
        );
      }
    },
    [selectedNode, setNodes, setEdges]
  );

  const deleteSelectedNode = useCallback(() => {
    if (!selectedNode) return;
    const id = selectedNode.id;

    // Check if node has children
    const hasChildren = edges.some(e => e.source === id);
    if (hasChildren) {
      alert("Cannot delete node with children. Delete child nodes first.");
      return;
    }

    setNodes(nds => nds.filter(n => n.id !== id));
    setEdges(eds => eds.filter(e => e.source !== id && e.target !== id));

    const remaining = nodes.filter(n => n.id !== id);
    if (remaining.length > 0) {
      setSelectedNodeId(remaining[0].id);
      setLabelInput(remaining[0].data?.label || "");
    } else {
      setSelectedNodeId(null);
      setLabelInput("");
    }
  }, [selectedNode, nodes, edges, setNodes, setEdges]);

  const exportJson = useCallback(async () => {
    const json = buildJson(nodes, edges);
    const pretty = JSON.stringify(json, null, 2);
    
    // Show JSON in textarea
    setExportedJson(pretty);
    
    // Send to backend to generate and download PNG
    setIsGenerating(true);
    try {
      const response = await fetch('/api/generate-flowchart', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: pretty,
      });

      if (!response.ok) {
        throw new Error('Failed to generate flowchart');
      }

      // Download the PNG
      const blob = await response.blob();
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = 'flowchart.png';
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      URL.revokeObjectURL(url);
    } catch (error) {
      console.error('Error:', error);
      alert('Error generating flowchart. Make sure Python 3 and matplotlib are installed.');
    } finally {
      setIsGenerating(false);
    }
  }, [nodes, edges]);

  const resetChart = useCallback(() => {
    idCounter = 1;
    setNodes(initialNodes);
    setEdges(initialEdges);
    setSelectedNodeId("root");
    setLabelInput('');
    setExportedJson("");
  }, [setNodes, setEdges]);

  return (
    <div style={{ display: "flex", height: "100vh", fontFamily: "sans-serif" }}>
      <div style={{ flex: 3 }}>
        <ReactFlow
          nodes={nodes}
          edges={edges}
          onNodesChange={onNodesChange}
          onEdgesChange={onEdgesChange}
          onConnect={onConnect}
          onNodeClick={onNodeClick}
          fitView
        >
          <MiniMap />
          <Controls />
          <Background gap={16} />
        </ReactFlow>
      </div>

      <div
        style={{
          flex: 1,
          borderLeft: "1px solid #ddd",
          padding: "0.75rem",
          display: "flex",
          flexDirection: "column",
          gap: "0.75rem",
          overflow: "auto"
        }}
      >
        <h3 style={{ marginTop: 0 }}>Node Inspector</h3>

        {selectedNode ? (
          <>
            <div>
              <div style={{ fontSize: "0.8rem", opacity: 0.7 }}>Selected ID</div>
              <div
                style={{
                  fontSize: "0.9rem",
                  fontFamily: "monospace",
                  wordBreak: "break-all"
                }}
              >
                {selectedNode.id}
              </div>
            </div>

            <label style={{ display: "block", fontSize: "0.9rem" }}>
              Label
              <textarea
                value={labelInput}
                onChange={e => updateSelectedLabel(e.target.value)}
                rows={4}
                style={{
                  width: "100%",
                  marginTop: "0.25rem",
                  fontFamily: "inherit",
                  fontSize: "0.9rem"
                }}
              />
            </label>

            <div style={{ display: "flex", gap: "0.5rem", marginTop: "0.5rem", flexWrap: "wrap" }}>
              <button onClick={() => addChild(false)}>Add Child</button>
              <button onClick={() => addChild(true)}>Add Decision (Yes/No)</button>
              <button onClick={deleteSelectedNode}>Delete Selected Node</button>
            </div>
          </>
        ) : (
          <p>No node selected.</p>
        )}

        <hr />

        <div style={{ display: "flex", gap: "0.5rem" }}>
          <button onClick={exportJson} disabled={isGenerating}>
            {isGenerating ? 'Generating...' : 'Export PNG'}
          </button>
          <button onClick={resetChart}>Reset Chart</button>
        </div>

        <p style={{ fontSize: "0.8rem", marginTop: "0.5rem", opacity: 0.7 }}>
          Click "Export PNG" to generate and download the flowchart image.
          The JSON structure will appear below for reference.
        </p>

        <textarea
          readOnly
          value={exportedJson}
          placeholder="JSON will appear here after you click Export PNG."
          style={{
            width: "100%",
            height: "260px",
            marginTop: "0.5rem",
            fontFamily: "monospace",
            fontSize: "0.8rem",
            whiteSpace: "pre"
          }}
        />
      </div>
    </div>
  );
}
EOF

echo "📝 Creating generate_flowchart.py..."
cat << 'EOF' > generate_flowchart.py
#!/usr/bin/env python3
import json
import sys
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as patches
import textwrap

def create_flowchart_image(cfg):
    """Generate flowchart image from config"""
    total_columns = cfg.get("total_columns", 95)
    col_width = cfg.get("col_width", 0.15)
    row_height = cfg.get("row_height", 1.2)
    row_gap = cfg.get("row_gap", 0.6)

    rows = cfg["rows"]
    edges_cfg = cfg["edges"]
    special_children_cfg = cfg.get("special_children", [])

    num_rows = len(rows)

    # Compute branching per row & widths (same as before - keeps *2 + 1 logic)
    widths = [total_columns]
    branch_from_prev = [False] * num_rows
    
    for r in range(1, num_rows):
        branch = rows[r].get("branch_from_prev", True)
        branch_from_prev[r] = branch
        if branch:
            widths.append((widths[r - 1] - 1) // 2)
        else:
            widths.append(widths[r - 1])

    def get_width(row):
        return widths[row]

    # Map node ids to (row, slot) and collect node metadata
    node_meta = {}
    for row_idx, row in enumerate(rows):
        node_list = row["nodes"]
        for n in node_list:
            nid = n["id"]
            node_meta[nid] = {
                "row": row_idx,
                "slot": n["slot"],  # Use stable slot instead of position in array
                "label": n["label"],
                "color": n.get("color", "white"),
            }

    # Build parent-child relationship for single child centering
    parent_map = {}
    children_count = {}
    for e in edges_cfg:
        parent_id = e["from"]
        child_id = e["to"]
        parent_map[child_id] = parent_id
        children_count[parent_id] = children_count.get(parent_id, 0) + 1
    
    # Special child alignment
    special_children = {}
    for sc in special_children_cfg:
        child_id = sc["child"]
        parent_id = sc["parent"]
        side = sc["side"]
        special_children[child_id] = (parent_id, side)
    
    # Normalize slot positions per row to fit within available columns
    def get_normalized_position(row, slot, width):
        """Calculate start column, normalizing slots to fit in available space"""
        # Find min and max slots for this row
        row_data = rows[row]
        slots = [n["slot"] for n in row_data["nodes"]]
        min_slot = min(slots)
        max_slot = max(slots)
        
        # If all nodes at same slot, center it
        if min_slot == max_slot:
            return (total_columns - width) / 2
        
        # Normalize slot to position within available columns
        # Each node needs (width + 1) columns, but last node only needs width
        total_needed = (max_slot - min_slot + 1) * (width + 1) - 1
        
        if total_needed <= total_columns:
            # All nodes fit - use slot-based positioning centered in canvas
            offset = (total_columns - total_needed) / 2
            return offset + (slot - min_slot) * (width + 1)
        else:
            # Nodes would overflow - compress spacing proportionally
            available = total_columns - width
            slot_range = max_slot - min_slot
            return (slot - min_slot) * (available / slot_range)

    # Cache for computed positions to maintain alignment
    position_cache = {}
    
    def get_start_col(row, node_id, node_slot):
        """Calculate start column using stable slot position"""
        # Return cached position if already computed
        if node_id in position_cache:
            return position_cache[node_id]
        
        width = get_width(row)
        
        # Check if this node has special alignment (2-child decision branches)
        sc = special_children.get(node_id)
        if sc is not None:
            parent_id, side = sc
            parent = node_meta[parent_id]
            parent_row = parent["row"]
            parent_width = get_width(parent_row)
            
            # Get parent's actual cached position (or compute it)
            parent_start = get_start_col(parent_row, parent_id, parent["slot"])

            if side == "left":
                result = parent_start
            elif side == "right":
                result = parent_start + parent_width - width
            else:
                result = get_normalized_position(row, node_slot, width)
            
            position_cache[node_id] = result
            return result
        
        # Check if this is a single child - center it under parent
        if node_id in parent_map:
            parent_id = parent_map[node_id]
            if children_count.get(parent_id, 0) == 1:
                # Single child - center under parent
                parent = node_meta[parent_id]
                parent_row = parent["row"]
                parent_width = get_width(parent_row)
                parent_start = get_start_col(parent_row, parent_id, parent["slot"])
                parent_center = parent_start + parent_width / 2
                child_center = width / 2
                result = parent_center - child_center
                position_cache[node_id] = result
                return result

        # Use normalized slot position for other nodes
        result = get_normalized_position(row, node_slot, width)
        position_cache[node_id] = result
        return result

    # Figure setup
    fig_width = total_columns * col_width + 1
    fig_height = num_rows * (row_height + row_gap) + 1

    fig, ax = plt.subplots(1, 1, figsize=(fig_width, fig_height))
    ax.set_xlim(-0.5, total_columns * col_width + 0.5)
    ax.set_ylim(-0.5, num_rows * (row_height + row_gap) + 0.5)
    ax.axis("off")

    # Draw nodes
    node_positions = {}
    for nid, meta in node_meta.items():
        row = meta["row"]
        slot = meta["slot"]
        label = meta["label"]
        color = meta["color"]

        width = get_width(row)
        start_col = get_start_col(row, nid, slot)

        x = start_col * col_width
        y = (num_rows - row - 1) * (row_height + row_gap)
        w = width * col_width

        rect = patches.FancyBboxPatch(
            (x, y), w, row_height,
            boxstyle="round,pad=0.02,rounding_size=0.1",
            facecolor=color, edgecolor="black", linewidth=1.5
        )
        ax.add_patch(rect)

        fontsize = max(6, min(11, width * 0.3))
        chars_per_line = max(10, int(width * 2))
        wrapped_text = "\n".join(textwrap.wrap(label, width=chars_per_line))
        
        ax.text(x + w / 2, y + row_height / 2, wrapped_text,
                ha="center", va="center", fontsize=fontsize)

        node_positions[nid] = {
            "center_x": x + w / 2,
            "top": y + row_height,
            "bottom": y
        }

    # Draw edges
    for e in edges_cfg:
        from_id = e["from"]
        to_id = e["to"]
        label = e.get("label")

        from_node = node_positions[from_id]
        to_node = node_positions[to_id]

        mid_y = (from_node["bottom"] + to_node["top"]) / 2

        ax.plot(
            [from_node["center_x"], from_node["center_x"]],
            [from_node["bottom"], mid_y],
            "k-", linewidth=1.2
        )
        ax.plot(
            [from_node["center_x"], to_node["center_x"]],
            [mid_y, mid_y],
            "k-", linewidth=1.2
        )
        ax.annotate(
            "",
            xy=(to_node["center_x"], to_node["top"]),
            xytext=(to_node["center_x"], mid_y),
            arrowprops=dict(arrowstyle="->", color="black", lw=1.2)
        )

        if label:
            label_x = (from_node["center_x"] + to_node["center_x"]) / 2
            ax.text(
                label_x, mid_y + 0.1, label,
                ha="center", va="bottom", fontsize=8
            )

    plt.tight_layout()
    
    # Output to stdout as binary
    plt.savefig(
        sys.stdout.buffer,
        format='png',
        dpi=200,
        bbox_inches="tight",
        facecolor="white",
        edgecolor="none"
    )
    plt.close(fig)

if __name__ == "__main__":
    cfg = json.load(sys.stdin)
    create_flowchart_image(cfg)
EOF

chmod +x generate_flowchart.py

echo "📦 Installing Python dependencies..."
pip install matplotlib

echo "📦 Installing Node dependencies..."
npm install

echo ""
echo "✅ Setup complete!"
echo ""
echo "To run the app:"
echo "  cd ~/flowchart-builder"
echo "  npm run dev"
echo ""
