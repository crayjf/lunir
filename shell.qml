import QtQuick 2.15
import Quickshell 0.1
import Quickshell.Wayland 0.1
import Quickshell.Io 0.1
import "./lib"
import "./modules"

// Entry point — run with: qs -p ~/Software/lunir-qs
//
// IPC via:  qs ipc call lunir <function> [arg]
//
//   toggle_overlay               — show/hide the overlay canvas
//   toggle <module-id>           — toggle a standalone module
//   show   <module-id>           — show a standalone module
//   hide   <module-id>           — hide a standalone module
//   list_modules                 — print JSON list of all modules
//   enable_module  <module-id>   — set enabled=true in config
//   disable_module <module-id>   — set enabled=false in config
//   volume_up                    — +5% volume + show volume-osd
//   volume_down                  — -5% volume + show volume-osd
//   volume_mute                  — toggle mute  + show volume-osd
//   wallpaper_picker             — toggle wallpaper-picker window
//   set_wallpaper  <path>        — set wallpaper to an absolute path
//   wallpaper_random             — pick a random wallpaper from configured folder

ShellRoot {

    // ── Standalone windows ────────────────────────────────────────────────────
    GridOverlay        {}   // must be registered before OverlayCanvas/WidgetWindows
    ClickCatcher       {}   // must come before OverlayCanvas so it's registered first
    OverlayCanvas      {}
    WallpaperBackground {}
    VolumeOSD          {}
    NotificationOSD    {}
    WallpaperPicker    {}

    // ── Volume helpers ────────────────────────────────────────────────────────
    Process {
        id: _volUpProc
        command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%+"]
        running: false 
        onExited: ModuleControllers.show("volume-osd")
    }
    Process {
        id: _volDownProc
        command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-"]
        running: false
        onExited: ModuleControllers.show("volume-osd")
    }
    Process {
        id: _volMuteProc
        command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
        running: false
        onExited: ModuleControllers.show("volume-osd")
    }

    // ── Wallpaper-random helper ───────────────────────────────────────────────
    Process {
        id: _wpRandProc
        property string folder: ""
        command: ["bash", "-c",
            "f=${1/#~/$HOME}; find \"$f\" -maxdepth 2 -type f" +
            " \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\)" +
            " | shuf -n 1",
            "--", _wpRandProc.folder]
        running: false
        stdout: StdioCollector { id: _wpRandStdio }
        onExited: {
            const p = _wpRandStdio.text.trim()
            if (p) Config.updateWallpaper({ current: p })
        }
    }

    // ── IPC handler ───────────────────────────────────────────────────────────
    // Called via:  qs ipc call lunir <function_name> [arg]
    IpcHandler {
        target: "qs"

        function toggle_overlay()          { ModuleControllers.toggle("overlay") }

        function toggle(moduleId: string)          { ModuleControllers.toggle(moduleId) }
        function show(moduleId: string)            { ModuleControllers.show(moduleId) }
        function hide(moduleId: string)            { ModuleControllers.hide(moduleId) }

        function enable_module(moduleId: string)   { Config.enableModule(moduleId) }
        function disable_module(moduleId: string)  { Config.disableModule(moduleId) }

        function list_modules() {
            const list = Config.modules.map(function(m) {
                return { id: m.id, type: m.type, enabled: m.enabled, mode: m.mode }
            })
            console.log(JSON.stringify(list, null, 2))
        }

        function volume_up()               { _volUpProc.running   = true }
        function volume_down()             { _volDownProc.running = true }
        function volume_mute()             { _volMuteProc.running = true }

        function wallpaper_picker()        { ModuleControllers.toggle("wallpaper-picker") }

        function set_wallpaper(path: string) { if (path) Config.updateWallpaper({ current: path }) }

        function wallpaper_random() {
            _wpRandProc.folder = Config.wallpaper.folder || "~/Pictures/Wallpaper"
            _wpRandProc.running = true
        }
    }
}
