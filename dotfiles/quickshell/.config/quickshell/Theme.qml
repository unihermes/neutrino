// Neutrino - Quickshell
// ~/.config/quickshell/Theme.qml
//
// The palette, type and motion in one place, so the bar and every flyout
// component agree without each file carrying its own copy of the values.
//
// A Quickshell Singleton rather than properties on the bar: the flyout
// components are separate files and have no way to reach into the bar's
// scope, and passing a palette down through every instantiation is worse
// than one import-free global.

pragma Singleton

import Quickshell
import QtQuick

Singleton {
    id: root

    // The grayscale ramp. In wallpaper colour mode each role is swapped for
    // the matching tone from the wallpaper's palette (see Wallpaper.qml);
    // until one exists, or in grayscale mode, it's these.
    readonly property var gray: ({
        base:    "#0b0b0b",
        bar:     "#121212",
        panel:   "#141414",
        surface: "#1a1a1a",
        overlay: "#242424",
        border:  "#303030",
        muted:   "#4d4d4d",
        subtext: "#7a7a7a",
        text:    "#c2c2c2",
        bright:  "#ebebeb",
    })
    readonly property var roles: Settings.colourMode === "wallpaper" && Wallpaper.palette
        ? Wallpaper.palette : gray

    readonly property color base:    roles.base
    readonly property color bar:     roles.bar
    // the flyouts' ground, a step above the bar
    readonly property color panel:   roles.panel
    readonly property color surface: roles.surface
    readonly property color overlay: roles.overlay
    readonly property color border:  roles.border
    readonly property color muted:   roles.muted
    readonly property color subtext: roles.subtext
    readonly property color text:    roles.text
    readonly property color bright:  roles.bright

    // The only hues that don't follow the wallpaper, and deliberately so:
    // charging and critical are states you want to catch without reading
    // anything, and a red or green wallpaper would otherwise camouflage them.
    // Desaturated hard, so they read as a tinted grey at a glance rather than
    // as alerts competing with the rest of the bar.
    readonly property color good:    "#7d9b7d"
    readonly property color alert:   "#a87676"

    // UbuntuMono Nerd Font for text and icons alike: one font that owns
    // every glyph, so no icon is drawn by fallback at another font's metrics.
    //
    // The NON-Mono variant on purpose. "Nerd Font Mono" forces every icon
    // into one terminal cell -- at 18px it draws all of them 9px wide, which
    // squeezes a 17px-wide glyph (brightness, wifi) by nearly half while
    // leaving a 9px one (battery) alone. That uneven squash is what makes a
    // row of icons look mismatched. The bar has no cell grid to honour, so
    // it takes the proportional faces. Alacritty keeps the Mono variant,
    // where fixed cells are the whole point.
    readonly property string fontText: "UbuntuMono Nerd Font"
    readonly property string fontIcon: "UbuntuMono Nerd Font"

    // Font Size, as a factor. Every font size and every text-bearing row
    // height in the shell goes through fs(), so text and the rows holding it
    // grow together instead of larger text clipping in fixed-height rows.
    readonly property real fontScale: Settings.fontScale / 100
    function fs(n) { return Math.round(n * fontScale) }

    // The type scale. Everything with text uses one of these rather than a
    // size of its own, so a label reads the same size in every flyout and
    // window. Pixel sizes, not point: points scale with the screen's DPI
    // while the rows and chips around them are laid out in pixels.
    readonly property int fontSmall: fs(14)   // headings, captions, secondary lines
    readonly property int fontBody:  fs(16)   // labels, values, chips, inputs
    readonly property int fontLarge: fs(19)   // the odd emphasised glyph (calendar arrows)
    readonly property int fontIconSize: fs(16) // Nerd Font glyphs inside rows

    // Animation Speed. Every duration goes through dur(); "off" makes them
    // all zero, which Qt treats as an instant jump.
    readonly property real animFactor: Settings.animSpeed === "off" ? 0
        : Settings.animSpeed === "fast" ? 0.5 : 1
    function dur(ms) { return Math.round(ms * animFactor) }

    // One source of truth for the bar's geometry: the flyouts anchor to
    // barHeight to sit flush under it, and the icons size off it, so
    // changing the bar's height here moves everything together.
    //
    // The values the control centre's Appearance page can change come from
    // Settings, which persists them. They stay readonly here because nothing
    // should write them through Theme -- Settings.set() is the one way in,
    // and it clamps.
    readonly property string barPosition: Settings.barPosition
    readonly property int barHeight:  Settings.barHeight
    readonly property real barOpacity: Settings.barOpacity / 100
    // The module frame is a double border (outer stroke + a 2px-inset inner
    // stroke), which eats 8px of the chip -- so the icon is sized to the
    // space left inside it rather than to the bar.
    //
    // Derived from the bar rather than fixed, so a taller bar gets taller
    // chips instead of a 28px chip swimming in it. The -6 reproduces the
    // original 28 at the default 34, and the floor keeps the double border
    // from eating the whole chip at the smallest bar height.
    readonly property int moduleHeight: Math.max(18, barHeight - 6)
    readonly property int modulePadH:   8
    // gap between adjacent modules, the same on both sides of the bar
    readonly property int moduleGap:    Settings.moduleGap
    // Shared width for the gauge modules only, so their fill bars are
    // directly comparable. The icon-only chips hug their content instead --
    // padding them out to match would just add dead space.
    readonly property int moduleWidth:  54
    // capped to the chip, so a large Font Size can't push icons out of it
    readonly property int iconSize:     Math.min(moduleHeight - 8, fs(17))
    // one size for every bar label (clock, media, counts), capped the same way
    readonly property int barLabelSize: Math.min(moduleHeight - 8, fs(15))

    readonly property int radius:      Settings.radius
    // One step in from the outer stroke. Floored at 0 because the radius is
    // user-settable down to square, and a negative radius draws nothing.
    readonly property int radiusInner: Math.max(0, radius - 2)
}
