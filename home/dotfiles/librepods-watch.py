#!/usr/bin/env python3
"""Run LibrePods while paired AirPods are connected, without scanning."""

import asyncio
import logging

AIRPODS_UUID = "74ec2172-0bad-4d01-8f77-997b2be0722a"
DEVICE_INTERFACE = "org.bluez.Device1"
DEVICE_PROPERTIES = frozenset(("Connected", "Paired", "UUIDs"))


def connected_airpods(devices):
    return any(
        device.get("Paired", False)
        and device.get("Connected", False)
        and AIRPODS_UUID in device.get("UUIDs", ())
        for device in devices
    )


async def main():
    from dbus_fast import BusType, Message, MessageType
    from dbus_fast.aio import MessageBus

    logging.basicConfig(level=logging.INFO, format="%(message)s")
    bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
    changed = asyncio.Event()
    owner = None

    async def call(message):
        reply = await bus.call(message)
        if reply.message_type == MessageType.ERROR:
            raise RuntimeError(f"{reply.error_name}: {reply.body}")
        return reply

    def receive(message):
        if message.message_type != MessageType.SIGNAL:
            return
        if (
            message.sender == "org.freedesktop.DBus"
            and message.interface == "org.freedesktop.DBus"
            and message.member == "NameOwnerChanged"
            and message.body[0] == "org.bluez"
        ):
            changed.set()
        elif message.sender == owner:
            if message.interface == "org.freedesktop.DBus.ObjectManager":
                changed.set()
            elif (
                message.interface == "org.freedesktop.DBus.Properties"
                and message.member == "PropertiesChanged"
                and message.body[0] == DEVICE_INTERFACE
                and DEVICE_PROPERTIES.intersection(
                    set(message.body[1]) | set(message.body[2])
                )
            ):
                changed.set()

    bus.add_message_handler(receive)
    for rule in (
        "type='signal',sender='org.freedesktop.DBus',"
        "interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='org.bluez'",
        "type='signal',sender='org.bluez',"
        "interface='org.freedesktop.DBus.ObjectManager'",
        "type='signal',sender='org.bluez',"
        "interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',"
        "arg0='org.bluez.Device1'",
    ):
        await call(Message(
            destination="org.freedesktop.DBus", path="/org/freedesktop/DBus",
            interface="org.freedesktop.DBus", member="AddMatch",
            signature="s", body=[rule],
        ))

    async def snapshot():
        nonlocal owner
        reply = await bus.call(Message(
            destination="org.freedesktop.DBus", path="/org/freedesktop/DBus",
            interface="org.freedesktop.DBus", member="GetNameOwner",
            signature="s", body=["org.bluez"],
        ))
        if reply.message_type == MessageType.ERROR:
            if reply.error_name == "org.freedesktop.DBus.Error.NameHasNoOwner":
                owner = None
                return []
            raise RuntimeError(f"{reply.error_name}: {reply.body}")
        owner = reply.body[0]
        reply = await bus.call(Message(
            destination=owner, path="/", interface="org.freedesktop.DBus.ObjectManager",
            member="GetManagedObjects",
        ))
        if reply.message_type == MessageType.ERROR:
            if reply.error_name in (
                "org.freedesktop.DBus.Error.ServiceUnknown",
                "org.freedesktop.DBus.Error.NameHasNoOwner",
            ):
                logging.info("BlueZ disappeared while reading devices; stopping LibrePods")
                return []
            raise RuntimeError(f"{reply.error_name}: {reply.body}")
        return [
            {key: value.value for key, value in interfaces[DEVICE_INTERFACE].items()
             if key in DEVICE_PROPERTIES}
            for interfaces in reply.body[0].values()
            if DEVICE_INTERFACE in interfaces
        ]

    running = None
    changed.set()
    disconnected = asyncio.create_task(bus.wait_for_disconnect())
    while True:
        pending = asyncio.create_task(changed.wait())
        done, _ = await asyncio.wait(
            (pending, disconnected), return_when=asyncio.FIRST_COMPLETED,
        )
        if disconnected in done:
            pending.cancel()
            await disconnected
            raise RuntimeError("System D-Bus disconnected")
        changed.clear()
        desired = connected_airpods(await snapshot())
        if desired != running:
            action = "start" if desired else "stop"
            process = await asyncio.create_subprocess_exec(
                "systemctl", "--user", action, "librepods.service",
            )
            if await process.wait() != 0:
                raise RuntimeError(f"Failed to {action} librepods.service")
            logging.info("%s LibrePods: connected paired AirPods = %s", action, desired)
            running = desired


if __name__ == "__main__":
    asyncio.run(main())
