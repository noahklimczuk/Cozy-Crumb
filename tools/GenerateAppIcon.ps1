Add-Type -AssemblyName System.Drawing

$size = 1024
$bitmap = [System.Drawing.Bitmap]::new($size, $size)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

function Color([int]$red, [int]$green, [int]$blue) {
    [System.Drawing.Color]::FromArgb(255, $red, $green, $blue)
}

function Brush([System.Drawing.Color]$color) {
    [System.Drawing.SolidBrush]::new($color)
}

function Pen([System.Drawing.Color]$color, [single]$width) {
    $pen = [System.Drawing.Pen]::new($color, $width)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen
}

$blush = Color 249 202 211
$frosting = Color 255 247 237
$wrapper = Color 242 169 184
$wrapperLine = Color 219 135 157
$ink = Color 107 90 82
$cherry = Color 255 195 206
$butter = Color 251 238 193
$mint = Color 197 230 212

$graphics.Clear($blush)

# Simple, sticker-like cupcake wrapper.
$wrapperPoints = [System.Drawing.Point[]]@(
    [System.Drawing.Point]::new(344, 590),
    [System.Drawing.Point]::new(680, 590),
    [System.Drawing.Point]::new(633, 792),
    [System.Drawing.Point]::new(391, 792)
)
$graphics.FillPolygon((Brush $wrapper), $wrapperPoints)
$graphics.DrawPolygon((Pen $ink 16), $wrapperPoints)

foreach ($x in 420, 485, 550, 615) {
    $graphics.DrawLine((Pen $wrapperLine 13), $x, 625, $x + 14, 756)
}

# White frosting cloud with a single continuous warm outline.
$frostingCloud = [System.Drawing.Drawing2D.GraphicsPath]::new()
$frostingCloud.AddEllipse(315, 410, 175, 170)
$frostingCloud.AddEllipse(405, 335, 195, 210)
$frostingCloud.AddEllipse(530, 410, 175, 170)
$frostingCloud.AddEllipse(380, 480, 260, 135)
$graphics.FillPath((Brush $frosting), $frostingCloud)
$graphics.DrawPath((Pen $ink 16), $frostingCloud)

# Tiny, gentle face and blush cheeks.
$graphics.FillEllipse((Brush $ink), 452, 484, 24, 33)
$graphics.FillEllipse((Brush $ink), 548, 484, 24, 33)
$graphics.DrawArc((Pen $ink 13), 490, 500, 45, 38, 10, 160)
$graphics.FillEllipse((Brush $cherry), 405, 522, 45, 24)
$graphics.FillEllipse((Brush $cherry), 575, 522, 45, 24)

# A small rainbow sprinkle peeking from behind the frosting, like the reference.
$graphics.DrawArc((Pen $butter 16), 638, 500, 80, 80, 210, 95)
$graphics.DrawArc((Pen $mint 16), 648, 510, 58, 58, 210, 95)
$graphics.DrawArc((Pen $wrapperLine 16), 657, 519, 38, 38, 210, 95)

$output = Join-Path $PSScriptRoot "..\Cozy Crumb\Assets.xcassets\AppIcon.appiconset\AppIcon.png"
$bitmap.Save($output, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()
