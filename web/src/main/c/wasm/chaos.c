/**
 * ChaosDrive - Circuit-bending hacks for Genesis/Mega Drive emulator
 *
 * Ported from the original DGen-based ChaosDrive to Genesis Plus GX (WASM).
 * Virtually circuit-bend a Sega Megadrive/Genesis by manipulating VRAM, CRAM,
 * audio memory, CPU registers, and more at runtime.
 */

#include "shared.h"
#include "chaos.h"

/* ======================================================================== */
/* Persistent corruption flags                                              */
/* ======================================================================== */

static int cram_corruption_enabled = 0;
static int fm_corruption_enabled = 0;
static int cram_randomize_pending = 0;
static int cram_shift_pending = 0;

/* ======================================================================== */
/* Helper: mark VRAM dirty so the renderer picks up changes                 */
/* ======================================================================== */

static void mark_all_vram_dirty(void)
{
    int i;
    for (i = 0; i < 0x800; i++)
    {
        bg_name_list[i] = i;
        bg_name_dirty[i] = 0xFF;
    }
    bg_list_index = 0x800;
}

static void mark_all_cram_dirty(void)
{
    int i;
    /* Force palette recalculation */
    for (i = 0; i < 0x40; i++)
    {
        color_update_m5(i, *(uint16 *)&cram[i << 1]);
    }
}

/* ======================================================================== */
/* VRAM Manipulation                                                        */
/* ======================================================================== */

void chaos_shift_vram_up(void)
{
    int i;
    for (i = 0; i < 0xFFFF; i++)
    {
        vram[i] = vram[i + 1];
    }
    mark_all_vram_dirty();
}

void chaos_shift_vram_down(void)
{
    int i;
    for (i = 0xFFFF; i > 0; i--)
    {
        vram[i] = vram[i - 1];
    }
    mark_all_vram_dirty();
}

void chaos_shift_vram_left(void)
{
    int block, i, base;
    for (block = 0; block < 0x100; block++)
    {
        base = block * 256;
        for (i = 0; i < 255; i++)
        {
            vram[base + i] = vram[base + i + 1];
        }
    }
    mark_all_vram_dirty();
}

void chaos_shift_vram_right(void)
{
    int block, i, base;
    for (block = 0; block < 0x100; block++)
    {
        base = block * 256;
        for (i = 255; i > 0; i--)
        {
            vram[base + i] = vram[base + i - 1];
        }
    }
    mark_all_vram_dirty();
}

void chaos_shift_vram_down_random(void)
{
    int shift_amount = rand() % 64;
    int i;
    for (i = 0xFFFF; i > shift_amount; i--)
    {
        vram[i] = vram[i - shift_amount];
    }
    for (i = 0; i < shift_amount; i++)
    {
        vram[i] = 0;
    }
    mark_all_vram_dirty();
}

void chaos_corrupt_vram_one_byte(void)
{
    int addr = rand() % 0x10000;
    vram[addr] = rand() % 256;
    mark_all_vram_dirty();
}

void chaos_invert_vram_contents(void)
{
    int addr;
    for (addr = 0; addr < 0x10000; addr++)
    {
        vram[addr] = ~vram[addr];
    }
    mark_all_vram_dirty();
}

/* ======================================================================== */
/* CRAM / Color Manipulation                                                */
/* ======================================================================== */

void chaos_randomize_cram(void)
{
    /* Defer to pre-render hook so it runs after VBlank DMA */
    cram_randomize_pending = 1;
}

void chaos_shift_cram_up(void)
{
    /* Defer to pre-render hook so it runs after VBlank DMA */
    cram_shift_pending = 1;
}

void chaos_enable_cram_corruption(void)
{
    cram_corruption_enabled = 1;
}

void chaos_disable_cram_corruption(void)
{
    cram_corruption_enabled = 0;
}

void chaos_reset(void)
{
    cram_corruption_enabled = 0;
    fm_corruption_enabled = 0;
    cram_randomize_pending = 0;
    cram_shift_pending = 0;
}

/* ======================================================================== */
/* Sprite / Scroll Manipulation                                             */
/* ======================================================================== */

void chaos_scroll_register_fuzzing(void)
{
    /* Fuzz one of the first 4 VDP registers (scroll-related) */
    int reg_to_fuzz = rand() % 4;
    int fuzz_amount = (rand() % 21) - 10;
    reg[reg_to_fuzz] = reg[reg_to_fuzz] + fuzz_amount;
}

