//! cpu info window
const MainWindow = @This();

const zsdl3 = @import("zsdl3");

const Ppu = @import("../core/ppu/Ppu.zig");

window: *zsdl3.SDL_Window = undefined,
renderer: *zsdl3.SDL_Renderer = undefined,
screen_texture: *zsdl3.SDL_Texture = undefined,
screen: []const u32 = undefined,

pub fn init(screen: []const u32) !MainWindow {
    var main_window = MainWindow{
        .screen = screen,
    };

    // Main game window
    main_window.window = zsdl3.createWindow(
        "Game Boy Color Emulator",
        Ppu.SCREEN_WIDTH * 2,
        Ppu.SCREEN_HEIGHT * 2,
        zsdl3.SDL_WINDOW_RESIZABLE,
    ) orelse return error.SDLWindowFailed;

    // renderer for the game window
    main_window.renderer = zsdl3.createRenderer(main_window.window, null) orelse return error.SDLRendererFailed;
    // gbc screen should not stretch to fill the window
    _ = zsdl3.setRenderLogicalPresentation(
        main_window.renderer,
        Ppu.SCREEN_WIDTH,
        Ppu.SCREEN_HEIGHT,
        zsdl3.SDL_LOGICAL_PRESENTATION_LETTERBOX,
    );

    main_window.screen_texture = zsdl3.createTexture(
        main_window.renderer,
        zsdl3.SDL_PIXELFORMAT_ARGB8888,
        zsdl3.SDL_TEXTUREACCESS_STREAMING,
        Ppu.SCREEN_WIDTH,
        Ppu.SCREEN_HEIGHT,
    ) orelse return error.SDLTextureFailed;
    // No blurring between pixels
    _ = zsdl3.setTextureScaleMode(main_window.screen_texture, zsdl3.SDL_SCALEMODE_NEAREST);

    return main_window;
}

pub fn deinit(self: *MainWindow) void {
    zsdl3.destroyWindow(self.window);
    zsdl3.destroyRenderer(self.renderer);
    zsdl3.destroyTexture(self.screen_texture);
}

pub fn render(self: *MainWindow) void {
    _ = zsdl3.renderClear(self.renderer);

    _ = zsdl3.updateTexture(
        self.screen_texture,
        null, // null means whole texture
        self.screen.ptr,
        Ppu.SCREEN_WIDTH * 4, // pitch (bytes per row) = width * 4 (bytes per pixel)
    );

    _ = zsdl3.renderTexture(
        self.renderer,
        self.screen_texture,
        null, // src rect (null means whole texture)
        null, // dest rect (null means whole window)
    );

    _ = zsdl3.renderPresent(self.renderer);
}
