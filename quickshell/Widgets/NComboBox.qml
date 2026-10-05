import QtQuick.Controls as Controls
Controls.ComboBox {
    property string currentKey: currentIndex >= 0 && model && model[currentIndex] && model[currentIndex].key !== undefined ? model[currentIndex].key : ""
}
