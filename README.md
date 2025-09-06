# Megablaster

Virtually circuit-bend a Sega Megadrive/Genesis. Take a perfectly good emulator (DGen), and add a number of "creative" features designed to glitch the video and audio drivers.  

Results in a number of weird, wonderful, interesting, insane effects. The software equivalent of jamming a screwdriver into a working system while it's running to "see what happens".

## Examples
### Sonic 1
<p align="center">
    <img src="screenshots/s1.png" alt="Sonic screenshot" width="50%">
</p>
<p align="center">
    <img src="screenshots/s2.png" alt="Sonic screenshot" width="50%">
</p>

# Build
## Building - Mac
`./buildandrun.sh` "works on my machine".  
Installs dependencies via homebrew and then builds the app. More info [here](BUILDING_ON_MACOS.md)

## Building - Windows
TBD

## Building - Linux
TBD


# Run
`./dgen <ROM>`, e.g. `./dgen sonic1.md`


# Keys
## VRAM Controls
- Key 9: Shift VRAM contents up one byte
- Key 0: Shift VRAM contents down one byte
- Key R: Randomly corrupt a chunk of VRAM

## Audio Memory Controls
- Key 7: Shift Z80 audio memory up  
- Key 8: Shift Z80 audio memory down
- Key C: Corrupt audio (YM2612) registers
- Key V: Corrupt audio (SN76496) PSG registers


Hold keys for rapid shifting (once per frame)
You can also use the VRAM control window buttons.


# Contributing
PRs welcome. 

# Credits/License
Forked from [dgen](https://sourceforge.net/p/dgen/dgen/ci/master/tree/). See the [original Readme](README.original.md) and [Copyright info](COPYING) for more details.