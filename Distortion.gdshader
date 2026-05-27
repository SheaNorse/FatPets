shader_type canvas_item;

// Bounding Battle Backgound shader by Youkuri (Modified for Pixel Scaling)
// Set 'pixel_scale' to 1.0 for original resolution, 2.0 for double-sized pixels, etc.

group_uniforms Scaling;
uniform float pixel_scale : hint_range(1.0, 16.0) = 1.0;
uniform bool pixel_perfect_movement = true;

group_uniforms Settings;
uniform bool snes_transparency = false;
uniform bool gba_transparency = false;
uniform bool horizontal_scan_line = false;
uniform bool vertical_scan_line = false;
uniform bool enable_palette_cycling = false;

group_uniforms Sprite_Scroll;
uniform vec2 sprite_scroll_direction = vec2(0.0, 0.0);
uniform float sprite_scroll_speed = 0.01;

group_uniforms GBA_Transparency;
uniform vec2 gba_transparency_scroll_direction = vec2(0.0, 0.0);
uniform float gba_transparency_scroll_speed = 0.01;
uniform float gba_transparency_value : hint_range(0.0, 1.0) = 0.5;

group_uniforms Horizontal_Wave;
uniform float horizontal_wave_amplitude = 0.0;
uniform float horizontal_wave_frequency = 0.0;
uniform float horizontal_wave_speed = 1.0;

group_uniforms Vertical_Wave;
uniform float vertical_wave_amplitude = 0.0;
uniform float vertical_wave_frequency = 0.0;
uniform float vertical_wave_speed = 1.0;

group_uniforms Horizontal_Deform;
uniform float horizontal_deform_amplitude = 0.0;
uniform float horizontal_deform_frequency = 0.0;
uniform float horizontal_deform_speed = 1.0;

group_uniforms Vertical_Deform;
uniform float vertical_deform_amplitude = 0.0;
uniform float vertical_deform_frequency = 0.0;
uniform float vertical_deform_speed = 1.0;

group_uniforms Palette_Cycling;
uniform float palette_cycling_speed = 0.1;
uniform sampler2D palette;

float calculate_diff(float uv, float amp, float freq, float spd){
    return amp * sin((freq * uv) + (TIME * spd));
}

vec2 calculate_move(vec2 dir, float spd){
    return dir * TIME * spd;
}

void fragment(){
    // 1. Dynamic Resolution Calculation
    // We get the actual size of the texture and divide by our scale factor
    vec2 tex_size = vec2(textureSize(TEXTURE, 0));
    vec2 scaled_res = tex_size / max(pixel_scale, 0.1);
    
    // Create the pixelated grid
    vec2 grid_uv = floor(UV * scaled_res) / scaled_res;
    
    // 2. Wave and Deform Logic
    float def_x = calculate_diff(grid_uv.x, horizontal_deform_amplitude, horizontal_deform_frequency, horizontal_deform_speed);
    float def_y = calculate_diff(grid_uv.y, vertical_deform_amplitude, vertical_deform_frequency, vertical_deform_speed);
    float wav_x = calculate_diff(grid_uv.y, horizontal_wave_amplitude, horizontal_wave_frequency, horizontal_wave_speed);
    float wav_y = calculate_diff(grid_uv.x, vertical_wave_amplitude, vertical_wave_frequency, vertical_wave_speed);
    
    vec2 move = calculate_move(sprite_scroll_direction, sprite_scroll_speed);
    
    // SNES Transparency logic
    if (int(grid_uv.y * scaled_res.y) % 2 == 0 && snes_transparency) {
        wav_x = -wav_x;
    }
    
    // 3. Final Coordinate Assembly
    vec2 final_uv = vec2(grid_uv.x + def_x + wav_x, grid_uv.y + def_y + wav_y) + move;
    
    if (pixel_perfect_movement) {
        final_uv = floor(final_uv * scaled_res) / scaled_res;
    }
    
    vec4 textube = texture(TEXTURE, final_uv);
    
    // 4. GBA Transparency
    if (gba_transparency) {
        float copy_wav_x = -calculate_diff(grid_uv.y, horizontal_wave_amplitude, horizontal_wave_frequency, horizontal_wave_speed);
        vec4 tex_copy;
        
        if (int(grid_uv.y * scaled_res.y) % 2 == 1 && snes_transparency) {
            copy_wav_x = -copy_wav_x;
        }
        
        vec2 copy_move = move;
        if (gba_transparency_scroll_direction != vec2(0.0)) {
            copy_move = calculate_move(gba_transparency_scroll_direction, gba_transparency_scroll_speed);
        }
        
        vec2 final_copy_uv = vec2(grid_uv.x + def_x + copy_wav_x, grid_uv.y + def_y + wav_y) + copy_move;
        if (pixel_perfect_movement) {
            final_copy_uv = floor(final_copy_uv * scaled_res) / scaled_res;
        }
        
        tex_copy = texture(TEXTURE, final_copy_uv);
        textube = mix(textube, tex_copy, gba_transparency_value);
    }
    
    // 5. Palette Cycling
    if (enable_palette_cycling) {
        float palette_swap = mod(textube.r - TIME * palette_cycling_speed, 1.0);
        textube = vec4(texture(palette, vec2(palette_swap, 0)).rgb, textube.a);
    }
    
    COLOR = textube;
    
    // 6. Scanlines
    if (horizontal_scan_line) {
        COLOR = mix(vec4(0.0, 0.0, 0.0, 1.0), COLOR, float(int(grid_uv.y * scaled_res.y) % 2));
    }
    if (vertical_scan_line) {
        COLOR = mix(vec4(0.0, 0.0, 0.0, 1.0), COLOR, float(int(grid_uv.x * scaled_res.x) % 2));
    }
}