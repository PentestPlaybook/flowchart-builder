import json
import matplotlib.pyplot as plt
import matplotlib.patches as patches
import textwrap


def create_flowchart(config_path="flowchart.json"):
    # -------------------------------------------------------------
    # Load JSON configuration
    # -------------------------------------------------------------
    with open(config_path, "r", encoding="utf-8") as f:
        cfg = json.load(f)

    total_columns = cfg.get("total_columns", 95)
    col_width = cfg.get("col_width", 0.15)
    row_height = cfg.get("row_height", 1.2)
    row_gap = cfg.get("row_gap", 0.6)

    rows = cfg["rows"]          # list of row dicts
    edges_cfg = cfg["edges"]    # list of {from, to, label}
    special_children_cfg = cfg.get("special_children", [])

    num_rows = len(rows)

    # -------------------------------------------------------------
    # Compute branching per row & widths
    # -------------------------------------------------------------
    # row 0 is root width = total_columns
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

    # -------------------------------------------------------------
    # Map node ids to (row, slot) and collect node metadata
    # -------------------------------------------------------------
    node_meta = {}   # id -> dict(row, slot, label, color)

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
    
    # Special child alignment: child_id -> (parent_id, side)
    # side is "left" or "right"
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

    # -------------------------------------------------------------
    # Helpers for positioning
    # -------------------------------------------------------------
    # Cache for computed positions to maintain alignment
    position_cache = {}
    
    def get_start_col(row, node_id, node_slot):
        """Return starting column index in the abstract grid."""
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

    # -------------------------------------------------------------
    # Figure setup
    # -------------------------------------------------------------
    fig_width = total_columns * col_width + 1
    fig_height = num_rows * (row_height + row_gap) + 1

    fig, ax = plt.subplots(1, 1, figsize=(fig_width, fig_height))
    ax.set_xlim(-0.5, total_columns * col_width + 0.5)
    ax.set_ylim(-0.5, num_rows * (row_height + row_gap) + 0.5)
    ax.axis("off")

    # -------------------------------------------------------------
    # Draw nodes
    # -------------------------------------------------------------
    node_positions = {}  # id -> {center_x, top, bottom}

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

    # -------------------------------------------------------------
    # Draw edges
    # -------------------------------------------------------------
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
    plt.savefig(
        cfg.get("output_file", "flowchart.png"),
        dpi=200,
        bbox_inches="tight",
        facecolor="white",
        edgecolor="none"
    )
    print("Flowchart saved")
    print(f"Widths per row: {widths}")


if __name__ == "__main__":
    create_flowchart()
