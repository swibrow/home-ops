# 1RU Raspberry Pi Rack Mount with HDD Support

A parametric 19" rack mount design for hosting multiple Raspberry Pis with 2.5" HDDs mounted underneath.

## Features

- Standard 19" rack width (482.6mm)
- 1RU height (44.45mm)
- Configurable number of Raspberry Pis (default: 4)
- 2.5" HDD mounting positions below each Pi
- Ventilation holes for airflow
- Standard rack ear mounting holes
- **Split printing support** - prints in two halves that bolt together

## Files

| Folder/File | Description |
|-------------|-------------|
| `PiRackFrame19in/` | **Fusion 360** - Open frame design (based on uktricky's 10" design) |
| `PiRackTray19in/` | **Fusion 360** - Solid tray design with HDD support |
| `1ru-pi-rack.scad` | OpenSCAD version of tray design |

## Fusion 360 Usage

1. Copy the desired script folder to your Fusion 360 scripts directory:
   - **Mac**: `~/Library/Application Support/Autodesk/Autodesk Fusion 360/API/Scripts/`
   - **Windows**: `%appdata%\Autodesk\Autodesk Fusion 360\API\Scripts\`
2. Open Fusion 360
3. Go to **Utilities > Scripts and Add-Ins** (or press Shift+S)
4. Select `PiRackFrame19in` or `PiRackTray19in` from the list
5. Click **Run**

### Modifying Parameters

After running the script:
1. Go to **Modify > Change Parameters**
2. Adjust values like `pi_count`, `rack_depth`, etc.
3. Model updates automatically

### Splitting for Print

1. Create a construction plane at the center (X = 241.3mm)
2. Use **Modify > Split Body** to cut the mount in half
3. Export each half as STL

## OpenSCAD Usage (Alternative)

Requires [OpenSCAD](https://openscad.org/)

## Usage

1. Open `1ru-pi-rack.scad` in OpenSCAD
2. Adjust parameters in the Customizer panel
3. Render (F6) and export as STL

### Key Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `pi_count` | 4 | Number of Raspberry Pis (1-4 recommended) |
| `rack_depth` | 200mm | Depth of the mount |
| `enable_hdd` | true | Toggle HDD mounting points |
| `render_part` | "full" | Which part to export: "full", "left", or "right" |

## Split Printing (Recommended)

The full mount is 482mm wide, exceeding most printer beds. Use split printing:

1. Set `render_part = "left"` → Export as `left.stl`
2. Set `render_part = "right"` → Export as `right.stl`
3. Print both halves
4. Join with **3x M4 bolts and nuts** through the center flange

Each half is approximately **241mm wide** and fits standard 250mm+ print beds.

```
┌─────────────────┬─────────────────┐
│   LEFT HALF     │   RIGHT HALF    │
│                 │                 │
│  [Pi 1] [Pi 2]  │  [Pi 3] [Pi 4]  │
│                 │                 │
│            ─────┼─────            │
│            FLANGE (M4 bolts)      │
└─────────────────┴─────────────────┘
```

## Print Settings

| Setting | Recommended |
|---------|-------------|
| Layer Height | 0.2mm |
| Infill | 20-30% |
| Supports | Yes (for rack ears) |
| Material | PETG or ABS |

## Hardware Required

| Component | Quantity | Notes |
|-----------|----------|-------|
| M2.5 x 6mm screws | 16 | Pi mounting (4 per Pi) |
| #6-32 UNC screws | 16 | HDD mounting (4 per HDD) |
| M6 or #10-32 screws | 4-6 | Rack mounting |
| M4 x 20mm bolts | 3 | Joining the halves |
| M4 nuts | 3 | Joining the halves |

## Dimensions

- Total width: 482.6mm (241mm per half)
- Depth: 200mm (adjustable)
- Height: 44.45mm (1RU)
