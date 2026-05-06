pragma Singleton
import QtQuick 2.15
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root

    // Latest notification object for OSD (live Quickshell Notification)
    property var latestNotification: null
    signal notificationAdded(var notification)
    signal notificationRemoved(int id)

    // Live list of Quickshell Notification objects.
    // Each has: id, appName, appIcon, summary, body, actions (list of NotificationAction),
    // plus dismiss() / expire() and a closed(reason) signal.
    property var notifications: []

    property NotificationServer _server: NotificationServer {
        keepOnReload: true

        onNotification: (notif) => {
            notif.tracked = true
            root.notifications = [...root.notifications, notif]
            root.latestNotification = notif
            root.notificationAdded(notif)
            notif.closed.connect(function() {
                root.notifications = root.notifications.filter(function(n) { return n.id !== notif.id })
                root.notificationRemoved(notif.id)
            })
        }
    }

    function dismiss(id) {
        const notif = notifications.find(function(n) { return n.id === id })
        if (notif) notif.dismiss()
    }

    function dismissOldest() {
        if (!notifications || notifications.length === 0)
            return
        const notif = notifications[0]
        if (notif)
            notif.dismiss()
    }

    function invokePrimaryAction(notification) {
        if (!notification) return false

        const actions = notification.actions || []
        if (!actions.length) return false

        const defaultAction = actions.find(function(action) {
            return action && action.identifier === "default"
        })
        const fallbackAction = actions.length === 1 ? actions[0] : null
        const action = defaultAction || fallbackAction

        if (!action) return false

        action.invoke()
        return true
    }

    function clear() {
        const all = notifications.slice()
        for (const n of all) n.dismiss()
    }
}
