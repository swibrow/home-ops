# Button+ V2 — Basement Office panel

[ButtonPlus](https://button.plus) "Button +" **V2** smart wall controller (ESP32-S3, fw `3.1.6-V2`)
mounted in the basement office. Configured **headlessly** over MQTT + HA automations —
no ButtonPlus cloud / browser auto-discovery.

- **Device host:** `http://esp32s3-03a5e4/` (Wi-Fi `haiot`)
- **Hardware:** 1× Large Display V2 (2.8″) + 3× button bars = **6 buttons** (positions 3–8).
  Only pos 3 is used (office light); 4–8 are unconfigured.
- **MQTT broker:** HA Mosquitto add-on `10.101.13.61:1883` (`homeassistant.iot`),
  user **`buttonplus`** (a dedicated HA user — the add-on authenticates MQTT against HA accounts).
  The password is **not** in this repo; it lives only as the HA user's credential.

## Files

| File | What |
|------|------|
| `office-device-config.json` | The device layout (buttons + display items + broker). POST to the device. Password redacted. |
| `office.yaml` | HA package: button-press action + the publisher that feeds the screen. |

## What it shows / does

**Top screen** (editorial layout, yellow labels + white values):

```
Office
HH:MM              Inside  22.6 °C
Today
[weather icon]  23 °C
Humidity 63%       Status Occupied
```

**Button (pos 3):** top-label "Light" + bulb icon → toggles `switch.0x7c2c67fffe687db8`;
the front LED glows green while the light is on.

## MQTT topics (broker `buttonplus`, base `buttonplus/office`)

| Topic | Dir | Meaning |
|-------|-----|---------|
| `…/light/click` | device → HA | button press (`click`) |
| `…/light/led`   | HA → device | `on`/`off` LED feedback (eventtype 14) |
| `…/loc` `…/today` | HA → device | static labels (`Office`, `Today`) |
| `…/time`        | HA → device | `HH:MM` clock (native clock feed renders blank, so HA drives it) |
| `…/temp` `…/humidity` `…/outdoor` | HA → device | raw numbers (unit rendered by the display item) |
| `…/occ`         | HA → device | `Occupied`/`Empty` |
| `…/icon/weather`| HA → device | weather SVG, dynamic by condition (eventtype 46) |

## Apply

**Device config** (POST the JSON, with the real password substituted):

```bash
jq '.brokers[0].password="<buttonplus-password>"' office-device-config.json \
  | curl -s -X POST http://esp32s3-03a5e4/configsave \
      -H 'Content-Type: application/json' --data-binary @-
# applies live; no reboot needed
```

**HA automations:** include `office.yaml` as an HA package, or recreate via the config API
(live copies exist as automation ids `bp_office_light` / `bp_office_pub`). After load,
trigger `bp_office_pub` once (or wait a minute) to populate the retained topics.

## Gotchas (learned the hard way)

- **`/configsave` renumbers `displayitemid` sequentially** by array order — never target an
  item by id across saves; match by topic.
- **Icons on the display** work only via the `displaysvg` event type (46), published over MQTT
  — a static `svg` field on a display item is stripped (only *buttons* keep `svg`). Use sparingly.
- **Buttons** are top-label + (icon **XOR** body text), never both.
- **Native clock** (`system/datetime/amsterdam`) renders blank → HA publishes `…/time`.
- **Hide the IP/system bar:** `core.statusbar` = `0` hidden / `1` top / `2` bottom.
- Layout is a **100×100 grid**; final pixel positioning is iterative — the configurator's
  simulator differs slightly from the real screen.
