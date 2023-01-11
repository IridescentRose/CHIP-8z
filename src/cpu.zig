const std = @import("std");
const cstd = @cImport(@cInclude("stdlib.h"));
const time = @cImport(@cInclude("time.h"));

/// Current Operation Code
current_opcode: u16,

/// Memory Map
///
/// 0x000-0x1FF - Interpreter
///     0x050-0x0A0 - Used for 4x5 pixel font set
/// 0x200-0xFFF - Program ROM & Working RAM
memory: [4096]u8,

/// Graphics
/// 64 x 32 array of monochrome
graphics: [64 * 32]u8,

/// 16 Registers V0-VF
registers: [16]u8,

index: u16,
program_counter: u16,

/// Timer registers
delay_timer: u8,
sound_timer: u8,

/// Stack and Stack Pointer
stack: [32]u16,
sp: u16,

/// Keys
/// Chip 8 has a HEX keypad. This stores the key
keys: [16]u8,

const chip8_fontset = [_]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};

const Self = @This();

pub fn init(self: *Self) !void {
    cstd.srand(@intCast(u32, time.time(0)));

    self.program_counter = 0x200;
    self.current_opcode = 0x00;
    self.index = 0x00;
    self.sp = 0x00;

    // Clear display
    for (self.graphics) |*g| {
        g.* = 0x00;
    }

    // Clear stack
    for (self.stack) |*s| {
        s.* = 0x00;
    }

    // Clear registers
    for (self.registers) |*r| {
        r.* = 0x00;
    }

    // Clear memory
    for (self.memory) |*v| {
        v.* = 0x00;
    }

    // Clear key
    for (self.keys) |*k| {
        k.* = 0x00;
    }

    // Set fonts
    for (chip8_fontset) |c, idx| {
        self.memory[idx] = c;
    }

    self.delay_timer = 0;
    self.sound_timer = 0;
}

fn increment_pc(self: *Self) void {
    self.program_counter += 2;
}

