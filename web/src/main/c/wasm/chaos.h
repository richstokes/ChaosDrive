#ifndef _CHAOS_H_
#define _CHAOS_H_

#include <emscripten/emscripten.h>

/* VRAM manipulation */
void EMSCRIPTEN_KEEPALIVE chaos_shift_vram_up(void);
void EMSCRIPTEN_KEEPALIVE chaos_shift_vram_down(void);
void EMSCRIPTEN_KEEPALIVE chaos_shift_vram_left(void);
void EMSCRIPTEN_KEEPALIVE chaos_shift_vram_right(void);
void EMSCRIPTEN_KEEPALIVE chaos_shift_vram_down_random(void);
void EMSCRIPTEN_KEEPALIVE chaos_corrupt_vram_one_byte(void);
void EMSCRIPTEN_KEEPALIVE chaos_invert_vram_contents(void);

/* CRAM/Color manipulation */
void EMSCRIPTEN_KEEPALIVE chaos_randomize_cram(void);
void EMSCRIPTEN_KEEPALIVE chaos_shift_cram_up(void);
void EMSCRIPTEN_KEEPALIVE chaos_enable_cram_corruption(void);
void EMSCRIPTEN_KEEPALIVE chaos_disable_cram_corruption(void);

/* Sprite/Scroll manipulation */
void EMSCRIPTEN_KEEPALIVE chaos_scroll_register_fuzzing(void);
void EMSCRIPTEN_KEEPALIVE chaos_sprite_attribute_scramble(void);

/* Audio controls */
void EMSCRIPTEN_KEEPALIVE chaos_enable_fm_corruption(void);
void EMSCRIPTEN_KEEPALIVE chaos_disable_fm_corruption(void);
void EMSCRIPTEN_KEEPALIVE chaos_corrupt_dac_data(void);
void EMSCRIPTEN_KEEPALIVE chaos_bitcrush_audio_memory(void);
void EMSCRIPTEN_KEEPALIVE chaos_detune_fm_registers(void);
void EMSCRIPTEN_KEEPALIVE chaos_shift_audio_memory_up(void);
void EMSCRIPTEN_KEEPALIVE chaos_shift_audio_memory_down(void);

/* General mayhem */
void EMSCRIPTEN_KEEPALIVE chaos_corrupt_68k_ram_one_byte(void);
void EMSCRIPTEN_KEEPALIVE chaos_critical_ram_scramble(void);
void EMSCRIPTEN_KEEPALIVE chaos_program_counter_increment(void);
void EMSCRIPTEN_KEEPALIVE chaos_random_register_corruption(void);
void EMSCRIPTEN_KEEPALIVE chaos_flip_game_logic_variables(void);

/* VSRAM / H-Scroll / CPU SR */
void EMSCRIPTEN_KEEPALIVE chaos_corrupt_vsram(void);
void EMSCRIPTEN_KEEPALIVE chaos_hscroll_waviness(void);
void EMSCRIPTEN_KEEPALIVE chaos_flip_vdp_mode(void);

/* Reset all chaos state */
void EMSCRIPTEN_KEEPALIVE chaos_reset(void);

/* Pre-render hook (called after VBlank DMA, before Active Display) */
void chaos_pre_render_hook(void);

/* Per-frame update (called from tick) */
void chaos_per_frame_update(void);

#endif /* _CHAOS_H_ */
