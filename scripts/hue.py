#!/usr/bin/env python3
"""Direct Hue BLE control. The dashboard uses newline-delimited JSON over stdio."""
import argparse
import asyncio
import json
from pathlib import Path
import re
import signal
import struct
import sys

HUE_SERVICE = "0000fe0f-0000-1000-8000-00805f9b34fb"
LIGHT_SERVICE = "932c32bd-0000-47a2-835a-a8d455b859dd"
POWER = "932c32bd-0002-47a2-835a-a8d455b859dd"
BRIGHTNESS = "932c32bd-0003-47a2-835a-a8d455b859dd"
TEMPERATURE = "932c32bd-0004-47a2-835a-a8d455b859dd"
COLOR = "932c32bd-0005-47a2-835a-a8d455b859dd"
MODEL = "00002a24-0000-1000-8000-00805f9b34fb"
SETTLE_SECONDS = 0.6  # The lamp fades; immediate reads can return intermediate values.
POLL_SECONDS = 10
MAX_RETRY_SECONDS = 60


def address(value):
    if not isinstance(value, str) or not re.fullmatch(r"(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}", value):
        raise ValueError("Select a lamp with a valid Bluetooth address.")
    return value.upper()


def integer(value, minimum, maximum):
    if type(value) is not int or not minimum <= value <= maximum:
        raise ValueError(f"Expected a whole number between {minimum} and {maximum}.")
    return value


