import QtQuick
import QtQuick.Effects
import qs.Commons

// Rounded thumbnail. `Style.cornerRadius` mirrors Hyprland's
// `decoration:rounding` (the shell re-reads it on startup and on theme
// change). `clip: true` on an Image only clips rectangularly, hence the
// MultiEffect mask.
//
// `inset` is the distance from the parent surface: the concentric-radii rule
// (`r_inner = r_outer - gap`) keeps the padding visually uniform.
Item {
  id: roundedImage

  property alias source: roundedImageSource.source
  property alias status: roundedImageSource.status
  property alias fillMode: roundedImageSource.fillMode
  property int inset: 0
  property int radius: Math.max(0, Style.cornerRadius - inset)
  property int topRadius: radius
  property int bottomRadius: radius

  Rectangle {
    id: roundedImageMask
    anchors.fill: parent
    visible: false
    layer.enabled: true
    color: "white"
    topLeftRadius: roundedImage.topRadius
    topRightRadius: roundedImage.topRadius
    bottomLeftRadius: roundedImage.bottomRadius
    bottomRightRadius: roundedImage.bottomRadius
  }

  Item {
    anchors.fill: parent
    layer.enabled: roundedImage.topRadius > 0 || roundedImage.bottomRadius > 0
    layer.smooth: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: roundedImageMask
    }

    Image {
      id: roundedImageSource
      anchors.fill: parent
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: true
      sourceSize.width: 512
    }
  }
}