pub fn cycle(self: *Self) !void {
    if (self.program_counter > 0xFFF)
        @panic("OPcode out of range! Your program has an error!");

    self.current_opcode = @intCast(u16, self.memory[self.program_counter]) << 8 | self.memory[self.program_counter + 1];

    if (self.current_opcode == 0x00E0) { // CLS
        for (self.graphics) |*g| {
            g.* = 0;
        }
        self.increment_pc();
    } else if (self.current_opcode == 0x00EE) { // RET
        self.sp -= 1;
        self.program_counter = self.stack[self.sp];
        self.increment_pc();
    } else {
        var first = self.current_opcode >> 12;

        switch (first) {
            0x0 => {
                std.debug.print("SYS INSTR!\n", .{});
                self.increment_pc();
            }, // Unimplemented system instructions

            0x1 => {
                self.program_counter = self.current_opcode & 0x0FFF;
            }, // Jump to NNN

            0x2 => {
                self.stack[self.sp] = self.program_counter;
                self.sp += 1;
                self.program_counter = self.current_opcode & 0x0FFF;
            }, // Call NNN, stack gets pushed

            0x3 => {
                var x = (self.current_opcode & 0x0F00) >> 8;

                if (self.registers[x] == self.current_opcode & 0x00FF) {
                    self.increment_pc();
                }

                self.increment_pc();
            }, // Skips next instruction if Vx == kk

            0x4 => {
                var x = (self.current_opcode & 0x0F00) >> 8;

                if (self.registers[x] != self.current_opcode & 0x00FF) {
                    self.increment_pc();
                }

                self.increment_pc();
            }, // Skips next instruction if Vx != kk

            0x5 => {
                var x = (self.current_opcode & 0x0F00) >> 8;
                var y = (self.current_opcode & 0x00F0) >> 4;

                if (self.registers[x] == self.registers[y]) {
                    self.increment_pc();
                }
                self.increment_pc();
            }, // Skip next instruction if Vx = Vy

            0x6 => {
                var x = (self.current_opcode & 0x0F00) >> 8;
                self.registers[x] = @truncate(u8, self.current_opcode & 0x00FF);
                self.increment_pc();
            }, // Set Vx = kk

            0x7 => {
                @setRuntimeSafety(false);
                var x = (self.current_opcode & 0x0F00) >> 8;
                self.registers[x] += @truncate(u8, self.current_opcode & 0x00FF);
                self.increment_pc();
            }, // Set Vx = Vx + kk

            0x8 => {
                var x = (self.current_opcode & 0x0F00) >> 8;
                var y = (self.current_opcode & 0x00F0) >> 4;
                var m = (self.current_opcode & 0x000F);

                switch (m) {
                    0 => {
                        self.registers[x] = self.registers[y];
                    },
                    1 => {
                        self.registers[x] |= self.registers[y];
                    },
                    2 => {
                        self.registers[x] &= self.registers[y];
                    },
                    3 => {
                        self.registers[x] ^= self.registers[y];
                    },
                    4 => {
                        var sum: u16 = self.registers[x];
                        sum += self.registers[y];

                        self.registers[0xF] = if (sum > 255) 1 else 0;
                        self.registers[x] = @truncate(u8, sum & 0x00FF);
                    },
                    5 => {
                        @setRuntimeSafety(false);
                        self.registers[0xF] = if (self.registers[x] > self.registers[y]) 1 else 0;
                        self.registers[x] -= self.registers[y];
                    },
                    6 => {
                        self.registers[0xF] = self.registers[x] & 0b00000001;
                        self.registers[x] >>= 1;
                    },
                    7 => {
                        @setRuntimeSafety(false);
                        self.registers[0xF] = if (self.registers[y] > self.registers[x]) 1 else 0;
                        self.registers[x] = self.registers[y] - self.registers[x];
                    },
                    0xE => {
                        self.registers[0xF] = if (self.registers[x] & 0b10000000 != 0) 1 else 0;
                        self.registers[x] <<= 1;
                    },

                    else => {
                        std.debug.print("CURRENT ALU OP: {x}\n", .{self.current_opcode});
                    },
                }

                self.increment_pc();
            }, // ALU instructions

            0x9 => {
                var x = (self.current_opcode & 0x0F00) >> 8;
                var y = (self.current_opcode & 0x00F0) >> 4;

                if (self.registers[x] != self.registers[y]) {
                    self.increment_pc();
                }
                self.increment_pc();
            }, // Skip next instruction if vx != vy

            0xA => {
                self.index = self.current_opcode & 0x0FFF;
                self.increment_pc();
            }, // Set I

            0xB => {
                self.program_counter = (self.current_opcode & 0x0FFF) + @intCast(u16, self.registers[0]);
            }, // JMP to V0 + NNN

            0xC => {
                var x = (self.current_opcode & 0x0F00) >> 8;
                var kk = self.current_opcode & 0x00FF;

                self.registers[x] = @truncate(u8, @bitCast(u32, cstd.rand()) & kk);
                self.increment_pc();
            }, // Generate random number into X and AND with kk

            0xD => {
                self.registers[0xF] = 0;

                var registerX = self.registers[(self.current_opcode & 0x0F00) >> 8];
                var registerY = self.registers[(self.current_opcode & 0x00F0) >> 4];
                var height = self.current_opcode & 0x000F;

                var y : usize = 0;
                while(y < height) : (y += 1) {
                    var spr = self.memory[self.index + y];

                    var x : usize = 0;
                    while(x < 8) : (x += 1) {
                        const v : u8 = 0x80;
                        if((spr & (v >> @intCast(u3, x))) != 0) {
                            var tX = (registerX + x) % 64;
                            var tY = (registerY + y) % 32;

                            var idx = tX + tY * 64;

                            self.graphics[idx] ^= 1;

                            if(self.graphics[idx] == 0) {
                                self.registers[0x0F] = 1;
                            }
                        }
                    }
                }

                self.increment_pc();
            }, // Draw

            0xE => {
                var x = (self.current_opcode & 0x0F00) >> 8;
                var m = self.current_opcode & 0x00FF;

                if(m == 0x9E) {
                    if(self.keys[self.registers[x]] == 1){
                        self.increment_pc();
                    }
                } else if(m == 0xA1) {
                    if(self.keys[self.registers[x]] != 1){
                        self.increment_pc();
                    }
                }
                self.increment_pc();
            }, // Misc

            0xF => {
                var x = (self.current_opcode & 0x0F00) >> 8;
                var m = self.current_opcode & 0x00FF;

                if (m == 0x07) {
                    self.registers[x] = self.delay_timer;
                } else if (m == 0x0A) {
                    var key_pressed = false;

                    var i : usize = 0;
                    while(i < 16) : (i += 1) {
                        if(self.keys[i] != 0) {
                            self.registers[x] = @truncate(u8, i);
                            key_pressed = true;
                        }
                    }
                    
                    if(!key_pressed)
                        return;
                } else if (m == 0x15) {
                    self.delay_timer = self.registers[x];
                } else if (m == 0x18) {
                    self.sound_timer = self.registers[x];
                } else if (m == 0x1E) {
                    self.registers[0xF] = if(self.index + self.registers[x] > 0xFFF) 1 else 0;
                    self.index += self.registers[x];
                } else if (m == 0x29) {
                    self.index = self.registers[x] * 0x5;
                } else if (m == 0x33) {
                    self.memory[self.index] = self.registers[x] / 100;
                    self.memory[self.index + 1] = (self.registers[x] / 10) % 10;
                    self.memory[self.index + 2] = self.registers[x] % 10;
                } else if (m == 0x55) {
                    var i: usize = 0;
                    while (i <= x) : (i += 1) {
                        self.memory[self.index + i] = self.registers[i];
                    }
                } else if (m == 0x65) {
                    var i: usize = 0;
                    while (i <= x) : (i += 1) {
                        self.registers[i] = self.memory[self.index + i];
                    }
                }

                self.increment_pc();
            }, // MISC

            else => {
                std.debug.print("CURRENT OP: {x}\n", .{self.current_opcode});
            },
        }
    }

    if (self.delay_timer > 0) 
        self.delay_timer -= 1;

    if (self.sound_timer > 0) {
        //TODO: Sound!
        self.sound_timer -= 1;
    }
}
