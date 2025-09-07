/**
 * @file
 * DGen v1.13+
 * Megadrive's VDP C++ module
 *
 * A useful resource for the Genesis VDP:
 * http://cgfm2.emuviews.com/txt/genvdp.txt
 * Thanks to Charles MacDonald for writing these docs.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <algorithm>
#include "md.h"

/** Reset the VDP. */
void md_vdp::reset()
{
  fprintf(stderr, "VDP RESET CALLED! Flag address: %p, was: %d\n", (void*)&cram_corruption_enabled, (int)cram_corruption_enabled);
  hint_pending = false;
  vint_pending = false;
  cmd_pending = false;
  rw_mode = 0x00;
  rw_addr = 0;
  rw_dma = 0;
  memset(mem, 0, sizeof(mem));
  memset(reg, 0, 0x20);
  memset(dirt, 0xff, 0x35); // mark everything as changed
  memset(highpal, 0, sizeof(highpal));
  memset(sprite_order, 0, sizeof(sprite_order));
  memset(sprite_mask, 0xff, sizeof(sprite_mask));
  sprite_base = NULL;
  sprite_count = 0;
  masking_sprite_index_cache = -1;
  dots_cache = 0;
  sprite_overflow_line = INT_MIN;
  dest = NULL;
  bmap = NULL;
  cram_corruption_enabled = false;
  fprintf(stderr, "VDP RESET COMPLETE! Flag now: %d\n", (int)cram_corruption_enabled);
}

/**
 * VDP constructor.
 *
 * @param md The md instance this VDP belongs to.
 */
md_vdp::md_vdp(md &md) : belongs(md)
{
  vram = (mem + 0x00000);
  cram = (mem + 0x10000);
  vsram = (mem + 0x10080);
  dirt = (mem + 0x10100); // VRAM/CRAM/Reg dirty buffer bitfield
  // Also in 0x34 are global dirt flags (inclduing VSRAM this time)
  Bpp = Bpp_times8 = 0;
  cram_corruption_enabled = false;
  reset();
}

/**
 * VDP destructor.
 */
md_vdp::~md_vdp()
{
  vram = cram = vsram = NULL;
}

/** Calculate the DMA length. */
int md_vdp::dma_len()
{
  return (reg[0x14] << 8) + reg[0x13];
}

/** Calculate DMA start address. */
int md_vdp::dma_addr()
{
  int addr = 0;
  addr = (reg[0x17] & 0x7f) << 17;
  addr += reg[0x16] << 9;
  addr += reg[0x15] << 1;
  return addr;
}

/**
 * Do a DMA read.
 * DMA can read from anywhere.
 *
 * @param addr Address where to read from.
 * @return Byte read at "addr".
 */
unsigned char md_vdp::dma_mem_read(int addr)
{
  return belongs.misc_readbyte(addr);
}

/**
 * Set value in VRAM.
 * Must go through these calls to update the dirty flags.
 *
 * @param addr Address to write to.
 * @param d Byte to write.
 * @return Always 0.
 */
int md_vdp::poke_vram(int addr, unsigned char d)
{
  addr &= 0xffff;
  if (vram[addr] != d)
  {
    // Store dirty information down to 256 byte level in bits
    int byt, bit;
    byt = addr >> 8;
    bit = byt & 7;
    byt >>= 3;
    byt &= 0x1f;
    dirt[0x00 + byt] |= (1 << bit);
    dirt[0x34] |= 1;
    vram[addr] = d;
  }
  return 0;
}

/**
 * Set value in CRAM.
 *
 * @param addr Address to write to.
 * @param d Byte to write.
 * @return Always 0.
 */
int md_vdp::poke_cram(int addr, unsigned char d)
{
  addr &= 0x007f;
 
  // Debug: Show flag state every few CRAM writes
  // static int debug_counter = 0;
  // if (++debug_counter % 50 == 0) {
  //   fprintf(stderr, "CRAM poke #%d: flag at %p = %d\n", debug_counter, (void*)&cram_corruption_enabled, (int)cram_corruption_enabled);
  // }
  
  if (cram[addr] != d)
  {
    // Store dirty information down to 1byte level in bits
    int byt, bit;
    byt = addr;
    bit = byt & 7;
    byt >>= 3;
    byt &= 0x0f;
    dirt[0x20 + byt] |= (1 << bit);
    dirt[0x34] |= 2;
    cram[addr] = d;
  }

  return 0;
}

