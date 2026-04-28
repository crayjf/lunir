import QtQuick 2.15
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import "./lib"
import "./modules"

// Entry point — run with: qs -p ~/Software/lunir
//
// IPC via:  qs ipc call lunir <function> [arg]
//
//   toggle_control_center        — show/hide the control center
//   toggle <controller-id>       — toggle a registered surface
//   show   <controller-id>       — show a registered surface
//   hide   <controller-id>       — hide a registered surface
//   volume_up                    — +5% volume + show volume-osd
//   volume_down                  — -5% volume + show volume-osd
//   volume_mute                  — toggle mute  + show volume-osd
//   set_wallpaper  <path>        — set wallpaper to an absolute path
//   wallpaper_random             — pick a random wallpaper from configured folder

ShellRoot {
    readonly property var _defaultAudioSink: Pipewire.defaultAudioSink

    PwObjectTracker {
        objects: [_defaultAudioSink]
    }

    // ── Standalone windows ────────────────────────────────────────────────────
    ControlCenter {}
    Variants {
        model: Quickshell.screens
        WallpaperBackground {
            required property var modelData
            screen: modelData
        }
    }
    Variants {
        model: Quickshell.screens
        DesktopWidgets {
            required property var modelData
            screen: modelData
        }
    }
    VolumeOSD {}
    NotificationOSD {}

    // ── Volume helpers ────────────────────────────────────────────────────────
    function _changeVolume(delta: real) {
        if (!_defaultAudioSink || !_defaultAudioSink.audio)
            return;
        _defaultAudioSink.audio.volume = Math.max(0, Math.min(1, _defaultAudioSink.audio.volume + delta));
        ModuleControllers.show("volume-osd");
    }

    function _toggleMute() {
        if (!_defaultAudioSink || !_defaultAudioSink.audio)
            return;
        _defaultAudioSink.audio.muted = !_defaultAudioSink.audio.muted;
        ModuleControllers.show("volume-osd");
    }

    // ── Wallpaper-random helper ───────────────────────────────────────── ──────
    Process {
        id: _wpRandProc
        property string folder: ""
        command: ["bash", "-c", "f=${1/#~/$HOME}; find \"$f\" -maxdepth 2 -type f" + " \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp'" + " -o -iname '*.avif' -o -iname '*.tiff' \\)" + " | shuf -n 1", "--", _wpRandProc.folder]
        running: false
        stdout: StdioCollector {
            id: _wpRandStdio
        }
        onExited: {
            const p = _wpRandStdio.text.trim();
            if (p)
                Config.updateWallpaper({
                    current: p
                });
        }
    }

    // ── Hot-reload watcher ────────────────────────────────────────────────────
    Process {
        command: ["inotifywait", "-r", "-q", "-e", "modify,create,delete,move", "--exclude", "(\\.git|\\.swp|\\.swx|~)$", "/home/crayjf/Software/lunir"]
        running: true
        onExited: _reloadDebounce.restart()
    }
    Timer {
        id: _reloadDebounce
        interval: 300
        repeat: false
        onTriggered: Quickshell.reload()
    }

    // ── IPC handler ───────────────────────────────────────────────────────────
    // Called via:  qs ipc call lunir <function_name> [arg]
    IpcHandler {
        target: "qs"

        function toggle_control_center() {
            ModuleControllers.toggle("control-center");
        }

        function toggle(moduleId: string) {
            ModuleControllers.toggle(moduleId);
        }
        function show(moduleId: string) {
            ModuleControllers.show(moduleId);
        }
        function hide(moduleId: string) {
            ModuleControllers.hide(moduleId);
        }

        function volume_up() {
            _changeVolume(0.05);
        }
        function volume_down() {
            _changeVolume(-0.05);
        }
        function volume_mute() {
            _toggleMute();
        }

        function set_wallpaper(path: string) {
            if (path)
                Config.updateWallpaper({
                    current: path
                });
        }

        function wallpaper_random() {
            _wpRandProc.folder = Config.wallpaper.folder || "~/Pictures/Wallpaper";
            _wpRandProc.running = true;
        }
    }
}
