pragma Singleton
import QtQuick 2.15
import Quickshell

Singleton {
    id: root

    property var selectedDay: null

    signal dayChanged(var day)

    function _sameDay(a, b) {
        return a && b
            && a.getFullYear() === b.getFullYear()
            && a.getMonth() === b.getMonth()
            && a.getDate() === b.getDate()
    }

    function setSelectedDay(day) {
        if (_sameDay(selectedDay, day))
            return
        selectedDay = day
        dayChanged(day)
    }

    function reset() {
        setSelectedDay(null)
    }
}