/**
 * Set value in VSRAM.
 *
 * @param addr Address to write to.
 * @param d Byte to write.
 * @return Always 0.
 */
int md_vdp::poke_vsram(int addr, unsigned char d)
{
  //  int diff=0;
  addr &= 0x007f;
  if (vsram[addr] != d)
  {
    dirt[0x34] |= 4;
    vsram[addr] = d;
  }
  return 0;
}

/**
 * Write a word to memory and update dirty flags.
 *
 * @param d 16-bit data to write.
 * @return Always 0.
 */
int md_vdp::putword(unsigned short d)
{
  // Called by dma or a straight write
  switch (rw_mode)
  {
  case 0x04:
    if (rw_addr & 0x0001)
    {
      poke_vram((rw_addr + 0), (d & 0xff));
      poke_vram((rw_addr + 1), (d >> 8));
    }
    else
    {
      poke_vram((rw_addr + 0), (d >> 8));
      poke_vram((rw_addr + 1), (d & 0xff));
    }
    break;
  case 0x0c:
    poke_cram((rw_addr + 0), (d >> 8));
    poke_cram((rw_addr + 1), (d & 0xff));
    break;
  case 0x14:
    poke_vsram((rw_addr + 0), (d >> 8));
    poke_vsram((rw_addr + 1), (d & 0xff));
    break;
  }
  rw_addr += reg[15];
  return 0;
}

/**
 * Write a byte to memory and update dirty flags.
 *
 * @param d 8-bit data to write.
 * @return Always 0.
 */
int md_vdp::putbyte(unsigned char d)
{
  // Called by dma or a straight write
  switch (rw_mode)
  {
  case 0x04:
    poke_vram(rw_addr, d);
    break;
  case 0x0c:
    poke_cram(rw_addr, d);
    break;
  case 0x14:
    poke_vsram(rw_addr, d);
    break;
  }
  rw_addr += reg[15];
  return 0;
}

#undef MAYCHANGE

/**
 * Read a word from memory.
 *
 * @return Read word.
 */
unsigned short md_vdp::readword()
{
  // Called by a straight read only
  unsigned short result = 0x0000;
  switch (rw_mode)
  {
  case 0x00:
    result = (vram[(rw_addr + 0) & 0xffff] << 8) +
             vram[(rw_addr + 1) & 0xffff];
    break;
  case 0x20:
    result = (cram[(rw_addr + 0) & 0x007f] << 8) +
             cram[(rw_addr + 1) & 0x007f];
    break;
  case 0x10:
    result = (vsram[(rw_addr + 0) & 0x007f] << 8) +
             vsram[(rw_addr + 1) & 0x007f];
    break;
  }
  rw_addr += reg[15];
  return result;
}

/**
 * Read a byte from memory.
 *
 * @return Read byte.
 */
unsigned char md_vdp::readbyte()
{
  // Called by a straight read only
  unsigned char result = 0x00;
  switch (rw_mode)
  {
  case 0x00:
    result = vram[(rw_addr + 0) & 0xffff];
    break;
  case 0x20:
    result = cram[(rw_addr + 0) & 0x007f];
    break;
  case 0x10:
    result = vsram[(rw_addr + 0) & 0x007f];
    break;
  }
  rw_addr += reg[15];
  return result;
}

/**
 * VDP commands
 *
 * A VDP command is 32-bits in length written into the control port
 * as two 16-bit words. The VDP maintains a pending flag so that it knows
 * what to expect next.
 *
 *  CD1 CD0 A13 A12 A11 A10 A09 A08     (D31-D24)
 *  A07 A06 A05 A04 A03 A02 A01 A00     (D23-D16)
 *   ?   ?   ?   ?   ?   ?   ?   ?      (D15-D8)
 *  CD5 CD4 CD3 CD2  ?   ?  A15 A14     (D7-D0)
 *
 * Where CD* indicates which ram is read or written in subsequent
 * data port read/writes. A* is an address.
 *
 * Note that the command is not cached, but rather, the lower 14 address bits
 * are commited as soon as the first half of the command arrives. Then when
 * the second word arrives, the remaining two address bits are commited.
 *
 * It is possible to cancel (but not roll back) a pending command by:
 *  - reading or writing to the data port.
 *  - reading the control port.
 *
 * In these cases the pending flag is cleared, and the first half of
 * the command remains comitted.
 *
 * @return Always 0.
 */
