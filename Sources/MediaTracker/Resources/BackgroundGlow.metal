#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

[[ stitchable ]] half4 backgroundGlow(float2 position, half4 color, float2 size, float time, float isDiscover) {
    // Normalize coordinates to 0.0 - 1.0
    float2 uv = position / size;
    
    // Smoothly interpolate between intensities
    float intensity = mix(0.04, 0.12, isDiscover);
    
    // Top-right glow (Pinkish)
    float2 pinkCenter = float2(0.8, 0.2);
    float d1 = distance(uv, pinkCenter);
    float pinkGlow = pow(max(0.0, 1.0 - d1 * 1.5), 3.0);
    
    // Bottom-left glow (Tealish)
    float2 tealCenter = float2(0.2, 0.8);
    float d2 = distance(uv, tealCenter);
    float tealGlow = pow(max(0.0, 1.0 - d2 * 1.5), 3.0);
    
    half4 pink = half4(1.0, 0.2, 0.6, 1.0) * pinkGlow * intensity;
    half4 teal = half4(0.0, 0.8, 0.8, 1.0) * tealGlow * intensity;
    
    // Add subtle animated noise for "texture"
    float noise = fract(sin(dot(uv + time * 0.01, float2(12.9898, 78.233))) * 43758.5453);
    half4 grain = half4(noise) * 0.01;
    
    return color + pink + teal + grain;
}
