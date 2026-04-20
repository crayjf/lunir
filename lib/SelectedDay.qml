pragma Singleton
import QtQuick 2.15

QtObject {
    id: root

    property var selectedDay: null

    signal dayChanged(var day)

    function setSelectedDay(day) {
        selectedDay = day
        dayChanged(day)
    }

    function reset() {
        setSelectedDay(null)
    }
}
