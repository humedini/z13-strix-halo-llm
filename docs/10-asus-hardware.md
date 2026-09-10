# 10. ASUS hardware control: TDP, fans, battery, lights

## z13ctl

[z13ctl](https://github.com/dahui/z13ctl) by dahui is the control layer for this specific machine. It drives keyboard and lightbar RGB over hidraw, performance profiles and battery limit through `asus-wmi` sysfs, boot sound and panel overdrive through `asus-armoury` firmware attributes, TDP through the `asus-nb-wmi` PPT attributes, and fan curves through the `asus_custom_fan_curve` hwmon. Its protocol knowledge comes from [g-helper](https://github.com/seerge/g-helper) by seerge, the Windows tool for the same hardware.

It is installed by the community setup script. Everything below assumes v1.3.2.

### Rootless

```bash
sudo z13ctl setup
```

writes udev rules granting the `users` group access to every interface z13ctl touches, and installs a small systemd oneshot (`z13ctl-perms.service`) that re-applies permissions at boot. That service exists because `asus_nb_wmi` creates several sysfs attributes late in its probe, after all udev events have fired, so a udev rule alone cannot catch them. After this, every `z13ctl` command works without sudo. Script `10-z13ctl-setup.sh`.

### The daemon

```bash
systemctl --user enable --now z13ctl.socket z13ctl.service
```

Required for custom profiles, autoswitch, and re-applying anything the kernel discards on a profile change. It is a socket-activated user unit.

## TDP

Three limits, all in watts, through `/sys/devices/platform/asus-nb-wmi/ppt_*`:

| | Meaning | Firmware `balanced` | Firmware `performance` | Hardware max |
|---|---|---|---|---|
| PL1 / SPL | sustained | 60 | 70 | 93 (needs `--force` above 75) |
| PL2 / sPPT | short boost | 75 | 86 | 93 |
| PL3 / fPPT | instantaneous | 86 | 86 | 93 |

**The `asus-armoury` interface reads stale values.** `/sys/class/firmware-attributes/asus-armoury/attributes/ppt_*` reported 60/75/86 while the machine was actually running 70/86/86, and later 5/5/5 before the permissions service had initialised the attributes. The `asus-nb-wmi` path is authoritative. This produced a false diagnosis of a TDP regression after a reboot; the verify script now reads both and labels them.

### Profiles

This build uses a z13ctl custom profile rather than a firmware one:

```bash
z13ctl profile --create ai-ac
z13ctl tdp --set 70 --pl2 86 --pl3 86 --profile ai-ac
z13ctl autoswitch --ac ai-ac --battery quiet
z13ctl profile --set ai-ac
```

A custom profile applies TDP itself and **never writes `platform_profile`**, so `z13ctl status` showing `Profile: ai-ac (platform: balanced)` is expected, not a fault. Autoswitch fires on an actual power source change, so the daemon restores the profile at login rather than at boot.

Note that `--pl1/--pl2/--pl3` are overrides on a base `--set`; passing them alone prints the help text and does nothing. That cost one round trip.

### Pushing to 90 W

`z13ctl tdp --set 90 --force` works. z13ctl then **mandates a fan floor** whenever PL1 exceeds 75 W, a curve starting around 49 percent PWM and reaching 100 percent by 85°C, written before the power limit is applied. If that write fails, it refuses to apply the TDP at all. So a 90 W run is loud by design. Measured: 90 W sustained, 84°C, fans at 8500 RPM, no throttling.

## Fans: leave them on firmware auto

This one contradicts the obvious approach.

A custom curve was written with 0 percent below 48°C and a steep ramp above 70°C, intending quieter idle and better cooling under sustained inference. The result, at the same 42°C:

| Mode | Fans |
|---|---|
| Firmware auto, `pwm_enable=2` | **0 RPM** |
| Custom curve, `pwm_enable=1` | **3400 / 3500 RPM** |

The EC ignores a PWM value of 0. Any custom curve puts the fans into a driven mode with a floor, so they never stop. The curve was correctly programmed into the hwmon (verified by reading back every point) and was still louder than doing nothing. **A custom curve can only make idle worse on this chassis.**

There is a second trap. The kernel driver discards custom curves on every power profile change: GNOME power modes, `power-profiles-daemon`, Fn+F5, anything touching `platform_profile`. The daemon re-applies them within seconds, but only if the curve belongs to the profile that is active. A curve saved into the `custom` profile and then an autoswitch to a firmware profile means the curve is simply gone.

The final configuration has no fan curve anywhere. Firmware auto idles at 0 RPM and ramps properly under load.

## Battery charge limit

```bash
z13ctl batterylimit --set 80
```

writes `/sys/class/power_supply/BAT0/charge_control_end_threshold`. **It does not persist.** The value has no firmware backing and resets to 100 on every boot and on resume from suspend.

Script `12-battery-limit-persist.sh` installs a systemd unit that reapplies it on boot and after suspend, waiting up to 30 seconds for the attribute to appear rather than racing the late `asus_nb_wmi` probe. Same timing problem as the permissions service, same solution.

## Keyboard backlight

Two independent paths, and both are needed:

```bash
z13ctl apply --device keyboard --mode static --color FFFFFF --brightness high
busctl --user set-property org.gnome.SettingsDaemon.Power \
  /org/gnome/SettingsDaemon/Power org.gnome.SettingsDaemon.Power.Keyboard Brightness i 100
```

The first sets colour and mode over the Aura HID protocol. The second sets the LED class brightness, which gates whether anything lights at all. `/sys/class/leds/asus::kbd_backlight/brightness` is root only, but GNOME exposes it on the user session bus. There is also a lightbar on `hidraw`, reachable with `--device lightbar`.

## Wi-Fi power save

The MT7925 defaults to power save on. Measured against a wired host on the same LAN with the access point beaconing every 100 ms at DTIM 2: ping averaged 86 ms with 65 ms of jitter and a 159 ms maximum, which is the 200 ms wake cycle showing through. Throughput collapsed to tens of kilobytes per second.

```bash
nmcli connection modify "<ssid>" 802-11-wireless.powersave 2
```

plus a global default in `/etc/NetworkManager/conf.d/`. Script `13-wifi-powersave-off.sh`. After it, ping to the gateway is 2 to 3 ms with 1 ms of jitter. Note that part of the original bad measurement turned out to be the far end's own Wi-Fi; measure against a wired host.

## Hibernate

Blocked, and not by anything fixable in software:

```
SecureBoot enabled
lockdown: none [integrity] confidentiality
```

Under Secure Boot the kernel runs in `integrity` lockdown, which disables hibernation because anyone able to write the swap image could inject code into the resumed kernel. `/sys/power/state` offers only `freeze mem`. Resizing swap does not help. Enabling it means turning Secure Boot off in BIOS, a trade this build did not make. Suspend on battery and never-suspend on AC is the configuration instead.

## Other things GNOME does on a tablet

**The on-screen keyboard**, if enabled, pops up on text focus even with a keyboard attached, because GNOME decides too eagerly that no physical keyboard is present. The tolerable alternative is `always-show-universal-access-status` so the keyboard is two taps away in the top bar without being on by default.

**Terminal copy and paste.** Ubuntu 26.04's default terminal is Ptyxis. `Ctrl+C` has been SIGINT for forty years, so terminals use `Ctrl+Shift+C/V`. If your muscle memory is macOS, `Super` is unused by terminal control codes in the same way `Cmd` is, and Ptyxis will take `<super>c` and `<super>v` in its `org.gnome.Ptyxis.Shortcuts` schema. GNOME's own `<Super>v` binding for the message tray has to be released first. The bindings are single strings, so this replaces `Ctrl+Shift` rather than adding to it.