int md_vdp::command(uint16_t cmd)
{
  if (cmd_pending) // If this is the second word of a command
  {
    uint16_t A14_15 = (cmd & 0x0003) << 14;
    rw_addr = (rw_addr & 0xffff3fff) | A14_15;

    // Copy rw_addr to mirror register
    rw_addr = (rw_addr & 0x0000ffff) | (rw_addr << 16);

    // CD{4,3,2}
    uint16_t CD4_2 = (cmd & 0x0070);
    rw_mode |= CD4_2;

    // if CD5 == 1
    rw_dma = ((cmd & 0x80) == 0x80);

    cmd_pending = false;
  }
  else // This is the first word of a command
  {
    // masking away command bits CD1 CD0
    uint16_t A00_13 = cmd & 0x3fff;
    rw_addr = (rw_addr & 0xffffc000) | A00_13;

    // Copy rw_addr to mirror register
    rw_addr = (rw_addr & 0x0000ffff) | (rw_addr << 16);

    // CD {1,0}
    uint16_t CD0_1 = (cmd & 0xc000) >> 12;
    rw_mode = CD0_1;
    rw_dma = 0;

    // we will expect the second half of the command next
    cmd_pending = true;

    return 0;
  }

  // if it's a dma request do it straight away
  if (rw_dma)
  {
    int mode = (reg[0x17] >> 6) & 3;
    int s = 0, d = 0, i = 0, len = 0;
    s = dma_addr();
    d = rw_addr;
    len = dma_len();
    (void)d;
    switch (mode)
    {
    case 0:
    case 1:
      for (i = 0; i < len; i++)
      {
        unsigned short val;
        val = dma_mem_read(s++);
        val <<= 8;
        val |= dma_mem_read(s++);
        putword(val);
      }
      break;
    case 2:
      // Done later on (VRAM fill I believe)
      break;
    case 3:
      for (i = 0; i < len; i++)
      {
        unsigned short val;
        val = vram[(s++) & 0xffff];
        val <<= 8;
        val |= vram[(s++) & 0xffff];
        putword(val);
      }
      break;
    }
  }

  return 0;
}

/**
 * Write a word to the VDP.
 *
 * @param d 16-bit data to write.
 * @return Always 0.
 */
int md_vdp::writeword(unsigned short d)
{
  if (rw_dma)
  {
    // This is the 'done later on' bit for words
    // Do a dma fill if it's set up:
    if (((reg[0x17] >> 6) & 3) == 2)
    {
      int i, len;
      len = dma_len();
      for (i = 0; i < len; i++)
        putword(d);
      return 0;
    }
  }
  else
  {
    putword(d);
    return 0;
  }
  return 0;
}

/**
 * Write a byte to the VDP.
 *
 * @param d 8-bit data to write.
 * @return Always 0.
 */
int md_vdp::writebyte(unsigned char d)
{
  if (rw_dma)
  {
    // This is the 'done later on' bit for bytes
    // Do a dma fill if it's set up:
    if (((reg[0x17] >> 6) & 3) == 2)
    {
      int i, len;
      len = dma_len();
      for (i = 0; i < len; i++)
        putbyte(d);
      return 0;
    }
  }
  else
  {
    putbyte(d);
    return 0;
  }

  return 0;
}

/**
 * Write away a VDP register.
 *
 * @param addr Address of register.
 * @param data 8-bit data to write.
 */
void md_vdp::write_reg(uint8_t addr, uint8_t data)
{
  uint8_t byt, bit;

  // store dirty information down to 1 byte level in bits
  if (reg[addr] != data)
  {
    byt = addr;
    bit = (byt & 7);
    byt >>= 3;
    byt &= 0x03;
    dirt[(0x30 + byt)] |= (1 << bit);
    dirt[0x34] |= 8;
  }
  reg[addr] = data;
  // "Writing to a VDP register will clear the code register."
  rw_mode = 0;
}

/**
 * Shift VRAM contents up by one byte.
 * This moves all data one byte earlier in memory.
 */
