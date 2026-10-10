# Robo Grid

A Factorio 2.0 mod that grows your robot network on a square grid to wherever you build.

- **Auto-grow** (lit button on the shortcut bar): build, or place a ghost, outside the robot network and the
  network grows toward it: roboport ghosts on the grid, edge-first, each with a pole chain to power it, and
  construction robots requested for each new roboport.
- **Robo grid tool**: drag over an area to grow the network over it. Shift-drag over roboports to remove the ones
  others now cover completely (as roboports gain quality).
- **Auto-tidy** (lit button): roboports made redundant by an upgraded roboport are removed by robots, and so are
  empty grid roboports and leftover pole chains this mod built. Roboports you placed yourself are never removed.

Map settings: the roboport and pole to use, robots per new roboport, how far to grow, distance kept from enemies,
which buildings don't pull the network (turrets, mines, vehicles by default), the grid overlap.
Safe to add or remove at any time.

## Install

Copy this folder into your mods folder (`%APPDATA%\Factorio\mods`) as `robo-grid`, or clone it there:

```
git clone https://github.com/watdafawx/robo-grid
```

`test\run.py` runs the headless test (`test\run.py --all`: both cases at once) (set `FACTORIO_EXE` if the game isn't in a usual Steam library).

## License

MIT, see [LICENSE](LICENSE).
