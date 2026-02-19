# HapticHelper

## Introduction

HapticHelper is a tool to translate text-based haptic feedback commands from MUDs (based on [NeonMOO](https://neon-moo.space)'s implementation) into WebSocket-based [Intiface™ Central](https://intiface.com) commands. This tool is one part of a rickety chain of nonsense that will allow a MUD to control haptic hardware, in particular sex toys.

This tool should be considered an alpha release; there is no particular guarantee that anything included in this setup will work for your particular situation, and using these tools assumes a level of familiarity with the system you're running your MUD client and other components on.

## What HapticHelper Does

Before anything else, let's consider the chain of action we wish to establish:

  1. An interaction happens between a character and an object in a MUD causing
  2. the MUD server to send a haptic feedback command, which is
  3. translated by the MUD client into a command for HapticHelper, which
  4. **sends a command to Intiface™**, ultimately causing
  5. a haptic feedback device (e.g. buttplug) to activate.

HapticHelper's responsibility in this chain is point 4, although included in `Resources/haptics.tt++` is an example implementation of how point 3 might be implemented.

HapticHelper does not provide haptic feedback against arbitrary MUDs, although client triggers or server support can certaintly be built against HapticHelper as an implementation layer.

## HapticHelper's Interface

In the current version, HapticHelper supports the following commands, all issued through the standard input. All commands are case sensitive. All commands but `STOP` take a device identifier; by default, this is the device index as reported by Intiface™, and depending on the use case it may be required to set it in the Intiface™ Central configuration file. See also [Configuring HapticHelper](#configuring-haptichelper) below for more details on the device index.

```sh
# immediately stop all devices
STOP

# connect the specified device ID, to warm up the connection
CONNECT 1234

# vibrate the specified device with a power of 0.0 <= x <= 1.0, e.g. 0.5
# in the case of devices with multiple motors, all motors are engaged
VIBRATE 1234 0.5

# issue a pulse with the specified device, and the specified power (LOW, MEDIUM, HIGH)
# a pulse is a short burst of vibration, decaying quickly
PULSE 1234 LOW

# issue a heartbeat as above
# a heartbeat are two pulses, close together
HEARTBEAT 1234 MEDIUM
```

HapticHelper does not generally issue output on successful command execution; it does however issue some feedback on unsuccessful or delayed exection. Informational messages start with two question marks, while error messages start with two exclamation points, as do certain important informational messages.

```sh
STOP
!! Stopping all devices.

CONNECT unconfigured-device-name
!! Invalid arguments, expected device index

!! Device `Device Name' disconnected.

CONNECT 4321
?? Device not connected, scanning
?? Connected to device `Device Name', issuing cached commands
```

## Installing HapticHelper

In order to install HapticHelper, Swift version 6.2.3 or later needs to be [installed on the system you want to run it on](https://www.swift.org/install), which is probably the same system as your MUD client. Using `git` and `swift`, download and build the latest version of HapticHelper, and install it into your executable path. The following commands assume a Linux-like system (including most Unixen and macOS), if on Windows, G-d help your soul.

```sh
git clone https://github.com/LexiePlaysFast/HapticHelper
cd HapticHelper
swift build -c release

# assuming ~/bin exists and is in $PATH, adjust as necessary
cp .build/release/HapticHelper ~/bin/HapticHelper
```

You can now launch Intiface™ Central, and then launch HapticHelper to confirm that the connection is good. Intiface™ Central's logging facilities can be used to confirm that the connection takes place as intended. HapticHelper can be closed using `^D` or `^C` when testing concludes.

The current version of HapticHelper will only connect to localhost, port 12345. If your Intiface™ Central is running on a different machine, you can use, as an example, an SSH tunnel to connect, or Intiface™ Central's repeating capabilities.

For Windows users, the `plink.exe` tools available as part of [PuTTY](https://www.chiark.greenend.org.uk/~sgtatham/putty/) should serve this purpose.

```sh
# setting up a tunnel from mud_machine to intiface_machine
ssh -N -L localhost:12345:localhost:12345 user_name@intiface_machine

# setting up a tunnel from intiface_machine to mud_machine
ssh -N -R localhost:12345:localhost:12345 user_name@mud_machine
```

With all of this set up, the MUD client can now run `HapticHelper`. Depending on your client, the exact method will vary, but for users of tintin++ the script file `Resources/haptics.tt++` can be moved somewhere practical and executed as follows:

```
/* `neonmoo' is an example session name, the file needs to be edited for
 * whatever session name you use in tintin++ for your MUD
 */
#run {haptics} {path/to/HapticHelper} {path/to/haptics.tt++} ; #neonmoo
```

This script starts `HapticHelper` in a session named `haptics`, and install triggers to read and transmit `#$#HAPTIC` messages from the MUD to which you are connected. It also `GAG`s these messages, and transmits status and error messages back to the MUD output frame.

Any client that can run an external program in a session can be used for this purpose, tintin++ is used as an example here. For certain clients, an additional wrapper around HapticHelper to make it available on the network may be required. Finding such wrappers is left as an exercise for the reader.

**With all of this set up, you should now be connected through from MUD to buttplug.**

## Configuring HapticHelper

HapticHelper, when starting up, reads the file `~/.config/haptics.conf` for its alias settings. For security and privacy reasons aliases cannot be set during operation, and only the configuration file in the home directory is read; no other files are searched for, accessed, or read during startup.

The configuration file consists of comments (lines beginning with `#`), blank lines, and alias declarations; an example configuration file can be found in `Resources/haptics.conf.example`, containing a very simple configuration suitable for most users.

Each alias line consists of a command name, a source rule, and a destination rule.

The command name is always `alias`. The source rule is either the wildcard rule (`*`) matching any device index, a numerical index, or an object identifier; the object identifier consists of an underscore or a lowercase character a--z, followed by any number of underscores, dashes and lowercase characters. The destination rule is the index rule (`@1`) matching the first available device, a numerical index matching a device index as reported by Intiface™ software, or a device name as reported by Intiface™ software. A device name, unlike an object identifier can contain spaces (and arbitrary unicode characters), although it cannot end with whitespace.

Alias rules are read from top to bottom, and the first matching rule is immediately executed. This means that a file can *effectively* only contain one wildcard alias, as any action will match that rule, and that the wildcard rule has to be the final rule in the config file.

For most users, the provided sample configuration file is likely to cover their use case:

```
# the example rule
alias * @1
```

This example configuration is a wildcard to index rule, routing all commands to the first available device. When using multiple devices, however, this will be inadequate, and the index rule will not actuate all devices. In that case, a config file might look something like this.

```
# advanced example, with specific game objects being routed to specific devices
alias plug Lovense Hush
alias egg Lovense Lush
```

Note that device names here are those reported by Intiface™ software, and the exact format of the names may differ based on your software version and specific devices. Note also that the index rule is not a generic mechanism; there's no `@2`, `@3` and so on. Which device is considered the "first" device might also vary over time, if multiple devices are in play and connections are not stable. Note finally that without the wildcard rule, any numerical indices will be passed through as is. With the example file above, lines with `--` represent action descriptions, not output;

```
PULSE plug LOW
-- Device `Lovense Hush' actuated

PULSE egg LOW
-- Device `Lovense Lush' actuated

PULSE 0 LOW
-- Device with device index 0 actuated
```

## Support

This software is fully offered as-is, but support may be available in the NeonMOO Discord server (as of time of writing Discord is teetering on the edge of viability, but this document will be updated to reflect other avenues of support). GitHub issues may also be fruitful.

## Todo

The system currently *works*, but is some rickety nonsense, and has a lot of points of fragility, as well as assumptions about the quality and nature of the network it operates on. Most of the current TODO points relate to reliability of the system, bringing the communication protocol up to version 4, and making the various tools surrounding the system easier to use, including a `telnet`-based repeater so as to support more MUD clients.

The currently most useable setup for the program is connecting to MUDs via tintin++ from a Linux-based VPS or other similar system via the command line, which while a good way to connect to MUDs is far from universal. A good improvement would be making HapticHelper useable for a wider range of conditions.

## Copying

The code for HapticHelper is Copyright © 2026 Lexie T, and is licensed under the GPL v3.0 or later (see `LICENSE`). `Sources/HapticHelper/WebSocketsClient.swift` is adapted from and substantially quotes example files from the [SwiftNIO](https://github.com/apple/swift-nio) project, and added portions are licensed under the Apache License v2.0. Scripts (such as `Resources/haptics.tt++`), example input/output, and other similar content is released into the Public Domain, or licensed under Creative Commons 0 (CC0) where required by law. This file (excluding the aforementioned) is Copyright © 2026 Lexie T, all rights reserved. Intiface™ is a registered trademark of [Nonpolynomial](https://nonpolynomial.com).
