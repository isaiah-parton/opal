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
	inspector_position:    [2]f32,
	drag_offset:           [2]f32,
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
					begin_node(&{fit = 1, padding = 3, spacing = 3})
					{
						if do_menu("File") {
							do_menu_item("New", lucide.PLUS)
							do_menu_item("Open", lucide.FOLDER_OPEN)
							do_menu_item("Save", lucide.SAVE)
							do_menu_item("Save As", lucide.SAVE)
						}
						if do_menu("Edit") {
							do_menu_item("Undo", lucide.UNDO)
							do_menu_item("Redo", lucide.REDO)
						}
						if do_menu("Select") {
							do_menu_item("All", lucide.TEXT_SELECT)
							do_menu_item("Invert", lucide.LASSO_SELECT)
						}
						if do_menu("Object") {
							do_menu_item("Create", lucide.PLUS)
							do_menu_item("Delete", lucide.TRASH)
						}
						if do_menu("Help") {
							do_menu_item("Manual", lucide.BOOK)
							do_menu_item("Forum", lucide.MESSAGE_CIRCLE)
						}
					}
					end_node()
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

				begin_node(&{max_size = INFINITY, grow = true})
				{
					begin_node(&{max_size = INFINITY, grow = true, vertical = true})
					{
						begin_node(
							&{
								max_size = INFINITY,
								grow = {false, true},
								fit = {1, 0},
								padding = 5,
								spacing = 1,
								vertical = true,
							},
						)
						{
							do_button(lucide.FOLDER_PLUS, font = &lucide.font, font_size = 20)
							do_node(&{size = {0, 4}})
							do_button(lucide.WAND_SPARKLES, font = &lucide.font, font_size = 20)
							do_node(&{size = {0, 4}})
							do_button(
								lucide.MOVE_3D,
								font = &lucide.font,
								font_size = 20,
								radius = {3, 3, 0, 0},
							)
							do_button(
								lucide.ROTATE_3D,
								font = &lucide.font,
								font_size = 20,
								radius = 0,
							)
							do_button(
								lucide.SCALE_3D,
								font = &lucide.font,
								font_size = 20,
								radius = {0, 0, 3, 3},
							)
						}
						end_node()
					}
					end_node()

					do_node(
						&{
							size = {1, 0},
							grow = {false, true},
							max_size = INFINITY,
							style = {background = tw.NEUTRAL_600},
						},
					)

					begin_node(
						&{
							size = {200, 0},
							grow = {false, true},
							max_size = INFINITY,
							vertical = true,
							spacing = 4,
							padding = 10,
							content_align = 0.5,
							background = Radial_Gradient {
								center = {1, 0.5},
								radius = 0.5,
								inner = tw.NEUTRAL_800,
								outer = tw.NEUTRAL_900,
							},
						},
					)
					{
						do_node(
							&{
								size = 100,
								style = {
									radius = 50,
									background = Image_Paint{index = app.image, size = 1},
								},
							},
						)
						do_node(
							&{
								text = FILLER_TEXT,
								fit = {0, 1},
								grow = {true, false},
								max_size = INFINITY,
								enable_wrapping = true,
								enable_selection = true,
								padding = {0, 10, 0, 10},
								style = {font_size = 12, foreground = tw.NEUTRAL_200},
							},
						)
						do_button("Botón A")
						do_button("Botón B")

						toggle_switch := make_toggle_switch(nil)
						do_node(&toggle_switch)

						node := do_node(
							&{
								background = tw.NEUTRAL_950,
								stroke = tw.NEUTRAL_500,
								stroke_width = 1,
								clip_content = true,
								text = app.edited_text,
								font_size = 12,
								padding = 4,
								radius = 3,
								foreground = tw.NEUTRAL_50,
								fit = {0, 1},
								max_size = INFINITY,
								grow = {true, false},
								enable_edit = true,
								show_scrollbars = true,
								enable_selection = true,
								is_widget = true,
								stroke_type = .Outer,
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
				end_node()
			}
			end_node()
			end()
		},
	})

	sdl3app.run(&{width = 1000, height = 800, min_width = 500, min_height = 400})
}

