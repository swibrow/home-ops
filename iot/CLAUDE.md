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
│   ├── automations/      # synced with HA by scripts/ha.py
│   ├── scripts/          # synced
│   ├── helpers/<domain>/ # synced (input_*, counter, timer, schedule)
│   ├── dashboards/       # synced (storage-mode dashboard configs)
│   ├── blueprints/       # pushed by scripts/ha.py, never pulled
│   ├── packages/         # YAML-only config (influxdb, template lights), copied to the host by hand
│   └── .ha-state.json    # last-synced hash per item, commit it with the files
├── zigbee2mqtt/
│   └── config/           # zigbee2mqtt configuration files
```

## Changing Home Assistant config

HA's own storage is live and stays editable in the UI; `iot/homeassistant/` mirrors it. Never change
automations, scripts, helpers or dashboards through the API or UI without going through these files, and
don't add new ones to `packages/` (only things the UI cannot hold go there).

1. `git pull`, then `./scripts/ha.py pull` to pick up UI edits not yet on main.
2. Edit or add files. Automations need an `id` and are named after their entity (`alias` slug); scripts
   are keyed by filename; helpers by `id` under their domain directory. Deleting a file deletes the item.
3. `./scripts/ha.py diff`, then `./scripts/ha.py push` (optionally with paths). Push refuses an item edited
   in HA since the last sync; pull first rather than `--force`. It rewrites each file with HA's
   normalized version, so re-read a file after pushing it.
4. Commit the files together with `.ha-state.json`.

Auth: `HA_TOKEN`, or `HOME_ASSISTANT_TOKEN` locally. `HA_URL` defaults to `http://homeassistant.iot:8123`
(`ha.wibrow.dev` resolves to an address Python cannot reach from the laptop). Blueprints reload their
automations or scripts on push. UI edits reach git through `.github/workflows/ha-pull.yaml`: hourly it
pulls and opens or updates a `ha-sync` PR set to auto-merge.

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
- Ignore stuck sensors after - minutes a sensor may stay on without reporting before it counts as clear (default: 60, 0 disables)

**Behavior:**
- Triggers when any sensor detects motion
- Waits until ALL sensors are clear before starting the countdown
- Uses `mode: restart` so new motion resets the timer

### water_schedule.yaml
Open a water valve on a schedule for a fixed duration, then close it. Built for a Sonoff smart water valve exposed as a `switch` via zigbee2mqtt, but works with any switch/valve entity.

**Inputs:**
- Water Valve - the switch/valve entity to control
- Start Time - time of day to start watering
- Watering Days - weekdays to run (multi-select)
- Watering Duration - how long to keep the valve open
- Skip Condition (optional) - skip watering when true (rain sensor, forecast, soil moisture)
- Enable Toggle (optional) - `input_boolean` that must be on for the schedule to run

**Behavior:**
- Triggers at the start time, checks weekday + enable toggle + skip condition, then opens the valve, waits the duration, and closes it
- Uses `mode: restart`; if HA restarts mid-watering the run is cancelled and the valve stays open (use a hardware auto-off timer or a separate safety automation if needed)
