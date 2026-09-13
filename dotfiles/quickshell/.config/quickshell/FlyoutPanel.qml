// Neutrino - Quickshell
// ~/.config/quickshell/FlyoutPanel.qml
//
// Shared shell for every bar flyout: a full-screen, transparent,
// click-through-everywhere-except-the-box layer-shell surface. The
// full-screen size (rather than sizing to the box) is what makes
// "click anywhere else closes it" possible -- a MouseArea behind the
// box catches the click and closes the flyout; the box has its own
// MouseArea on top of that one, so clicks that land on the box itself
// don't reach the backdrop. The box itself is PanelFrame.qml.

import Quickshell
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: root

    // The bar's per-screen scope (shell.qml) and this flyout's name in it.
    // The scope holds which flyout is open and where it was clicked, so the
    // panel follows it rather than keeping any state of its own.
    required property var scope
    required property string flyout

    screen: scope.modelData
    readonly property bool open: scope.openFlyout === flyout
    // screen-local x (relative to this panel, which spans the whole
    // screen) that the box centres itself under
    readonly property real anchorX: scope.flyoutAnchorX
    // backdrop click, and content that wants to dismiss the flyout
    function requestClose() { scope.openFlyout = "" }

    property real menuWidth: 240
    // A layer-shell surface receives no key events unless it asks for focus,
    // so a text field in here would look focused and silently swallow every
    // keystroke. Only the panels that actually contain an input set this --
    // taking focus unconditionally would steal it from the focused window
    // every time any flyout opened.
    property bool wantsKeyboard: false
    // Stronger than wantsKeyboard: take the keyboard the moment the surface
    // is mapped, not on the next click into it. For search-as-you-type, where
    // making the user click the field first defeats the point. Safe because
    // the panel is transient -- focus goes back when it closes.
    property bool keyboardExclusive: false
    // Distance from the bar's screen edge to the near edge of the box.
    // Matches the bar's height exactly so the flyout sits flush against it
    // rather than floating away from it.
    property real topOffset: Theme.barHeight
    // How close the box may come to the left/right screen edge once the
    // clamp below catches it. The panels whose trigger sits at the very end
    // of the bar (control centre at the far left, battery at the far right)
    // set this to 0 so they run into the corner instead of leaving a sliver
    // of desktop showing beside them.
    property int edgeMargin: 6

    // data, not children, so a panel can hold non-visual helpers (a Timer,
    // a QsMenuOpener) alongside its rows; the Column still lays out only the
    // Items among them
    default property alias content: contentColumn.data
    property alias contentColumn: contentColumn

    visible: open
    anchors { top: true; left: true; right: true; bottom: true }
    // Anchoring to all four edges does NOT stretch a PanelWindow -- it stays
    // at its default 100x100 and the flyout renders as a clipped sliver in
    // the corner. The size has to be given explicitly for the backdrop to
    // actually cover the screen (which is what makes click-off-to-close work).
    implicitWidth: screen ? screen.width : 1920
    implicitHeight: screen ? screen.height : 1080
    // Ignore, not a zero zone: with a plain exclusiveZone the compositor
    // still lays this surface out *below* the bar's reserved strip, so its
    // y=0 is the bar's bottom edge and topOffset would push the flyout down
    // by the bar's height twice over.
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.keyboardExclusive ? WlrKeyboardFocus.Exclusive
        : root.wantsKeyboard ? WlrKeyboardFocus.OnDemand
        : WlrKeyboardFocus.None
    WlrLayershell.namespace: "neutrino-flyout"

    // backdrop: anywhere that isn't the box
    MouseArea {
        anchors.fill: parent
        onClicked: root.requestClose()
    }

    PanelFrame {
        id: box
        x: Math.max(root.edgeMargin,
                    Math.min(root.anchorX - width / 2,
                             root.width - width - root.edgeMargin))
        // Hangs off whichever edge the bar is on: below it at the top,
        // above it at the bottom. Measured from the far edge in the bottom
        // case so the box grows upward as rows are added, which keeps it
        // pinned to the bar instead of sliding down over the screen edge.
        y: Theme.barPosition === "bottom"
            ? root.height - root.topOffset - height
            : root.topOffset
        width: Math.round(root.menuWidth * Theme.fontScale)
        height: contentColumn.implicitHeight + 20

        Behavior on height {
            NumberAnimation { duration: Theme.dur(90); easing.type: Easing.OutCubic }
        }

        // absorbs clicks so they don't fall through to the backdrop
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        Column {
            id: contentColumn
            x: 10
            y: 10
            width: parent.width - 20
            spacing: 6
        }
    }
}
