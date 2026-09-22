pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "../components"
import "../js/Model.js" as Model

// Shared screen header: the emkcloud mark, the screen title with its dim meta
// caption and the row of screen actions (store pill, Help / GitHub / Releases,
// Refresh, Back, Close). Used by every screen except the fullscreen preview.
// The panel owns the state and the actions; this component only renders them
// and reports clicks through signals.
PanelHero {
  id: heroBar

  property string view: "themes"
  property string themeName: ""
  property string versionedName: ""
  property string logoPath: ""
  property bool dev: false
  property bool actionRunning: false
  // Setup's auto-save flash.
  property bool saved: false
  property int wallpapers: 0
  property int installed: 0
  property bool storageLimitReached: false
  property string storageLimitReason: ""
  property color accent: Color.accent

  signal refreshRequested()
  signal backRequested()
  signal closeRequested()
  signal helpRequested()
  signal releasesRequested()
  signal githubRequested()
  signal showThemesRequested()
  signal limitRequested()

  iconComponent: heroIcon
  trailingControl: heroActions
  title: (view === "help"
    ? "Guide & support"
    : (view === "setup"
      ? "Setup & options"
      : (view === "themes"
        ? "Theme selection"
        : (view === "custom"
          ? "Custom install"
          : ("Theme / " + Model.ucfirst(themeName)))))).toUpperCase()
  detail: ""
  meta: view === "help" || view === "setup" || view === "themes"
    || view === "custom"
    ? versionedName
    : "browse and manage wallpapers"

  Component {
    id: heroIcon

    HeroLogo {
      glyph: heroBar.view === "themes" ? "󰸌"
        : (heroBar.view === "help" ? "󰘥"
          : (heroBar.view === "setup" ? "󰒓" : ""))
      source: heroBar.logoPath
      foreground: heroBar.foreground
      fontFamily: heroBar.fontFamily
    }
  }

  Component {
    id: heroActions

    Row {
      spacing: Style.spacing.controlGap

      Button {
        visible: heroBar.dev
        text: "DEV"
        iconText: "\uf121"
        bordered: true
        foreground: heroBar.accent
        accent: heroBar.accent
        fontFamily: heroBar.fontFamily
      }

      // Auto-save feedback: first in the row so showing/hiding it never shifts
      // the pill and the buttons that follow.
      Rectangle {
        visible: heroBar.view === "setup" && heroBar.saved
        width: savedHeroText.implicitWidth + Style.space(24)
        height: refreshButton.implicitHeight
        radius: Style.cornerRadius
        color: Util.alpha(heroBar.accent, 0.16)

        Text {
          id: savedHeroText

          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: "Saved"
          color: heroBar.accent
          font.family: heroBar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      // Global store: total wallpapers and installed count across every theme.
      StorePill {
        visible: heroBar.view !== "help"
        controlHeight: refreshButton.implicitHeight
        wallpapers: heroBar.wallpapers
        installed: heroBar.installed
        limitReason: heroBar.storageLimitReached && heroBar.view !== "setup"
          ? heroBar.storageLimitReason : ""
        foreground: heroBar.foreground
        accent: heroBar.accent
        fontFamily: heroBar.fontFamily
        onLimitActivated: heroBar.limitRequested()
      }

      Button {
        visible: heroBar.view === "themes"
        // Frozen while an action runs, like the preview's actions.
        enabled: !heroBar.actionRunning
        opacity: enabled ? 1 : 0.4
        text: "Help"
        iconText: "󰘥"
        bordered: true
        foreground: heroBar.foreground
        accent: heroBar.accent
        fontFamily: heroBar.fontFamily
        onClicked: heroBar.helpRequested()
      }

      // On Help: jump straight back to the theme list, before GitHub.
      Button {
        visible: heroBar.view === "help"
        enabled: !heroBar.actionRunning
        opacity: enabled ? 1 : 0.4
        text: "Wallpaper manager"
        iconText: "󰸌"
        bordered: true
        foreground: heroBar.foreground
        accent: heroBar.accent
        fontFamily: heroBar.fontFamily
        onClicked: heroBar.showThemesRequested()
      }

      Button {
        visible: heroBar.view === "themes" || heroBar.view === "help"
          || heroBar.view === "setup"
        enabled: !heroBar.actionRunning
        opacity: enabled ? 1 : 0.4
        text: "GitHub"
        iconText: "\uf09b"
        bordered: true
        foreground: heroBar.foreground
        accent: heroBar.accent
        fontFamily: heroBar.fontFamily
        onClicked: heroBar.githubRequested()
      }

      // Releases: same target as the Help "Changelog" resource
      // (config.links.releases). Help screen only.
      Button {
        visible: heroBar.view === "help"
        enabled: !heroBar.actionRunning
        opacity: enabled ? 1 : 0.4
        text: "Releases"
        iconText: "󰓹"
        bordered: true
        foreground: heroBar.foreground
        accent: heroBar.accent
        fontFamily: heroBar.fontFamily
        onClicked: heroBar.releasesRequested()
      }

      Button {
        id: refreshButton

        visible: heroBar.view !== "help" && heroBar.view !== "setup"
        enabled: !heroBar.actionRunning
        opacity: enabled ? 1 : 0.4
        text: "Refresh"
        iconText: "󰑓"
        bordered: true
        foreground: heroBar.foreground
        accent: heroBar.accent
        fontFamily: heroBar.fontFamily
        onClicked: heroBar.refreshRequested()
      }

      Button {
        visible: heroBar.view === "wallpapers" || heroBar.view === "help"
          || heroBar.view === "setup" || heroBar.view === "custom"
        enabled: !heroBar.actionRunning
        opacity: enabled ? 1 : 0.4
        text: "Back"
        iconText: "󰁍"
        bordered: true
        foreground: heroBar.foreground
        accent: heroBar.accent
        fontFamily: heroBar.fontFamily
        onClicked: heroBar.backRequested()
      }

      Button {
        enabled: !heroBar.actionRunning
        opacity: enabled ? 1 : 0.4
        text: "Close"
        iconText: "✕"
        bordered: true
        foreground: heroBar.foreground
        accent: heroBar.accent
        fontFamily: heroBar.fontFamily
        onClicked: heroBar.closeRequested()
      }
    }
  }
}

// innocuous end-of-file comment added for the agent procedure test

