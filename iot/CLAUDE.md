# Home Automation Repository

This repository contains configuration and setup files for home automation.

## Stack

- **Home Assistant** - Core home automation platform
- **ESPHome** - For ESP-based device firmware and configuration
- **zigbee2mqtt** - Zigbee device integration via MQTT

## Hardware

### Switches
- **Aqara H2** - All switches in the home use Aqara H2 smart switches
  - WS-K07E (single rocker)
  - WS-K08E (double rocker)

## Folder Structure

```
home-automation/
├── esphome/
│   ├── devices/          # Device-specific ESPHome configs
│   └── common/           # Shared configs (wifi, sensors, etc.)
├── homeassistant/
│   ├── blueprints/       # Home Assistant automation blueprints
│   └── packages/         # HA packages
├── zigbee2mqtt/
│   └── config/           # zigbee2mqtt configuration files
```

## Blueprints

The rocker blueprints (`aqara_h2_single_rocker`, `aqara_h2_double_rocker`) are the canonical way to wire Aqara H2 switches. Because they expose raw action slots for every button event, they cover standalone control, multi-way setups (secondary switches call service on the master relay), and wireless-button use cases (decoupled switch with service calls in the action slots).

### aqara_h2_single_rocker.yaml
Map WS-K07E (single rocker) button presses to custom actions.

**Inputs:**
- Switch Device - the H2 WS-K07E device (MQTT)
- Action slots: single_up, single_down, double_down, hold_down, release_down

**Notes:**
- Top button toggles relay in control_relay mode, sends events only in decoupled mode
- Bottom button supports single/double/hold/release (enable "Multi click" in zigbee2mqtt for double/hold/release; adds ~1s delay)

### aqara_h2_double_rocker.yaml
Map WS-K08E (double rocker) button presses to custom actions.

**Inputs:**
- Switch Device - the H2 WS-K08E device (MQTT)
- Action slots for left and right sides: single, single_down, double_down, hold_down, release_down per side

**Notes:** Same control_relay vs decoupled behavior as single rocker.

### ikea_styrbar_light_selector.yaml
Control multiple lights with an IKEA STYRBAR (E2001/E2002) remote using labels.

- Left/Right press: cycle lights, selected flashes
- Up/Down press: color temperature (Kelvin)
- Up/Down hold: brightness
- Left/Right hold: confirm selection with long flash

### motion_activated_light.yaml
Run custom actions when motion is detected. Supports multiple motion sensors and any action for both motion detected and motion cleared events.

**Inputs:**
- Motion Sensors - one or more binary_sensors with motion or occupancy device class
- Motion Detected Action - custom action(s) to run when any sensor detects motion
- Motion Cleared Action - custom action(s) to run after all sensors are clear and wait time elapses
- Wait time - seconds to wait after last motion before running cleared action (default: 120)

**Behavior:**
- Triggers when any sensor detects motion
- Waits until ALL sensors are clear before starting the countdown
- Uses `mode: restart` so new motion resets the timer
