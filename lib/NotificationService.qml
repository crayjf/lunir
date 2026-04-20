pragma Singleton
import QtQuick 2.15
import Quickshell.Services.Notifications 0.1

QtObject {
    id: root

    // Latest notification object for OSD (live Quickshell Notification)
    property var latestNotification: null
    signal notificationAdded(var notification)
    signal notificationRemoved(int id)

    // Live list of Quickshell Notification objects.
    // Each has: id, appName, appIcon, summary, body, actions (list of NotificationAction),
    // plus close() to dismiss.
    property var notifications: []

    property NotificationServer _server: NotificationServer {
        keepOnReload: true

        onNotification: (notif) => {
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
        if (notif) notif.close()
    }

    function clear() {
        const all = notifications.slice()
        for (const n of all) n.close()
    }
}
