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

### aqara_h2_two_way_switch.yaml
Multi-way switch setup for Aqara H2 devices. One master switch controls the relay, secondary switches control it wirelessly.

**Setup:**
- Master switch: Default mode (control_relay)
- Secondary switches: Set to decoupled mode in zigbee2mqtt

**Inputs:**
- Master Switch Entity - the relay switch
- Secondary Device 1-3 - device picker (up to 3 secondary devices)
- Secondary Actions 1-3 - actions per device (allows different buttons per switch)
- MQTT Base Topic - default: zigbee2mqtt

**Supports:**
- WS-K07E (single rocker): single_up, single_down, double_down, hold_down
- WS-K08E (double rocker): single_left/right, single_left/right_down, double/hold variants
- Configurable number of secondary switches

### aqara_h2_wireless_button.yaml
Use an Aqara H2 switch as a wireless button to control any entity.

**Setup:**
- Switch: Set to decoupled mode in zigbee2mqtt
- Enable "Flip indicator light" for LED sync

**Inputs:**
- Button Device - the H2 switch
- Button Actions - which presses trigger control
- Target Entity - entity to toggle (light, switch, etc.)
- Sync LED - keep LED in sync with target state
- MQTT Base Topic - default: zigbee2mqtt

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

**Use case:** Flexible motion automations - turn on lights, activate scenes, control multiple devices, adjust brightness, etc.

### aqara_h2_button_actions.yaml
Map Aqara H2 button presses to custom actions. Supports both single and double rocker models.

**Inputs:**
- Switch Device - the H2 switch (device picker)
- Action selectors for each button:
  - WS-K07E: single_up, single_down, double_down, hold_down, release_down
  - WS-K08E: single/double/hold/release for left_up, left_down, right_up, right_down

**Use case:** Complex automations where each button does something different (dimming, scenes, etc.)
