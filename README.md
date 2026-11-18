# Roblox Auto Rejoin

A simple Lua script that automatically rejoins a Roblox game after a disconnect or kick.

## Usage

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Meiks1/roblox-auto-rejoin/main/autorejoin.lua"))()
```

Replace `YOUR_USERNAME` with your GitHub username (also in `SCRIPT_URL` inside `autorejoin.lua`).

## Settings

| Option | Default | Description |
|---|---|---|
| `REJOIN_SAME_SERVER` | `true` | Try the same server first, otherwise join a new one |
| `DELAY` | `2` | Seconds to wait before rejoining |
| `RELOAD_ON_TELEPORT` | `true` | Re-run the script after rejoining (needs `queue_on_teleport`) |

## Notes

- Same-server rejoin only works if the server still exists and has room.
- Requires an executor with `CoreGui` access.
- Using executors may violate Roblox's Terms of Service. Use at your own risk.

## License

MIT

## Sprout Hopper

`sprout-hopper.lua` hops public servers, tweens to a sprout when it finds one, auto-digs (swings your tool) on it until it is gone, collects loot, then hops again.
Object names in `CONFIG` are guesses: check them with Dex and adjust. Set `SCRIPT_URL` to your own repo so it reloads after each hop.
