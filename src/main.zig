const std = @import("std");
const sdl = @cImport(
    @cInclude("SDL.h")
);

pub fn println(msg: []const u8) void {
    std.debug.print("{s}\n", .{msg});
}

var window: ?*sdl.SDL_Window = null;
var window_surface: ?*sdl.SDL_Surface = null;

pub fn create_window() void {
    window = sdl.SDL_CreateWindow("CHIP-8z", sdl.SDL_WINDOWPOS_CENTERED, sdl.SDL_WINDOWPOS_CENTERED, 1024, 512, 0);
    if(window == null) {
        @panic("SDL Window Creation Failed!");
    }

    window_surface = sdl.SDL_GetWindowSurface(window);
    if(window_surface == null) {
        @panic("SDL Window Surface Creation Failed!");
    }

    _ = sdl.SDL_UpdateWindowSurface(window);
}

pub fn init() void {
    println("CHIP-8z Started!");
    println("Initializing SDL!");

    if(sdl.SDL_Init(sdl.SDL_INIT_VIDEO | sdl.SDL_INIT_AUDIO) < 0) {
        @panic("SDL Initialization Failed!");
    }

    create_window();
}

pub fn deinit() void {
    sdl.SDL_DestroyWindow(window);
    window = null;

    println("Quitting SDL!");
    sdl.SDL_Quit();
    println("CHIP-8z Exitting!");
}

pub fn main() !void {
    init();
    defer deinit();

    var keep_open = true;
    while(keep_open) {
        var e: sdl.SDL_Event = undefined;
        while(sdl.SDL_PollEvent(&e) > 0) {
            switch(e.@"type") {
                sdl.SDL_QUIT => keep_open = false,
                else => {}
            }
        }


        _ = sdl.SDL_UpdateWindowSurface(window);
    }

}