import QtQuick 2.15
import "../lib"

DateTextModule {
    mode: "time"
    fontFamily: Theme.value(moduleConfig, "font", "Anurati")
    pixelScale: 1.2
    minPixelSize: 10
}
