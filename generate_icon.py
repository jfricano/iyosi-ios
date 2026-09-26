"""Generate the simple iYosi map-pin app icon using only Python's standard library."""
from pathlib import Path
import struct
import zlib

SIZE = 1024
TEAL = bytes((6, 117, 122))
WHITE = bytes((255, 255, 255))
rows = []
for y in range(SIZE):
    row = bytearray(b"\x00")
    for x in range(SIZE):
        dx, dy = x - 512, y - 565
        head = dx * dx + dy * dy < 235 * 235
        tail = 565 <= y <= 900 and abs(dx) < (900 - y) * 0.65
        hole = dx * dx + dy * dy < 90 * 90
        row += TEAL if hole or not (head or tail) else WHITE
    rows.append(bytes(row))


def chunk(name: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + name + data + struct.pack(">I", zlib.crc32(name + data))


png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
png += chunk(b"IEND", b"")
destination = Path(__file__).parent / "iYosi/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
destination.write_bytes(png)
print(destination)
