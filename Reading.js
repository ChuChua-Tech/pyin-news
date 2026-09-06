.pragma library

function sizeScale(value) {
  return value === "large" ? 1.15 : (value === "extra-large" ? 1.3 : 1)
}

function luminance(color) {
  function linear(value) {
    return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4)
  }
  return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
}

function contrast(a, b) {
  var first = luminance(a), second = luminance(b)
  return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05)
}

function secondaryColor(foreground, background, muted) {
  // Stay within the selected palette. Desktop compositing can affect the final
  // contrast; this chooses against the app surface, without changing the theme.
  return contrast(muted, background) >= 4.5 ? muted : foreground
}
