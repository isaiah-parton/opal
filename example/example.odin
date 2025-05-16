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

FILLER_TEXT :: "Algo de texto que puedes seleccionar si gusta."

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

	sdl3app.state = new_clone(My_App {
		run = true,
		on_start = proc(app: ^sdl3app.App) {
			app := (^My_App)(app)
			lucide.load()
			components.theme.icon_font = &lucide.font
			app.image = opal.load_image("image.png") or_else panic("Could not load image!")
		},
		on_frame = proc(app: ^sdl3app.App) {
			app := (^My_App)(app)
			using opal, components
			begin()
			begin_node(
				&{
					size = kn.get_size(),
					style = {
						background = tw.NEUTRAL_950,
						stroke = tw.NEUTRAL_600,
						stroke_width = 1,
					},
					vertical = true,
					padding = 1,
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
						style = {background = tw.NEUTRAL_900},
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
				app.enable_window_grab =
					(title_node.is_hovered || title_node.has_hovered_child) &&
					!global_ctx.widget_hovered
				app.window_grab_box = title_node.box

				do_node(
					&{
						size = {0, 1},
						grow = {true, false},
						max_size = INFINITY,
						background = tw.NEUTRAL_600,
					},
				)

				begin_node(&{max_size = INFINITY, grow = true, content_align = 0.5})
				{
					begin_node(
						&{
							fit = 1,
							radius = 7,
							background = tw.NEUTRAL_800,
							padding = 8,
							spacing = 8,
						},
					)
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
									on_animate = proc(self: ^Node) {
										node_update_transition(self, 0, self.is_hovered, 0.1)
										self.style.background = fade(
											tw.NEUTRAL_700,
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
									on_animate = proc(self: ^Node) {
										node_update_transition(self, 0, self.is_hovered, 0.1)
										self.style.background = fade(
											tw.NEUTRAL_700,
											self.transitions[0],
										)
									},
								},
								loc,
							)
						}
						do_icon(lucide.BOLD)
						do_icon(lucide.ITALIC)
						do_icon(lucide.STRIKETHROUGH)
						do_icon(lucide.UNDERLINE)
						do_node(
							&{
								size = {2, 0},
								max_size = {0, INFINITY},
								grow = {false, true},
								background = tw.NEUTRAL_700,
							},
						)

					}
					end_node()
				}
				end_node()
			}
			end_node()
			end()
		},
	})

	sdl3app.run(&{width = 1000, height = 800, min_width = 500, min_height = 400, vsync = true})
}
