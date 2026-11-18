"""Compile the macOS .icns app icon from macos/Assets/AppIcon.png."""
from pathlib import Path
import struct
import subprocess

SOURCE = Path(__file__).resolve().parents[1] / 'macos/Assets/AppIcon.png'


def compile_icon(work, resources_dir):
    work, resources_dir = Path(work), Path(resources_dir)
    resources_dir.mkdir(parents=True, exist_ok=True)
    data = SOURCE.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    width, height = struct.unpack_from('>II', data, 16)
    assert width == height and 1024 <= width <= 8192, 'Expected a >=1024x1024 square icon'

    iconset = work / 'AppIcon.iconset'
    iconset.mkdir(parents=True, exist_ok=True)
    sizes = [
        (16, 'icon_16x16.png'),
        (32, 'icon_16x16@2x.png'),
        (32, 'icon_32x32.png'),
        (64, 'icon_32x32@2x.png'),
        (128, 'icon_128x128.png'),
        (256, 'icon_128x128@2x.png'),
        (256, 'icon_256x256.png'),
        (512, 'icon_256x256@2x.png'),
        (512, 'icon_512x512.png'),
        (1024, 'icon_512x512@2x.png'),
    ]
    for px, name in sizes:
        subprocess.run(
            ['sips', '-s', 'format', 'png', '--resampleHeightWidth', str(px), str(px),
             str(SOURCE), '--out', str(iconset / name)],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
    icns = resources_dir / 'AppIcon.icns'
    subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(icns)], check=True)
    assert icns.is_file() and icns.stat().st_size > 0
    return {'CFBundleIconFile': 'AppIcon'}
