// Desk lamp controller case: NodeMCU v2 + HLK-LD2410 + 5V power split.
// Measure your parts and adjust the values below before printing.
// part = "box" | "lid" | "both"

part = "both";

wall = 2;
floor_t = 2;
radar_wall = 1.2;   // thin, plastic only in front of the radar antenna
clear = 0.4;

mcu_l = 48;         // NodeMCU v2 board length (some are 58)
mcu_w = 26;         // NodeMCU v2 board width (some are 31)
pcb_t = 1.6;
mcu_under = 9;      // header pins below the board
mcu_over = 12;      // ESP shield + dupont connectors above the board

radar_l = 35;
radar_h = 7;
radar_t = 4;        // PCB plus components on the back

splice_l = 24;      // bay for the 5V split and a 10x16mm capacitor lying flat
cable_d = 5;        // USB-in cable and lamp cable
usb_w = 12;
usb_h = 8;

rail_w = 1.5;
rib_t = 1.5;
lip_h = 3;
lip_t = 1.2;
lid_t = 2;

in_w = max(mcu_w, radar_l) + 2 * clear;
in_l = radar_t + clear + rib_t + splice_l + mcu_l + clear;
in_h = mcu_under + pcb_t + mcu_over;

out_l = in_l + 2 * wall;
out_w = in_w + 2 * wall;
out_h = in_h + floor_t;

radar_x = wall;
splice_x = radar_x + radar_t + clear + rib_t;
mcu_x = splice_x + splice_l;
board_z = floor_t + mcu_under;

$fn = 48;

module box() {
    difference() {
        cube([out_l, out_w, out_h]);
        translate([wall, wall, floor_t]) cube([in_l, in_w, in_h + 1]);

        // thin window in front of the radar
        translate([radar_wall, wall, floor_t])
            cube([wall - radar_wall + 0.01, in_w, radar_h + 1]);

        // micro-USB access on the back wall, for recovery flashing only
        translate([out_l - wall - 1, (out_w - usb_w) / 2, board_z + pcb_t - 1])
            cube([wall + 2, usb_w, usb_h]);

        // USB-in on one side, lamp cable on the other, both at the splice bay
        for (y = [-1, out_w - wall - 1])
            translate([splice_x + splice_l / 2, y, floor_t + in_h / 2])
                rotate([-90, 0, 0]) cylinder(d = cable_d, h = wall + 2);
    }

    // rib holding the radar against the front window
    rib_len = radar_l * 0.6;
    translate([radar_x + radar_t + clear, wall + (in_w - rib_len) / 2, floor_t])
        cube([rib_t, rib_len, radar_h * 0.6]);

    // side rails the NodeMCU rests on, header pins hang between them
    rail_reach = (in_w - mcu_w) / 2 + rail_w;
    for (y = [wall, out_w - wall - rail_reach])
        translate([mcu_x, y, floor_t]) cube([mcu_l, rail_reach, mcu_under]);
}

module lid() {
    cube([out_l, out_w, lid_t]);
    translate([wall + clear / 2, wall + clear / 2, lid_t])
        difference() {
            cube([in_l - clear, in_w - clear, lip_h]);
            translate([lip_t, lip_t, -1])
                cube([in_l - clear - 2 * lip_t, in_w - clear - 2 * lip_t, lip_h + 2]);
        }
}

if (part == "box" || part == "both") box();
if (part == "lid" || part == "both") translate([0, out_w + 10, 0]) lid();

echo(str("outer size: ", out_l, " x ", out_w, " x ", out_h + lid_t, " mm"));
