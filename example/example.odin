package example

import opal ".."
import kn "../../katana"
import "../../katana/sdl3glue"
import "../lucide"
import "../sdl3app"
import tw "../tailwind_colors"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:mem"
import "core:strings"
import "core:time"
import "vendor:sdl3"
import "vendor:wgpu"

import "../components"

My_App :: struct {
	using app:             sdl3app.App,
	image:                 int,
	edited_text:           string,
	drag_offset:           [2]f32,
	inspector_position:    [2]f32,
	is_dragging_inspector: bool,
	boolean:               bool,
}

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	if !sdl3.Init({.VIDEO}) {
		panic("Could not initialize SDL3")
	}

	sdl3app.state = new_clone(
	My_App {
		run = true,
		on_start = proc(app: ^sdl3app.App) {
			app := (^My_App)(app)
			lucide.load()
			components.theme.icon_font = &lucide.font
			app.image = opal.load_image("image.png") or_else panic("Could not load image!")
			opal.set_color(.Selection_Background, tw.SKY_500)
			opal.set_color(.Selection_Foreground, tw.BLACK)
			opal.set_color(.Scrollbar_Background, tw.SLATE_800)
			opal.set_color(.Scrollbar_Foreground, tw.SLATE_500)
		},
		on_frame = proc(app: ^sdl3app.App) {
			app := (^My_App)(app)
			using opal, components
			window_radius :=
				app.radius * f32(i32(.MAXIMIZED not_in sdl3.GetWindowFlags(app.window)))
			begin()
			begin_node(
				&{
					size = kn.get_size(),
					background = tw.NEUTRAL_950,
					stroke = tw.NEUTRAL_800,
					stroke_width = 1,
					vertical = true,
					padding = 1,
					radius = window_radius,
					clip_content = window_radius > 0,
				},
			)
			{
				title_node := begin_node(
					&{
						fit = {0, 1},
						size = {0, 20},
						max_size = INFINITY,
						grow = {true, false},
						content_align = {0, 0.5},
						style = {background = tw.NEUTRAL_800},
					},
				)
				{
					do_node(&{grow = true, max_size = INFINITY})
					if do_window_button(lucide.CHEVRON_DOWN, tw.ROSE_500) {
						sdl3.MinimizeWindow(app.window)
					}
					if do_window_button(lucide.CHEVRON_UP, tw.ROSE_500) {
						if .MAXIMIZED in sdl3.GetWindowFlags(app.window) {
							sdl3.RestoreWindow(app.window)
						} else {
							sdl3.MaximizeWindow(app.window)
						}
					}
					if do_window_button(lucide.X, tw.ROSE_500) {
						app.run = false
					}
				}
				end_node()
				sdl3app.app_use_node_for_window_grabbing(app, title_node)

				begin_node(
					&{
						max_size        = INFINITY,
						grow            = true,
						// content_align = 0.5,
						spacing         = 5,
						padding         = 20,
						vertical        = true,
						clip_content    = true,
						show_scrollbars = true,
					},
				)
				do_text_editor_toolbar(app)
				// {
				// 	for i in 1 ..= 1000 {
				// 		push_id(i)
				// 		do_node(
				// 			&{
				// 				size = {0, 30},
				// 				max_size = INFINITY,
				// 				grow = {true, false},
				// 				background = tw.NEUTRAL_900,
				// 				foreground = tw.ROSE_500,
				// 				font_size = 14,
				// 				text = fmt.tprintf("Item #%i", i),
				// 				content_align = 0.5,
				// 			},
				// 		)
				// 		pop_id()
				// 	}
				// }
				end_node()
			}
			end_node()
			end()
		},
	},
	)

	sdl3app.run(
		&{
			width = 1000,
			height = 800,
			min_width = 500,
			min_height = 400,
			vsync = true,
			customize_window = true,
		},
	)
}

do_text_editor_toolbar :: proc(app: ^My_App) {
	using opal, components
	begin_node(&{fit = 1, radius = 7, background = tw.NEUTRAL_800, padding = 8, spacing = 8})
	{
		do_icon_button :: proc(icon: rune, loc := #caller_location) {
			do_node(
				&{
					text = string_from_rune(icon),
					font = theme.icon_font,
					font_size = 24,
					foreground = tw.WHITE,
					fit = 1,
					padding = 4,
					radius = 4,
					square_fit = true,
					content_align = 0.5,
					on_animate = proc(self: ^Node) {
						node_update_transition(self, 0, self.is_hovered, 0.1)
						node_update_transition(self, 1, self.is_active, 0.1)
						self.background = fade(
							mix(self.transitions[1], tw.NEUTRAL_700, tw.ROSE_600),
							self.transitions[0],
						)
					},
				},
				loc,
			)
		}
		do_toggle_icon_button :: proc(icon: rune, loc := #caller_location) {
			do_node(
				&{
					text = string_from_rune(icon),
					font = theme.icon_font,
					font_size = 24,
					foreground = tw.WHITE,
					fit = 1,
					padding = 4,
					radius = 4,
					square_fit = true,
					content_align = 0.5,
					on_animate = proc(self: ^Node) {
						node_update_transition(self, 0, self.is_hovered, 0.1)
						self.style.background = fade(tw.NEUTRAL_700, self.transitions[0])
					},
				},
				loc,
			)
		}
		do_icon_button(lucide.BOLD)
		do_icon_button(lucide.ITALIC)
		do_icon_button(lucide.STRIKETHROUGH)
		do_icon_button(lucide.UNDERLINE)
		do_node(
			&{
				size = {2, 0},
				max_size = {0, INFINITY},
				grow = {false, true},
				background = tw.NEUTRAL_700,
			},
		)
		do_icon_button(lucide.LIGHTBULB)
		toggle_switch := make_toggle_switch(&app.boolean)
		do_node(&toggle_switch)
		node := do_node(
			&{
				background = tw.NEUTRAL_950,
				stroke = tw.NEUTRAL_500,
				stroke_width = 1,
				clip_content = true,
				text = app.edited_text,
				font_size = 16,
				padding = 4,
				radius = 3,
				foreground = tw.NEUTRAL_50,
				fit = {0, 1},
				size = {200, 0},
				max_size = INFINITY,
				grow = {false, true},
				enable_edit = true,
				enable_selection = true,
				is_widget = true,
				stroke_type = .Outer,
				content_align = {0, 0.5},
				on_animate = proc(self: ^Node) {
					using opal
					node_update_transition(self, 0, self.is_hovered, 0.1)
					node_update_transition(self, 1, self.is_focused, 0.1)
					self.style.stroke = tw.LIME_500
					self.style.stroke_width = 3 * self.transitions[1]
				},
			},
		)
		if node.was_changed {
			delete(app.edited_text)
			app.edited_text = strings.clone(strings.to_string(node.builder))
		}

	}
	end_node()
}

