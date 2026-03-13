// 1RU 19" Rack Mount for Raspberry Pi with 2.5" HDD Support
// Parametric OpenSCAD Design for Home Ops
//
// Print Settings:
//   - Layer height: 0.2mm
//   - Infill: 20-30%
//   - Supports: Yes (for rack ears)
//   - Material: PETG or ABS recommended for heat resistance
//
// Split Printing:
//   - Set render_part to "left" or "right" to export each half
//   - Halves join with M4 bolts through the center flange
//   - Each half is ~241mm wide (fits most printer beds)

/* [Rack Dimensions] */
// 19" rack standard width (mm)
rack_width = 482.6;
// 1RU height (mm) - standard is 44.45mm
rack_height = 44.45;
// Depth of the mount (mm)
rack_depth = 200;
// Wall thickness (mm)
wall_thickness = 3;

/* [Rack Ears] */
// Width of mounting ears (mm)
ear_width = 15.875; // 5/8" standard
// Rack hole diameter (mm) - for M6 or #10-32
rack_hole_diameter = 7;
// Distance between rack mounting holes (mm)
rack_hole_spacing = 15.875; // 5/8" spacing

/* [Raspberry Pi Configuration] */
// Number of Raspberry Pis
pi_count = 4;
// Pi board width (mm)
pi_width = 85;
// Pi board depth (mm)
pi_depth = 56;
// Pi mounting hole spacing X (mm)
pi_hole_x = 58;
// Pi mounting hole spacing Y (mm)
pi_hole_y = 49;
// Pi mounting hole diameter (mm) - M2.5
pi_hole_diameter = 2.7;
// Pi standoff height (mm)
pi_standoff_height = 8;

/* [2.5" HDD Configuration] */
// Enable HDD mounts below Pis
enable_hdd = true;
// HDD width (mm)
hdd_width = 69.85;
// HDD depth (mm)
hdd_depth = 100;
// HDD mounting hole spacing X (mm)
hdd_hole_x = 61.72;
// HDD mounting hole spacing Y (mm) - side holes
hdd_hole_y = 76.2;
// HDD mounting hole diameter (mm) - UNC #6-32
hdd_hole_diameter = 3.5;

/* [Ventilation] */
// Ventilation hole diameter (mm)
vent_hole_diameter = 5;
// Ventilation hole spacing (mm)
vent_spacing = 8;

/* [Split Printing] */
// Which part to render: "full", "left", or "right"
render_part = "full"; // [full, left, right]
// Width of joining flange at center (mm)
flange_width = 15;
// Diameter for joining bolts (M4)
join_bolt_diameter = 4.5;
// Number of joining bolts along depth
join_bolt_count = 3;

/* [Rendering] */
$fn = 32;

// Calculated values
inner_width = rack_width - (2 * ear_width) - (2 * wall_thickness);
pi_spacing = inner_width / pi_count;
center_x = rack_width / 2;

// Main module
module rack_mount() {
    difference() {
        union() {
            // Main tray
            main_tray();

            // Rack ears
            rack_ears();

            // Pi standoffs
            pi_standoffs();

            // HDD standoffs
            if (enable_hdd) {
                hdd_standoffs();
            }

            // Center joining flange (only when split)
            if (render_part != "full") {
                center_flange();
            }
        }

        // Ventilation holes
        ventilation_holes();

        // Rack mounting holes
        rack_mounting_holes();

        // Center flange bolt holes (only when split)
        if (render_part != "full") {
            center_bolt_holes();
        }
    }
}

module main_tray() {
    // Base plate
    translate([ear_width, 0, 0])
        cube([rack_width - (2 * ear_width), rack_depth, wall_thickness]);

    // Side walls
    translate([ear_width, 0, 0])
        cube([wall_thickness, rack_depth, rack_height]);

    translate([rack_width - ear_width - wall_thickness, 0, 0])
        cube([wall_thickness, rack_depth, rack_height]);

    // Front lip
    translate([ear_width, 0, 0])
        cube([rack_width - (2 * ear_width), wall_thickness, rack_height]);

    // Rear lip (lower for cable routing)
    translate([ear_width, rack_depth - wall_thickness, 0])
        cube([rack_width - (2 * ear_width), wall_thickness, rack_height * 0.5]);
}

module rack_ears() {
    // Left ear
    cube([ear_width, wall_thickness, rack_height]);

    // Right ear
    translate([rack_width - ear_width, 0, 0])
        cube([ear_width, wall_thickness, rack_height]);
}

module center_flange() {
    // Vertical flange at the center for joining the two halves
    flange_height = rack_height * 0.7;

    if (render_part == "left") {
        // Left half gets flange on the right side of cut
        translate([center_x, 0, 0])
            cube([flange_width / 2, rack_depth, flange_height]);
    } else if (render_part == "right") {
        // Right half gets flange on the left side of cut
        translate([center_x - flange_width / 2, 0, 0])
            cube([flange_width / 2, rack_depth, flange_height]);
    }
}

