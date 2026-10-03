"""Render the landing page's vector pin as an iOS icon, without dependencies."""
from pathlib import Path
import math
import struct
import zlib

SIZE = 1024
PAPER = bytes.fromhex('f6f1e8')
TEAL = bytes.fromhex('147d79')
SCALE = SIZE / 64


def curve(start, control1, control2, end):
    points = []
    for step in range(33):
        t = step / 32
        u = 1 - t
        points.append(tuple((u**3 * start[i] + 3*u*u*t * control1[i]
                             + 3*u*t*t * control2[i] + t**3 * end[i]) * SCALE
                            for i in (0, 1)))
    return points


# Original SVG favicon path; the OS supplies icon corner masking.
outline = (curve((32, 8), (19, 8), (9, 18), (9, 31))
           + curve((9, 31), (9, 49), (32, 59), (32, 59))
           + curve((32, 59), (32, 59), (55, 49), (55, 31))
           + curve((55, 31), (55, 18), (45, 8), (32, 8)))
rows = []
for y in range(SIZE):
    sample = y + 0.5
    crossings = sorted(a[0] + (sample-a[1]) * (b[0]-a[0]) / (b[1]-a[1])
                       for a, b in zip(outline, outline[1:] + outline[:1])
                       if min(a[1], b[1]) <= sample < max(a[1], b[1]))
    row = bytearray(PAPER * SIZE)
    for left, right in zip(crossings[::2], crossings[1::2]):
        start, end = max(0, math.ceil(left)), min(SIZE, math.ceil(right))
        row[start*3:end*3] = TEAL * (end-start)
    dy = sample - 30*SCALE
    if abs(dy) < 9*SCALE:
        radius = math.sqrt((9*SCALE)**2-dy**2)
        start, end = math.ceil(32*SCALE-radius), math.ceil(32*SCALE+radius)
        row[start*3:end*3] = PAPER * (end-start)
    rows.append(b'\x00' + row)


def chunk(name, data):
    return struct.pack('>I', len(data)) + name + data + struct.pack('>I', zlib.crc32(name + data))


png = b'\x89PNG\r\n\x1a\n'
png += chunk(b'IHDR', struct.pack('>IIBBBBB', SIZE, SIZE, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(b''.join(rows), 9))
png += chunk(b'IEND', b'')
destination = Path(__file__).parent / 'iYosi/Assets.xcassets/AppIcon.appiconset/AppIcon.png'
destination.write_bytes(png)
print(destination)
