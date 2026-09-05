import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: picker
  spacing: Style.spacing.md
  property string selectedModel: ""
  property string selectedEffort: ""
  property var catalog: ({})
  property bool loading: false
  property bool saving: false
  property color foreground: Color.foreground
  property color background: Color.background
  property color accent: Color.accent
  property color dim: Color.muted
  property string fontFamily: Style.font.family
  property bool manualEntry: false
  property string validationMessage: ""
  readonly property var models: catalog.models || []
  readonly property var selectedEntry: {
    for (var i = 0; i < models.length; i++)
      if (String(models[i].value) === selectedModel) return models[i]
    return ({})
  }
  readonly property var modelOptions: {
    var result = [{value: "", label: "Agent default", description: "Follow your agent's configured model and reasoning"}]
    for (var i = 0; i < models.length; i++) result.push(models[i])
    if (selectedModel !== "" && !selectedEntry.value)
      result.push({value: selectedModel, label: selectedModel, description: "Saved model · availability checked on request"})
    result.push({value: "__refresh__", label: "Refresh available models", description: "Ask the selected agent for its current catalog"})
    result.push({value: "__manual__", label: "Enter model name manually…", description: "Use an exact model identifier supported by your agent"})
    return result
  }
  readonly property var effortOptions: {
    var result = [{value: "", label: "Agent default"}]
    var efforts = selectedEntry.efforts || []
    var found = selectedEffort === ""
    for (var i = 0; i < efforts.length; i++) {
      result.push(efforts[i])
      if (String(efforts[i].value) === selectedEffort) found = true
    }
    if (!found) result.push({value: selectedEffort, label: selectedEffort + " · saved setting"})
    return result
  }
  signal selectionRequested(string model, string effort)
  signal discoveryRequested(bool refresh)

  function chooseModel(value) {
    if (value === "__refresh__") picker.discoveryRequested(true)
    else if (value === "__manual__") {
      picker.manualEntry = true
      manualField.text = picker.selectedModel
      Qt.callLater(function() { manualField.forceActiveFocus(); manualField.selectAll() })
    } else {
      picker.manualEntry = false
      picker.validationMessage = ""
      picker.selectionRequested(String(value), value === picker.selectedModel ? picker.selectedEffort : "")
    }
  }
  function applyManual() {
    var model = manualField.text.trim()
    if (!/^[A-Za-z0-9][A-Za-z0-9._:/@+\-]{0,199}$/.test(model)) {
      picker.validationMessage = "Enter a model identifier without spaces (up to 200 characters)."
      return
    }
    picker.validationMessage = ""
    picker.manualEntry = false
    picker.selectionRequested(model, model === picker.selectedModel ? picker.selectedEffort : "")
  }
  onVisibleChanged: if (!visible) {
    modelDropdown.close()
    effortDropdown.close()
    manualEntry = false
    validationMessage = ""
  }

  SearchableDropdown {
    id: modelDropdown
    width: parent.width
    label: "MODEL"
    value: picker.selectedModel
    options: picker.modelOptions
    placeholderText: "Search models…"
    enabled: !picker.saving
    foreground: picker.foreground
    background: picker.background
    accent: picker.accent
    fontFamily: picker.fontFamily
    onPopupOpenChanged: if (popupOpen) picker.discoveryRequested(false)
    onChanged: function(value) {
      picker.chooseModel(value)
      modelDropdown.value = Qt.binding(function() { return picker.selectedModel })
    }
  }
  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: picker.selectedModel === ""
      ? "Uses your agent's configured model and reasoning."
      : "Used only by PYIN. " + String(picker.selectedEntry.description || "Availability is checked when you request a summary.")
    wrapMode: Text.Wrap
    color: picker.dim
    font.family: picker.fontFamily
    font.pixelSize: Style.font.caption
  }
  Text {
    visible: picker.loading || Boolean(picker.catalog.error)
    width: parent.width
    textFormat: Text.PlainText
    text: picker.loading ? "Loading available models…"
      : String(picker.catalog.error || "") + (picker.catalog.stale ? " Showing the previous catalog." : "")
    wrapMode: Text.Wrap
    color: picker.dim
    font.family: picker.fontFamily
    font.pixelSize: Style.font.caption
  }
  Column {
    width: parent.width
    visible: picker.manualEntry
    spacing: Style.spacing.sm
    TextField {
      id: manualField
      width: parent.width
      placeholderText: "Exact model name"
      maximumLength: 200
      foreground: picker.foreground
      accent: picker.accent
      font.family: picker.fontFamily
      onAccepted: if (!picker.saving) picker.applyManual()
    }
    Row {
      spacing: Style.spacing.md
      Button {
        text: "Use model"; bordered: true; focusable: true
        foreground: picker.foreground; accent: picker.accent; fontFamily: picker.fontFamily
        enabled: !picker.saving
        onClicked: picker.applyManual()
      }
      Button {
        text: "Cancel"; focusable: true
        foreground: picker.foreground; accent: picker.accent; fontFamily: picker.fontFamily
        onClicked: { picker.manualEntry = false; picker.validationMessage = "" }
      }
    }
    Text {
      visible: text !== ""; width: parent.width; textFormat: Text.PlainText
      text: picker.validationMessage; wrapMode: Text.Wrap; color: picker.dim
      font.family: picker.fontFamily; font.pixelSize: Style.font.caption
    }
  }
  Dropdown {
    id: effortDropdown
    visible: picker.selectedModel !== "" && picker.effortOptions.length > 1
    width: parent.width
    label: "REASONING · OPTIONAL"
    value: picker.selectedEffort
    options: picker.effortOptions
    enabled: !picker.saving
    foreground: picker.foreground
    background: picker.background
    accent: picker.accent
    fontFamily: picker.fontFamily
    onChanged: function(value) {
      picker.selectionRequested(picker.selectedModel, value)
      effortDropdown.value = Qt.binding(function() { return picker.selectedEffort })
    }
  }
}
