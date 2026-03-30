# Screens and UI

## Overview

The game uses a state machine to manage screens and a button widget for clickable UI. Love2D callbacks are delegated from `main.lua` through `src/init.lua` to the current screen.

## State Machine (`src/core/state.lua`)

A simple screen manager. Each screen is a Lua module registered by name.

**API:**
- `state.register(name, screenModule)` — register a screen
- `state.set(name)` — transition to a screen (calls `onExit` on old, `onEnter` on new)
- `state.get()` — returns current screen name as a string
- `state.getScreen()` — returns the current screen module table
- `state.update(dt)` / `state.draw()` — delegates to current screen

**Lifecycle:** Each screen module can implement any of these (all optional):
- `onEnter(prevState)` — called when switching to this screen. Create UI, initialize state.
- `onExit()` — called when leaving. Clean up UI, release resources.
- `update(dt)` — called every frame.
- `draw()` — called every frame after update.
- `mousepressed(x, y, btn)` / `mousereleased(x, y, btn)` — mouse input.
- `wheelmoved(x, y)` — scroll wheel.

**Why a state machine instead of a stack:** We don't need screen stacking (e.g., pause overlay on top of gameplay). Each screen is a full replacement. If we need overlays later, we can add a stack, but YAGNI for now.

## Input Routing (`src/core/input.lua`)

Centralizes all keyboard and mouse input handling. No screen should directly use `love.keypressed` etc.

**Key bindings** can be registered per-state or globally (`"*"`):
- `input.bindKey(stateName, key, handler)` — state-specific takes priority, global is fallback
- `input.bindMousePress(stateName, btn, handler)` — same pattern for mouse

**Mouse delegation:** If no explicit mouse binding matches, input automatically delegates `mousepressed`/`mousereleased` to the current screen module. This is how buttons in screens receive clicks without explicit bindings.

**Global escape binding** (in `src/init.lua`): Escape returns to menu from any screen, or quits from menu.

## Callback Chain

```
love.keypressed(key)
  → game.keypressed(key)           [src/init.lua]
    → input.keypressed(key)        [src/core/input.lua]
      → state-specific handler OR global handler

love.mousepressed(x, y, btn)
  → game.mousepressed(x, y, btn)
    → input.mousepressed(x, y, btn)
      → explicit binding OR current screen's mousepressed()

love.update(dt) / love.draw()
  → game.update(dt) / game.draw()
    → state.update(dt) / state.draw()
      → currentScreen.update(dt) / currentScreen.draw()
```

## Button Widget (`src/ui/button.lua`)

A self-contained clickable button with hover and pressed states. No external dependencies.

**Usage:**
```lua
local btn = Button.new({
    x = 100, y = 200, w = 160, h = 44,
    text = "Click Me",
    onClick = function() doSomething() end,
})
```

**Per-frame:** Call `btn:update()` (tracks hover via mouse position) and `btn:draw()`.

**Input:** Call `btn:mousepressed(x, y, btnCode)` and `btn:mousereleased(x, y, btnCode)`. The button handles hit testing internally. `onClick` fires on release inside the button (standard click behavior).

**Lifecycle:** Buttons are created in `onEnter` and set to `nil` in `onExit`. They have no persistent state beyond the current screen.

## Current Screens

- **menu** (`src/screens/menu.lua`) — four buttons: Start Run, Simulator, Options, Quit
- **play** (`src/screens/play.lua`) — placeholder with back button
- **simulator** (`src/screens/simulator.lua`) — dev display with spatial map, system panel, event log
- **options** (`src/screens/options.lua`) — placeholder with back button