void md_vdp::shift_vram_up()
{
  fprintf(stderr, "Shifting VRAM up by 1 byte...\n");
  // Move all bytes one position up (toward lower addresses)
  for (int i = 0; i < 0xFFFF; i++)
  {
    poke_vram(i, vram[i + 1]);
  }
  // Clear the last byte
  // poke_vram(0xFFFF, 0);
}

/**
 * Shift VRAM contents down by one byte.
 * This moves all data one byte later in memory.
 */
void md_vdp::shift_vram_down()
{
  fprintf(stderr, "Shifting VRAM down by 1 byte...\n");
  // Move all bytes one position down (toward higher addresses)
  for (int i = 0xFFFF; i > 0; i--)
  {
    poke_vram(i, vram[i - 1]);
  }
  // Clear the first byte
  // poke_vram(0, 0);
}

/**
 * Shift VRAM contents down by a random number of bytes in range 0-63.
 */
void md_vdp::shift_vram_down_random()
{
  int shift_amount = rand() % 64; // Get a random number between 0 and 63
  fprintf(stderr, "Shifting VRAM down by %d bytes...\n", shift_amount);
  // Move all bytes down by the shift amount
  for (int i = 0xFFFF; i > shift_amount; i--)
  {
    poke_vram(i, vram[i - shift_amount]);
  }
  // Clear the first few bytes
  for (int i = 0; i < shift_amount; i++)
  {
    poke_vram(i, 0);
  }
}

/**
 * Randomize color entries in CRAM. Produces acid trip color swaps without destroying tile data.
 */
void md_vdp::randomize_cram()
{
  fprintf(stderr, "Randomizing CRAM...\n");
  // Randomly swap color entries in CRAM
  for (int i = 0; i < 0x100; i++)
  {
    int j = rand() % 0x100;
    std::swap(cram[i], cram[j]);
  }

  // Mark all CRAM as dirty
  memset(dirt + 0x20, 0xFF, 0x10);
  dirt[0x34] |= 2;
}

/**
 * Enable persistent CRAM corruption mode.
 * When enabled, all CRAM writes will be corrupted in real-time.
 */
void md_vdp::enable_cram_corruption()
{
  fprintf(stderr, "Enabling persistent CRAM corruption mode...\n");
  fprintf(stderr, "Flag address: %p, current value: %d\n", (void*)&cram_corruption_enabled, (int)cram_corruption_enabled);
  cram_corruption_enabled = true;
  fprintf(stderr, "Flag set to: %d\n", (int)cram_corruption_enabled);
  // Mark all CRAM as dirty so changes are visible
  memset(dirt + 0x20, 0xFF, 0x10);
  dirt[0x34] |= 2;
}

/**
 * Disable persistent CRAM corruption mode.
 */
void md_vdp::disable_cram_corruption()
{
  fprintf(stderr, "Disabling persistent CRAM corruption mode...\n");
  fprintf(stderr, "Flag address: %p, current value: %d\n", (void*)&cram_corruption_enabled, (int)cram_corruption_enabled);
  cram_corruption_enabled = false;
  fprintf(stderr, "Flag set to: %d\n", (int)cram_corruption_enabled);
}

/**
 * Scramble sprite attribute table in VRAM.
 * This can cause sprites to flicker or disappear.
 */
