import QtQuick 2.15
import QtQml.Models 2.15
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
//   toggle_desktop_edit_mode     — show/hide interactive desktop widget editor
//   show_desktop_edit_mode       — enable interactive desktop widget editor
//   hide_desktop_edit_mode       — disable interactive desktop widget editor
//   toggle <controller-id>       — toggle a registered surface
//   show   <controller-id>       — show a registered surface
//   hide   <controller-id>       — hide a registered surface
//   volume_up                    — +5% volume + show volume-osd
//   volume_down                  — -5% volume + show volume-osd
//   volume_mute                  — toggle mute  + show volume-osd
//   dismiss_oldest_notification  — dismiss the oldest notification without taking focus
//   set_wallpaper  <path>        — set wallpaper to an absolute path

ShellRoot {
    readonly property var _defaultAudioSink: Pipewire.defaultAudioSink
    readonly property bool _garminBootstrap: GarminState.started

    PwObjectTracker {
        objects: [_defaultAudioSink]
    }

    Timer {
        interval: 1500
        repeat: false
        running: true
        onTriggered: GarminState.ensureStarted()
    }

    // ── Standalone windows ────────────────────────────────────────────────────
    ControlCenter { id: controlCenter }
    Variants {
        model: Quickshell.screens
        WallpaperBackground {
            required property var modelData
            screen: modelData
        }
    }
    Instantiator {
        model: ModuleRegistry.desktopModules
        delegate: DesktopEditWidgetWindow {
            required property var modelData
            screen: Quickshell.screens[0]
            moduleConfig: modelData
        }
    }
    VolumeOSD {}
    NotificationOSD { id: notificationOsd }

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

        function toggle_desktop_edit_mode() {
            DesktopState.editMode = !DesktopState.editMode;
        }

        function show_desktop_edit_mode() {
            DesktopState.editMode = true;
        }

        function hide_desktop_edit_mode() {
            DesktopState.editMode = false;
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

        function dismiss_oldest_notification() {
            if ((controlCenter && controlCenter.visible) || (notificationOsd && notificationOsd.visible))
                NotificationService.dismissOldest();
        }

        function set_wallpaper(path: string) {
            if (path)
                Config.updateWallpaper({
                    current: path
                });
        }

    }
}