void chaos_sprite_attribute_scramble(void)
{
    /* Get sprite attribute table base address from VDP register 5 */
    int sprite_table_base = (reg[5] & 0x7F) << 9;
    int max_sprites = 80;
    int sprite_entry_size = 8;
    int active_sprites[80];
    int active_sprite_count = 0;
    int i, effects_to_apply, effect_num;

    /* Find active sprites */
    for (i = 0; i < max_sprites; i++)
    {
        int sprite_addr = sprite_table_base + (i * sprite_entry_size);
        uint8 y_high = vram[sprite_addr + 0];
        uint8 y_low  = vram[sprite_addr + 1];
        uint8 pattern_high = vram[sprite_addr + 4];
        uint8 pattern_low  = vram[sprite_addr + 5];
        uint8 x_high = vram[sprite_addr + 6];
        uint8 x_low  = vram[sprite_addr + 7];

        int has_position = (y_high != 0 || y_low != 0 || x_high != 0 || x_low != 0);
        int has_pattern  = (pattern_high != 0 || pattern_low != 0);
        int reasonable_y = (y_high < 8);

        if ((has_position || has_pattern) && reasonable_y)
        {
            active_sprites[active_sprite_count] = i;
            active_sprite_count++;
        }
    }

    if (active_sprite_count == 0)
    {
        for (i = 0; i < 5; i++)
            active_sprites[i] = i;
        active_sprite_count = 5;
    }

    effects_to_apply = (active_sprite_count < 10) ? active_sprite_count : (rand() % 10) + 1;

    for (effect_num = 0; effect_num < effects_to_apply; effect_num++)
    {
        int sprite_index = active_sprites[rand() % active_sprite_count];
        int sprite_addr = sprite_table_base + (sprite_index * sprite_entry_size);
        int scramble_type = rand() % 10;
        int pos, byte_offset;

        switch (scramble_type)
        {
        case 0: /* Scramble Y position */
            pos = rand() % 1024 - 256;
            vram[sprite_addr + 0] = (pos >> 8) & 0xFF;
            vram[sprite_addr + 1] = pos & 0xFF;
            break;
        case 1: /* Scramble sprite size + link */
            vram[sprite_addr + 2] = rand() % 256;
            vram[sprite_addr + 3] = rand() % 256;
            break;
        case 2: /* Scramble tile pattern */
            vram[sprite_addr + 4] = rand() % 256;
            vram[sprite_addr + 5] = rand() % 256;
            break;
        case 3: /* Scramble X position */
            pos = rand() % 1024 - 256;
            vram[sprite_addr + 6] = (pos >> 8) & 0xFF;
            vram[sprite_addr + 7] = pos & 0xFF;
            break;
        case 4: /* Swap with another sprite */
            if (active_sprite_count > 1)
            {
                int sprite2_index = active_sprites[rand() % active_sprite_count];
                int sprite2_addr = sprite_table_base + (sprite2_index * sprite_entry_size);
                uint8 tmp;
                for (byte_offset = 0; byte_offset < sprite_entry_size; byte_offset++)
                {
                    tmp = vram[sprite_addr + byte_offset];
                    vram[sprite_addr + byte_offset] = vram[sprite2_addr + byte_offset];
                    vram[sprite2_addr + byte_offset] = tmp;
                }
            }
            break;
        case 5: /* Completely randomize */
            for (byte_offset = 0; byte_offset < sprite_entry_size; byte_offset++)
                vram[sprite_addr + byte_offset] = rand() % 256;
            break;
        case 6: /* Ghost sprite (position = 0) */
            vram[sprite_addr + 0] = 0;
            vram[sprite_addr + 1] = 0;
            vram[sprite_addr + 6] = 0;
            vram[sprite_addr + 7] = 0;
            break;
        case 7: /* Giant sprite */
            vram[sprite_addr + 2] = 0xFF;
            vram[sprite_addr + 0] = rand() % 256;
            vram[sprite_addr + 1] = rand() % 256;
            vram[sprite_addr + 6] = rand() % 256;
            vram[sprite_addr + 7] = rand() % 256;
            break;
        case 8: /* Break sprite chains */
            vram[sprite_addr + 3] = rand() % 256;
            vram[sprite_addr + 2] = rand() % 256;
            break;
        case 9: /* Stretchy sprite */
        {
            unsigned short weird_pattern = rand() % 0xFFFF;
            vram[sprite_addr + 4] = (weird_pattern >> 8) & 0xFF;
            vram[sprite_addr + 5] = weird_pattern & 0xFF;
            vram[sprite_addr + 2] = 0xFF;
            break;
        }
        }
    }

    /* Occasionally scramble sprite table base register */
    if (rand() % 10 == 0)
    {
        reg[5] = (reg[5] & 0x80) | (rand() % 128);
        satb = (reg[5] << 9) & 0xFE00;
    }

    mark_all_vram_dirty();
}

/* ======================================================================== */
/* Audio Controls                                                           */
/* ======================================================================== */

void chaos_enable_fm_corruption(void)
{
    fm_corruption_enabled = 1;
}

