varying highp vec2 qt_TexCoord0;
uniform sampler2D source;
uniform lowp float qt_Opacity;
uniform highp float fadeWidthRatio;

void main() {
    lowp vec4 color = texture2D(source, qt_TexCoord0.st);
    highp float alphaFactor = 1.0;

    if (fadeWidthRatio > 0.0) {
        if (qt_TexCoord0.x < fadeWidthRatio)
            alphaFactor = qt_TexCoord0.x / fadeWidthRatio;
        else if (qt_TexCoord0.x > 1.0 - fadeWidthRatio)
            alphaFactor = (1.0 - qt_TexCoord0.x) / fadeWidthRatio;
    }

    alphaFactor = clamp(alphaFactor, 0.0, 1.0);
    gl_FragColor = vec4(color.rgb, color.a * alphaFactor) * qt_Opacity;
}
             