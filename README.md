# Flowchart Builder - Complete Setup Guide

A React-based flowchart editor that exports directly to PNG using Python/matplotlib.

---

## 📋 Prerequisites

- Ubuntu/Linux
- Python 3.8+
- Node.js 18+
- npm

---

## 🚀 Complete Setup Instructions

### 1. Install System Dependencies (if needed)

```bash
sudo apt update
sudo apt install -y nodejs npm python3 python3-pip python3-venv wget
```

### 2. Create and Activate Python Virtual Environment

```bash
cd ~
python3 -m venv venv
source venv/bin/activate
```

**Note:** You'll need to activate the venv every time you want to run the app.

### 3. Download and Run the Setup Script

```bash
# Make sure you're in the venv (you should see (venv) in your prompt)

# Download the setup script
wget https://raw.githubusercontent.com/PentestPlaybook/flowchart-builder/refs/heads/main/flowchart-builder-setup.sh

# Make it executable
chmod +x flowchart-builder-setup.sh

# Run the setup
./flowchart-builder-setup.sh
```

This script will:
- Create `~/flowchart-builder/` directory
- Generate all project files (package.json, vite.config.js, React components, Python script)
- Install matplotlib in your venv
- Install npm dependencies

### 4. Run the Application

```bash
cd ~/flowchart-builder
npm run dev
```

You should see:
```
VITE v5.4.10 ready in XXX ms

  ➜  Local:   http://localhost:5173/
  ➜  Network: use --host to expose
```

### 5. Open in Browser

Navigate to: **http://localhost:5173/**

---

## 🎯 Using the Editor

1. **Build your flowchart:**
   - Click nodes to select them
   - Edit labels in the right panel
   - Use "Add Child" to add a single child node
   - Use "Add Decision (Yes/No)" to add a branching decision
   - Delete nodes (must have no children)

2. **Export:**
   - Click "Export PNG" button
   - PNG downloads automatically as `flowchart.png`
   - JSON structure appears in textarea for reference

---

## 🔄 Subsequent Uses

Every time you want to run the app:

```bash
# 1. Activate venv
cd ~
source venv/bin/activate

# 2. Start the app
cd ~/flowchart-builder
npm run dev
```

**To stop the server:** Press `Ctrl+C`

---

## 📁 Project Structure

```
~/flowchart-builder/
├── package.json              # Node dependencies
├── vite.config.js           # Vite config with API endpoint
├── index.html               # HTML entry point
├── generate_flowchart.py    # Python script for PNG generation
├── src/
│   ├── main.jsx            # React entry point
│   └── App.jsx             # Main React component
└── node_modules/           # Installed npm packages (auto-generated)
```

---

## 🛠️ How It Works

1. **Frontend:** React + ReactFlow for visual editing
2. **Backend:** Vite middleware intercepts `/api/generate-flowchart`
3. **Processing:** Spawns Python subprocess, pipes JSON → PNG
4. **Output:** Browser downloads PNG, displays JSON

---

## 🧹 Cleanup

To completely remove the project:

```bash
rm -rf ~/flowchart-builder
```

To deactivate venv:

```bash
deactivate
```

---

## 🐛 Troubleshooting

### Error: `matplotlib` not found
Make sure venv is activated:
```bash
source ~/venv/bin/activate
pip install matplotlib
```

### Port 5173 already in use
Kill existing process:
```bash
lsof -ti:5173 | xargs kill -9
```

### Python script fails
Check Python3 is available:
```bash
which python3
python3 --version
```

### Download fails
If `wget` is not available, use `curl` instead:
```bash
curl -O https://raw.githubusercontent.com/PentestPlaybook/flowchart-builder/refs/heads/main/flowchart-builder-setup.sh
```

---

## 📝 Notes

- The app runs on a single Vite dev server (port 5173)
- No separate backend server needed
- Python script runs as a subprocess when exporting
- JSON still visible in browser for debugging/reference
- Only matplotlib is required (no Flask, no CORS)
---

Enjoy! 🎨