module center_bolt_holes() {
    flange_height = rack_height * 0.7;
    bolt_spacing = (rack_depth - 40) / (join_bolt_count - 1);

    for (i = [0 : join_bolt_count - 1]) {
        y_pos = 20 + (i * bolt_spacing);

        // Bolt holes through the flange
        translate([center_x - flange_width, y_pos, flange_height / 2])
            rotate([0, 90, 0])
                cylinder(d = join_bolt_diameter, h = flange_width * 2);
    }
}

module rack_mounting_holes() {
    // Standard rack has 3 holes per 1U spaced 5/8" apart
    hole_positions = [
        rack_height * 0.25,
        rack_height * 0.5,
        rack_height * 0.75
    ];

    for (z = hole_positions) {
        // Left ear holes
        translate([ear_width / 2, -1, z])
            rotate([-90, 0, 0])
                cylinder(d = rack_hole_diameter, h = wall_thickness + 2);

        // Right ear holes
        translate([rack_width - (ear_width / 2), -1, z])
            rotate([-90, 0, 0])
                cylinder(d = rack_hole_diameter, h = wall_thickness + 2);
    }
}

module pi_standoffs() {
    for (i = [0 : pi_count - 1]) {
        x_offset = ear_width + wall_thickness + (pi_spacing * i) + (pi_spacing - pi_width) / 2;
        y_offset = (rack_depth - pi_depth) / 2;

        // Four standoffs per Pi
        pi_standoff_positions = [
            [0, 0],
            [pi_hole_x, 0],
            [0, pi_hole_y],
            [pi_hole_x, pi_hole_y]
        ];

        for (pos = pi_standoff_positions) {
            translate([x_offset + (pi_width - pi_hole_x) / 2 + pos[0],
                       y_offset + (pi_depth - pi_hole_y) / 2 + pos[1],
                       wall_thickness]) {
                difference() {
                    cylinder(d = 6, h = pi_standoff_height);
                    translate([0, 0, -0.1])
                        cylinder(d = pi_hole_diameter, h = pi_standoff_height + 0.2);
                }
            }
        }
    }
}

module hdd_standoffs() {
    standoff_height = 3;

    for (i = [0 : pi_count - 1]) {
        x_offset = ear_width + wall_thickness + (pi_spacing * i) + (pi_spacing - hdd_width) / 2;
        y_offset = (rack_depth - hdd_depth) / 2;

        // HDD bottom mounting holes (4 corners pattern)
        hdd_mount_positions = [
            [3.18, 12], // Front left
            [3.18 + hdd_hole_x, 12], // Front right
            [3.18, 12 + hdd_hole_y], // Rear left
            [3.18 + hdd_hole_x, 12 + hdd_hole_y] // Rear right
        ];

        for (pos = hdd_mount_positions) {
            translate([x_offset + pos[0], y_offset + pos[1], 0]) {
                // Standoff goes down from base (mounting underneath)
                translate([0, 0, -standoff_height])
                difference() {
                    cylinder(d = 8, h = standoff_height);
                    translate([0, 0, -0.1])
                        cylinder(d = hdd_hole_diameter, h = standoff_height + 0.2);
                }
            }
        }
    }
}

module ventilation_holes() {
    // Create ventilation pattern in the base between Pi positions
    for (i = [0 : pi_count - 1]) {
        x_start = ear_width + wall_thickness + (pi_spacing * i) + 15;
        x_end = x_start + pi_spacing - 30;
        y_start = 20;
        y_end = rack_depth - 20;

        for (x = [x_start : vent_spacing : x_end]) {
            for (y = [y_start : vent_spacing : y_end]) {
                translate([x, y, -0.1])
                    cylinder(d = vent_hole_diameter, h = wall_thickness + 0.2);
            }
        }
    }
}

// Split modules for printing
module left_half() {
    intersection() {
        rack_mount();
        translate([-1, -1, -10])
            cube([center_x + flange_width / 2 + 1, rack_depth + 2, rack_height + 20]);
    }
}

module right_half() {
    // Mirror and translate so it sits flat for printing
    translate([-(center_x - flange_width / 2), 0, 0])
    intersection() {
        rack_mount();
        translate([center_x - flange_width / 2, -1, -10])
            cube([center_x + flange_width / 2 + 1, rack_depth + 2, rack_height + 20]);
    }
}

// Render based on selected part
if (render_part == "full") {
    rack_mount();
} else if (render_part == "left") {
    left_half();
} else if (render_part == "right") {
    right_half();
}

// Optional: Show Pi board outlines for visualization (comment out for export)
// %pi_board_visualization();

module pi_board_visualization() {
    color("green", 0.5)
    for (i = [0 : pi_count - 1]) {
        x_offset = ear_width + wall_thickness + (pi_spacing * i) + (pi_spacing - pi_width) / 2;
        y_offset = (rack_depth - pi_depth) / 2;

        translate([x_offset, y_offset, wall_thickness + pi_standoff_height])
            cube([pi_width, pi_depth, 1.6]);
    }
}