void chaos_disable_fm_corruption(void)
{
    fm_corruption_enabled = 0;
}

void chaos_corrupt_dac_data(void)
{
    /* Corrupt Z80 RAM region commonly used for DAC/PCM data */
    int corruptions = rand() % 64 + 16;
    int i;
    for (i = 0; i < corruptions; i++)
    {
        int index = 0x100 + (rand() % 0x1F00); /* Skip first 0x100 bytes */
        zram[index] = rand() % 256;
    }
}

void chaos_bitcrush_audio_memory(void)
{
    int bits_to_clear = 4; /* Moderate bitcrush */
    uint8 mask = 0xFF << bits_to_clear;
    int i;
    for (i = 0x100; i < 0x2000; i++)
    {
        zram[i] &= mask;
    }
}

void chaos_detune_fm_registers(void)
{
    int channel;
    /* Detune all 6 FM channels by writing random frequency offsets */
    for (channel = 0; channel < 6; channel++)
    {
        int bank = (channel < 3) ? 0 : 2; /* address port: 0 for bank 0, 2 for bank 1 */
        int ch_offset = channel % 3;

        /* Frequency low byte register (0xA0 + ch_offset) */
        int freq_low_reg = 0xA0 + ch_offset;
        int detune = (rand() % 64) - 32;
        int new_val = detune; /* Just add random offset; wraps naturally via uint8 */
        if (new_val < 0) new_val = 0;
        if (new_val > 255) new_val = 255;

        /* Select register, then write data */
        YM2612Write(bank, freq_low_reg);     /* address write */
        YM2612Write(bank + 1, new_val);       /* data write */

        /* Frequency high byte register (0xA4 + ch_offset) */
        {
            int freq_high_reg = 0xA4 + ch_offset;
            int detune_hi = (rand() % 16) - 8;
            int new_hi = detune_hi;
            if (new_hi < 0) new_hi = 0;
            if (new_hi > 63) new_hi = 63;

            YM2612Write(bank, freq_high_reg);
            YM2612Write(bank + 1, new_hi);
        }
    }
}

void chaos_shift_audio_memory_up(void)
{
    int i;
    for (i = 0; i < 0x1FFF; i++)
    {
        zram[i] = zram[i + 1];
    }
}

void chaos_shift_audio_memory_down(void)
{
    int i;
    for (i = 0x1FFF; i > 0; i--)
    {
        zram[i] = zram[i - 1];
    }
}

/* ======================================================================== */
/* General Mayhem                                                           */
/* ======================================================================== */

void chaos_corrupt_68k_ram_one_byte(void)
{
    int addr = rand() % 0x10000;
    work_ram[addr] = rand() % 256;
}

void chaos_critical_ram_scramble(void)
{
    int i, addr;

    /* Corrupt random bytes in upper 32KB of RAM (likely stack space) */
    for (i = 0; i < 32; i++)
    {
        addr = 0x8000 + (rand() % 0x8000);
        work_ram[addr] = rand() % 256;
    }

    /* Also corrupt some bytes at the beginning of RAM */
    for (i = 0; i < 16; i++)
    {
        addr = rand() % 0x1000;
        work_ram[addr] = rand() % 256;
    }
}

void chaos_program_counter_increment(void)
{
    unsigned int pc = m68k_get_reg(M68K_REG_PC);
    unsigned int increment = ((rand() % 4) + 1) * 2; /* 2-8 bytes, even */
    m68k_set_reg(M68K_REG_PC, pc + increment);
}

void chaos_random_register_corruption(void)
{
    int reg_type = rand() % 2;
    int reg_index = rand() % 8;
    m68k_register_t reg_id;

    if (reg_type == 0)
    {
        reg_id = (m68k_register_t)(M68K_REG_D0 + reg_index);
    }
    else
    {
        reg_id = (m68k_register_t)(M68K_REG_A0 + reg_index);
    }

    m68k_set_reg(reg_id, (unsigned int)rand());
}

