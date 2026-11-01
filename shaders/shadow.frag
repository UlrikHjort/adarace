#version 450 core
flat in float vMat;
in vec2 vUV;
uniform sampler2D uLeaves;
uniform sampler2D uNeedles;
void main()
{
    // Foliage throws dappled shadow, not the shape of its cards
    if (vMat == 9.0 && texture(uLeaves, vUV).a < 0.42) discard;
    if (vMat == 10.0 && texture(uNeedles, vUV).a < 0.42) discard;
}