def color_bytes(value):
    """Convert sRGB to CIE xy and two little-endian unsigned 16-bit values."""
    if not isinstance(value, str) or not re.fullmatch(r"#[0-9a-fA-F]{6}", value):
        raise ValueError("Use a color in #RRGGBB format.")
    channels = [int(value[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    r, g, b = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    x = 0.664511 * r + 0.154324 * g + 0.162028 * b
    y = 0.283881 * r + 0.668433 * g + 0.047685 * b
    z = 0.000088 * r + 0.072310 * g + 0.986039 * b
    total = x + y + z
    if total == 0:
        raise ValueError("Black has no light color. Use Turn off instead.")
    return struct.pack("<HH", round(x / total * 65535), round(y / total * 65535))


def setting(command):
    op, value = command.get("op"), command.get("value")
    if op == "power":
        if type(value) is not bool:
            raise ValueError("Power must be true or false.")
        return POWER, bytes([int(value)])
    if op == "brightness":
        return BRIGHTNESS, bytes([max(1, round(integer(value, 1, 100) * 254 / 100))])
    if op == "color":
        return COLOR, color_bytes(value)
    if op == "temperature":
        return TEMPERATURE, struct.pack("<H", round(1_000_000 / integer(value, 2000, 6500)))
    raise ValueError("Unknown lamp command.")


def emit(value):
    print(json.dumps(value, allow_nan=False), flush=True)


class Hue:
    def __init__(self, client_factory, scanner, state_path=None, output=emit):
        self.client_factory = client_factory
        self.scanner = scanner
        self.state_path = Path(state_path) if state_path else None
        self.output = output
        self.client = None
        self.active = False
        self.devices = {}
        self.load_error = ""
        self.state = dict(address="", connected=False, busy=False, power=False,
                          brightness=100, color=False, temperature=False, model="",
                          devices=[], error="", ready=True)
        if self.state_path:
            try:
                saved = json.loads(self.state_path.read_text())
                self.state["address"] = address(saved["address"]) if saved["address"] else ""
            except FileNotFoundError:
                pass
            except (OSError, ValueError, KeyError, TypeError) as error:
                self.load_error = f"Could not load the saved lamp: {error}"
                self.state["error"] = self.load_error

    def publish(self, reply=None, **changes):
        self.state.update(changes)
        self.output(dict(self.state, reply=reply))

    def save(self, selected):
        if self.state_path:
            self.state_path.parent.mkdir(parents=True, exist_ok=True)
            temporary = self.state_path.with_suffix(".tmp")
            temporary.write_text(json.dumps({"address": selected}) + "\n")
            temporary.replace(self.state_path)
        self.state["address"] = selected
        self.load_error = ""

    def disconnected(self, client):
        if client is self.client:
            self.publish(connected=False)

    async def disconnect(self):
        client, self.client = self.client, None
        self.state["connected"] = False
        if client:
            await asyncio.wait_for(client.disconnect(), 5)

    async def connect(self):
        if self.client and self.client.is_connected:
            return
        await self.disconnect()
        selected = address(self.state["address"])
        device = self.devices.get(selected)
        if device is None:
            device = await self.scanner.find_device_by_address(selected, timeout=8)
        if device is None:
            raise RuntimeError("Lamp not found. Turn it on nearby and close the Hue phone app.")
        self.client = self.client_factory(device, pair=True, disconnected_callback=self.disconnected)
        await asyncio.wait_for(self.client.connect(), 30)
        for uuid in (POWER, BRIGHTNESS):
            if self.client.services.get_characteristic(uuid) is None:
                raise RuntimeError("This device does not expose the Hue light controls.")
        self.state["color"] = self.client.services.get_characteristic(COLOR) is not None
        self.state["temperature"] = self.client.services.get_characteristic(TEMPERATURE) is not None
        self.state["model"] = ""
        if self.client.services.get_characteristic(MODEL):
            self.state["model"] = bytes(await self.read(MODEL)).decode("utf-8", errors="replace").rstrip("\0")
        self.state["connected"] = True

    async def read(self, uuid):
        return await asyncio.wait_for(self.client.read_gatt_char(uuid), 5)

    async def refresh(self):
        power = await self.read(POWER)
        brightness = await self.read(BRIGHTNESS)
        if len(power) != 1 or power[0] not in (0, 1) or len(brightness) != 1:
            raise RuntimeError("The lamp returned an invalid state.")
        self.state.update(power=bool(power[0]), brightness=max(1, min(100, round(brightness[0] * 100 / 254))))

    async def scan(self):
        if self.state["connected"]:
            raise ValueError("Forget the selected lamp before scanning for another.")
        self.state["devices"] = []
        results = await self.scanner.discover(timeout=8, return_adv=True)
        self.devices = {}
        for device, advertisement in results.values():
            uuids = {uuid.lower() for uuid in advertisement.service_uuids}
            uuids.update(uuid.lower() for uuid in advertisement.service_data)
            if {HUE_SERVICE, LIGHT_SERVICE}.intersection(uuids):
                selected = address(device.address)
                self.devices[selected] = device
                self.state["devices"].append(dict(address=selected, name=advertisement.local_name or device.name or "Hue lamp"))
        self.state["devices"].sort(key=lambda item: item["address"])
        if not self.devices:
            raise RuntimeError("No Hue lamps found. Turn the lamp off and on nearby, then scan again.")

    async def handle(self, command):
        reply = command.get("id") if isinstance(command, dict) else None
        self.publish(busy=True, error="")
        try:
            if not isinstance(command, dict):
                raise ValueError("Expected a JSON object.")
            op = command.get("op")
            if op == "active":
                if type(command.get("value")) is not bool:
                    raise ValueError("Active must be true or false.")
                self.active = command["value"]
                if not self.active:
                    await self.disconnect()
                elif self.state["address"]:
                    await self.connect()
                    await self.refresh()
                elif self.load_error:
                    self.state["error"] = self.load_error
            elif op == "forget":
                self.save("")
                await self.disconnect()
                self.state.update(model="", devices=[], color=False, temperature=False)
            elif op == "scan":
                await self.scan()
            elif op == "select":
                selected = address(command.get("address"))
                await self.disconnect()
                self.save(selected)
                self.active = True
                await self.connect()
                await self.refresh()
            elif op == "refresh":
                if self.active and self.state["address"]:
                    await self.connect()
                    await self.refresh()
            else:
                uuid, payload = setting(command)
                # Do not reconnect and replay an old click after a dropped link.
                if not self.active or not self.client or not self.client.is_connected:
                    raise ValueError("Lamp disconnected. Reconnect before changing it.")
                characteristic = self.client.services.get_characteristic(uuid)
                if characteristic is None:
                    raise ValueError("This lamp does not support that control.")
                response = "write" in characteristic.properties
                if not response and "write-without-response" not in characteristic.properties:
                    raise ValueError("This lamp control is not writable.")
                await asyncio.wait_for(self.client.write_gatt_char(uuid, payload, response=response), 5)
                await asyncio.sleep(SETTLE_SECONDS)
                await self.refresh()
        except ValueError as error:
            self.state["error"] = str(error)
        except Exception as error:
            self.state["error"] = f"Bluetooth: {str(error) or type(error).__name__}. Check power, pairing, and other connected apps."
            try:
                await self.disconnect()
            except Exception as cleanup_error:
                self.state["error"] += f" Disconnect failed: {cleanup_error}"
        finally:
            self.publish(reply=reply, busy=False)


async def serve(hue):
    loop = asyncio.get_running_loop()
    reader = asyncio.StreamReader(limit=4096)
    transport, _ = await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)
    loop.add_signal_handler(signal.SIGTERM, asyncio.current_task().cancel)
    hue.publish()
    retry = POLL_SECONDS
    try:
        while True:
            timeout = retry if hue.active and hue.state["address"] else None
            try:
                line = await asyncio.wait_for(reader.readline(), timeout)
            except asyncio.TimeoutError:
                await hue.handle({"op": "refresh"})
                retry = POLL_SECONDS if hue.state["connected"] else min(MAX_RETRY_SECONDS, retry * 2)
                continue
            if not line:
                break
            try:
                command = json.loads(line)
            except (ValueError, UnicodeDecodeError) as error:
                hue.publish(error=f"Invalid command: {error}")
                continue
            await hue.handle(command)
            retry = POLL_SECONDS
    finally:
        transport.close()
        await hue.disconnect()


async def main(args):
    try:
        from bleak import BleakClient, BleakScanner
    except ImportError:
        emit(dict(ready=False, connected=False, busy=False,
                  error="Install the Hue Bluetooth dependency. See README: Hue Go setup."))
        return 1
    hue = Hue(BleakClient, BleakScanner, args.state)
    if args.command == "serve":
        await serve(hue)
        return 0
    try:
        if args.command == "scan":
            await hue.handle({"op": "scan"})
        else:
            await hue.handle({"op": "select", "address": args.address})
            if not hue.state["error"] and args.command == "set":
                value = json.loads(args.value) if args.control in ("power", "brightness", "temperature") else args.value
                await hue.handle({"op": args.control, "value": value})
            if not hue.state["error"] and args.command == "inspect":
                emit({"services": [{"uuid": service.uuid, "characteristics": [
                    {"uuid": char.uuid, "properties": char.properties} for char in service.characteristics
                ]} for service in hue.client.services]})
        return 1 if hue.state["error"] else 0
    finally:
        await hue.disconnect()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state", help="Optional saved lamp JSON path")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("serve")
    commands.add_parser("scan")
    commands.add_parser("inspect").add_argument("address")
    setter = commands.add_parser("set")
    setter.add_argument("address")
    setter.add_argument("control", choices=["power", "brightness", "color", "temperature"])
    setter.add_argument("value")
    try:
        sys.exit(asyncio.run(main(parser.parse_args())))
    except (KeyboardInterrupt, asyncio.CancelledError):
        pass
    except Exception as error:
        emit(dict(ready=False, connected=False, busy=False, error=str(error) or type(error).__name__))
        sys.exit(1)