void md_vdp::sprite_attribute_scramble()
{
  fprintf(stderr, "AGGRESSIVELY scrambling sprite attribute table...\n");
  
  // Get sprite attribute table base address from VDP register 5
  // Bits 15-9 of reg[5] contain the base address (in units of $200)
  int sprite_table_base = (reg[5] & 0x7F) << 9;
  
  // Genesis supports up to 80 sprites, each sprite entry is 8 bytes
  int max_sprites = 80;
  int sprite_entry_size = 8;
  
  fprintf(stderr, "Sprite table base: 0x%04X\n", sprite_table_base);

  // Apply MUCH more aggressive scrambling - target 80 out of 80 sprites!
  for (int i = 0; i < 80; i++) 
  {
    int sprite_index = rand() % max_sprites;
    int sprite_addr = sprite_table_base + (sprite_index * sprite_entry_size);
    
    int scramble_type = rand() % 10; // More scramble types
    switch (scramble_type)
    {
      case 0:
        // AGGRESSIVELY scramble Y position - make sprites fly all over
        {
          int y_pos = rand() % 1024 - 256; // Allow negative positions too
          poke_vram(sprite_addr + 0, (y_pos >> 8) & 0xFF);
          poke_vram(sprite_addr + 1, y_pos & 0xFF);
        }
        break;
        
      case 1:
        // AGGRESSIVELY scramble sprite size - create huge or tiny sprites
        {
          unsigned char size_byte = rand() % 256;
          // Force extreme sizes more often
          if (rand() % 3 == 0) {
            size_byte = 0xFF; // Maximum size
          }
          poke_vram(sprite_addr + 2, size_byte);
          
          // Also scramble the link field to break sprite chains
          poke_vram(sprite_addr + 3, rand() % 256);
        }
        break;
        
      case 2:
        // MASSIVELY scramble tile pattern and attributes
        {
          // Completely randomize both bytes
          poke_vram(sprite_addr + 4, rand() % 256);
          poke_vram(sprite_addr + 5, rand() % 256);
        }
        break;
        
      case 3:
        // AGGRESSIVELY scramble X position
        {
          int x_pos = rand() % 1024 - 256; // Allow off-screen positions
          poke_vram(sprite_addr + 6, (x_pos >> 8) & 0xFF);
          poke_vram(sprite_addr + 7, x_pos & 0xFF);
        }
        break;
        
      case 4:
        // Swap MULTIPLE sprite entries at once (create chaos)
        {
          for (int swap_count = 0; swap_count < 5; swap_count++) {
            int sprite2_index = rand() % max_sprites;
            int sprite2_addr = sprite_table_base + (sprite2_index * sprite_entry_size);
            
            for (int byte_offset = 0; byte_offset < sprite_entry_size; byte_offset++)
            {
              unsigned char temp = vram[sprite_addr + byte_offset];
              poke_vram(sprite_addr + byte_offset, vram[sprite2_addr + byte_offset]);
              poke_vram(sprite2_addr + byte_offset, temp);
            }
          }
        }
        break;
        
      case 5:
        // COMPLETELY randomize the entire sprite entry
        {
          for (int byte_offset = 0; byte_offset < sprite_entry_size; byte_offset++)
          {
            poke_vram(sprite_addr + byte_offset, rand() % 256);
          }
        }
        break;
        
      case 6:
        // Create "ghost sprites" by setting positions to 0
        {
          poke_vram(sprite_addr + 0, 0); // Y = 0
          poke_vram(sprite_addr + 1, 0);
          poke_vram(sprite_addr + 6, 0); // X = 0
          poke_vram(sprite_addr + 7, 0);
        }
        break;
        
      case 7:
        // Force sprites to maximum size and random positions
        {
          poke_vram(sprite_addr + 2, 0xFF); // Max size
          poke_vram(sprite_addr + 0, rand() % 256); // Random Y
          poke_vram(sprite_addr + 1, rand() % 256);
          poke_vram(sprite_addr + 6, rand() % 256); // Random X
          poke_vram(sprite_addr + 7, rand() % 256);
        }
        break;
        
      case 8:
        // Break sprite chains by corrupting link fields
        {
          poke_vram(sprite_addr + 3, rand() % 256); // Random link
          // Also corrupt the size/link byte
          poke_vram(sprite_addr + 2, rand() % 256);
        }
        break;
        
      case 9:
        // Create "stretchy" sprites by manipulating tile patterns
        {
          // Set weird tile patterns that might stretch
          unsigned short weird_pattern = rand() % 0xFFFF;
          poke_vram(sprite_addr + 4, (weird_pattern >> 8) & 0xFF);
          poke_vram(sprite_addr + 5, weird_pattern & 0xFF);
          
          // Also set maximum size
          poke_vram(sprite_addr + 2, 0xFF);
        }
        break;
    }
  }
  
  // ALSO corrupt the sprite table location register itself sometimes!
  if (rand() % 10 == 0) {
    unsigned char new_sprite_base = rand() % 128;
    write_reg(5, (reg[5] & 0x80) | new_sprite_base); // Keep bit 7, scramble bits 6-0
    fprintf(stderr, "Also scrambled sprite table base register!\n");
  }
  
  // Mark ALL of VRAM as dirty for maximum effect
  memset(dirt + 0x00, 0xFF, 0x20);
  dirt[0x34] |= 1;
  
  fprintf(stderr, "Aggressive sprite scrambling complete!\n");
}