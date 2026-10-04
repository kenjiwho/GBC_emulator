//! scrollable text box for SDL3
const TextBox = @This();

const std = @import("std");
const zsdl3 = @import("zsdl3");

bounds: zsdl3.SDL_Rect,
scroll_y: f32 = 0,
max_scroll: f32 = 0,
content_height: f32 = 0,
text_data: [:0]const u8 = "",

pub fn init(x: c_int, y: c_int, w: c_int, h: c_int) TextBox {
    return TextBox{
        .bounds = .{ .x = x, .y = y, .w = w, .h = h },
    };
}

pub fn handle_wheel_event(self: *TextBox, wheel_y: f32, mouse_x: f32, mouse_y: f32) void {
    // Check if mouse is hovering inside the bounds
    const is_inside = mouse_x >= @as(f32, @floatFromInt(self.bounds.x)) and mouse_x <= @as(f32, @floatFromInt(self.bounds.x + self.bounds.w)) and
        mouse_y >= @as(f32, @floatFromInt(self.bounds.y)) and mouse_y <= @as(f32, @floatFromInt(self.bounds.y + self.bounds.h));
    if (is_inside) {
        self.scroll_y -= wheel_y * 20.0;
        self.scroll_y = std.math.clamp(self.scroll_y, 0, self.max_scroll);
    }
}

pub fn render(self: *TextBox, renderer: *zsdl3.SDL_Renderer, font: *zsdl3.ttf.TTF_Font) void {
    // lock drawing to this specific rectangle
    _ = zsdl3.setRenderClipRect(renderer, &self.bounds);
    // remove clipping so the rest of the UI can draw normally
    defer _ = zsdl3.setRenderClipRect(renderer, null);

    // white
    const text_color = zsdl3.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

    // wrap length of 0 means it only breaks on standard \n characters
    const surface = zsdl3.ttf.renderTextBlendedWrapped(font, self.text_data.ptr, self.text_data.len, text_color, self.bounds.w) orelse return;
    defer zsdl3.destroySurface(surface);
    const texture = zsdl3.createTextureFromSurface(renderer, surface) orelse return;
    defer zsdl3.destroyTexture(texture);
    // dynamically update scroll boundaries based on generated text height
    self.update_content_height(@floatFromInt(surface.h));

    const dest_rect = zsdl3.SDL_FRect{
        .x = @floatFromInt(self.bounds.x),
        .y = @as(f32, @floatFromInt(self.bounds.y)) - self.scroll_y,
        .w = @floatFromInt(surface.w),
        .h = @floatFromInt(surface.h),
    };
    _ = zsdl3.renderTexture(renderer, texture, null, &dest_rect);
}

pub fn resize(self: *TextBox, width: i32, height: i32) void {
    self.bounds.w = width;
    self.bounds.h = height;
    self.max_scroll = @max(0, self.content_height - @as(f32, @floatFromInt(self.bounds.h)));
    self.scroll_y = std.math.clamp(self.scroll_y, 0, self.max_scroll);
}

fn update_content_height(self: *TextBox, height: f32) void {
    self.content_height = height;
    self.max_scroll = @max(0, self.content_height - @as(f32, @floatFromInt(self.bounds.h)));
}