void chaos_flip_game_logic_variables(void)
{
    /* Target common variable locations used by Genesis games */
    struct { int base_addr; int range; } targets[] = {
        {0x0000, 0x400},
        {0x0400, 0x400},
        {0x0800, 0x800},
        {0x1000, 0x800},
        {0x1800, 0x600},
        {0x2000, 0x800},
        {0x3000, 0x1000},
        {0x8000, 0x1000},
        {0xC000, 0x2000},
        {0xF000, 0x800}
    };
    int num_targets = 10;
    int area, i, addr, hunt;

    for (area = 0; area < num_targets; area++)
    {
        int corruptions_in_area = 3 + (rand() % 6);
        for (i = 0; i < corruptions_in_area; i++)
        {
            uint8 value, new_value;
            int chaos_type;

            addr = targets[area].base_addr + (rand() % targets[area].range);
            if (addr >= 0x10000) continue;
            value = work_ram[addr];

            if (value == 0x00 || value == 0xFF)
                continue;

            chaos_type = rand() % 6;
            switch (chaos_type)
            {
            case 0: new_value = ~value; break;
            case 1:
            {
                uint8 bad_values[] = {0xFF, 0x80, 0x7F, 0x01, 0x00};
                new_value = bad_values[rand() % 5];
                break;
            }
            case 2: new_value = value + (rand() % 32) + 1; break;
            case 3: new_value = value * 2; break;
            case 4: new_value = value | (1 << (rand() % 8)); break;
            case 5: new_value = value & ~(1 << (rand() % 8)); break;
            default: new_value = ~value; break;
            }

            work_ram[addr] = new_value;
        }
    }

    /* Hunt for counter-like values (1-99) and flip them */
    for (hunt = 0; hunt < 20; hunt++)
    {
        addr = rand() % 0x8000;
        if (work_ram[addr] >= 1 && work_ram[addr] <= 99)
        {
            work_ram[addr] = (rand() % 2) ? 0 : 255;
        }
    }

    /* Hunt for boolean-like flags and flip them */
    for (hunt = 0; hunt < 30; hunt++)
    {
        addr = rand() % 0x8000;
        if (work_ram[addr] == 0x00 || work_ram[addr] == 0x01)
        {
            work_ram[addr] = work_ram[addr] ? 0x00 : 0xFF;
        }
    }
}

/* ======================================================================== */
/* Pre-render hook: called after VBlank DMA, before Active Display          */
/* This ensures CRAM modifications aren't overwritten by game palette DMA   */
/* ======================================================================== */

void chaos_pre_render_hook(void)
{
    int dirty = 0;

    /* Apply deferred CRAM randomize */
    if (cram_randomize_pending)
    {
        int i, j;
        uint8 tmp;
        for (i = 0; i < 0x80; i++)
        {
            j = rand() % 0x80;
            tmp = cram[i];
            cram[i] = cram[j];
            cram[j] = tmp;
        }
        cram_randomize_pending = 0;
        dirty = 1;
    }

    /* Apply deferred CRAM shift */
    if (cram_shift_pending)
    {
        int i;
        for (i = 0; i < 0x7F; i++)
        {
            cram[i] = cram[i + 1];
        }
        cram_shift_pending = 0;
        dirty = 1;
    }

    /* Persistent CRAM corruption */
    if (cram_corruption_enabled)
    {
        int i;
        for (i = 0; i < 8; i++)
        {
            int idx = rand() % 0x80;
            cram[idx] = rand() % 256;
        }
        dirty = 1;
    }

    if (dirty)
    {
        mark_all_cram_dirty();
    }
}

/* ======================================================================== */
/* Per-frame update (persistent effects)                                    */
/* ======================================================================== */

void chaos_per_frame_update(void)
{
    /* Persistent FM corruption: inject random frequency/volume corruption */
    if (fm_corruption_enabled)
    {
        int channel;
        for (channel = 0; channel < 6; channel++)
        {
            int bank = (channel < 3) ? 0 : 2;
            int ch_offset = channel % 3;

            /* Corrupt frequency registers (most noticeable) */
            if (rand() % 3 == 0) /* 33% chance per channel per frame */
            {
                int freq_reg = 0xA0 + ch_offset;
                int corrupted_val = rand() % 256;
                YM2612Write(bank, freq_reg);
                YM2612Write(bank + 1, corrupted_val);
            }

            /* Corrupt volume registers occasionally */
            if (rand() % 5 == 0) /* 20% chance */
            {
                int op = rand() % 4;
                int vol_reg = 0x40 + ch_offset + (op * 4);
                YM2612Write(bank, vol_reg);
                YM2612Write(bank + 1, rand() % 128);
            }

            /* Corrupt envelope parameters occasionally */
            if (rand() % 8 == 0) /* 12.5% chance */
            {
                int op = rand() % 4;
                int env_base = 0x50 + (rand() % 5) * 0x10; /* 0x50-0x90 range */
                int env_reg = env_base + ch_offset + (op * 4);
                YM2612Write(bank, env_reg);
                YM2612Write(bank + 1, rand() % 256);
            }
        }

        /* Occasionally corrupt algorithm/feedback */
        if (rand() % 10 == 0)
        {
            int ch = rand() % 6;
            int bank = (ch < 3) ? 0 : 2;
            int ch_offset = ch % 3;
            int alg_reg = 0xB0 + ch_offset;
            YM2612Write(bank, alg_reg);
            YM2612Write(bank + 1, rand() % 256);
        }
    }
}
