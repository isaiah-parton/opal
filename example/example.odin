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

	sdl3app.state = new_clone(My_App {
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
					min_size = kn.get_size(),
					background = tw.NEUTRAL_950,
					stroke = tw.NEUTRAL_800,
					stroke_width = 1,
					vertical = true,
					padding = 1,
					radius = window_radius,
					clip_content = window_radius > 0,
					interactive = true,
				},
			)
			{
				begin_node(
					&{
						fit = {0, 1},
						min_size = {0, 20},
						max_size = INFINITY,
						grow = {true, false},
						content_align = {0, 0.5},
						style = {background = tw.NEUTRAL_800},
					},
				)
				{
					grab_node := add_node(
						&{grow = true, max_size = INFINITY, interactive = true},
					).?
					sdl3app.app_use_node_for_window_grabbing(app, grab_node)
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

				begin_node(
					&{
						max_size = INFINITY,
						grow = true,
						content_align = 0.5,
						spacing = 5,
						padding = 20,
						interactive = true,
						clip_content = true,
						show_scrollbars = true,
					},
				)
				{
					do_text(
						`Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nunc quis malesuada metus, a placerat lacus. Mauris aliquet congue blandit. Praesent elementum efficitur lorem, sed mattis ipsum viverra a. Integer blandit neque eget ultricies commodo. In sapien libero, gravida sit amet egestas quis, pharetra non mi. In nec ligula molestie, placerat dui vitae, ultricies nisl. Curabitur ultrices iaculis urna, in convallis dui dictum id. Nullam suscipit, massa ac venenatis finibus, turpis augue ultrices dolor, at accumsan est sem eu dui. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae; Curabitur sem neque, varius in eros non, vestibulum condimentum ante. In molestie nulla non nulla pulvinar placerat. Nullam sit amet imperdiet turpis.`,
						true,
						0,
					)
					do_text(
						`Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nunc quis malesuada metus, a placerat lacus. Mauris aliquet congue blandit. Praesent elementum efficitur lorem, sed mattis ipsum viverra a. Integer blandit neque eget ultricies commodo. In sapien libero, gravida sit amet egestas quis, pharetra non mi. In nec ligula molestie, placerat dui vitae, ultricies nisl. Curabitur ultrices iaculis urna, in convallis dui dictum id. Nullam suscipit, massa ac venenatis finibus, turpis augue ultrices dolor, at accumsan est sem eu dui. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae; Curabitur sem neque, varius in eros non, vestibulum condimentum ante. In molestie nulla non nulla pulvinar placerat. Nullam sit amet imperdiet turpis.`,
						{true, false},
						1,
					)
				}
				end_node()
			}
			end_node()
			end()
		},
	})

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

do_text :: proc(text: string, grow: [2]bool, fit: [2]f32, loc := #caller_location) {
	using opal
	push_id(hash(loc))
	defer pop_id()
	words := strings.split(text, " ", allocator = context.temp_allocator)
	begin_node(
		&{
			max_size = {500, 500},
			grow = grow,
			padding = 10,
			fit = fit,
			enable_wrapping = true,
			stroke = tw.WHITE,
			stroke_width = 2,
			clip_content = true,
			spacing = kn.DEFAULT_FONT.space_advance * 14,
		},
	)
	for word, i in words {
		push_id(int(i))
		add_node(
			&{foreground = tw.WHITE, fit = 1, static_text = true, text = word, font_size = 14},
			loc = loc,
		)
		pop_id()
	}
	end_node()
}

do_text_editor :: proc(app: ^My_App, loc := #caller_location) {
	using opal, components
	push_id(hash(loc))
	defer pop_id()
	begin_node(
		&{
			fit = 1,
			grow = {true, false},
			max_size = {INFINITY, 0},
			padding = 8,
			background = tw.NEUTRAL_800,
			radius = 7,
			vertical = true,
			spacing = 8,
		},
	)
	{
		begin_node(&{fit = 1, spacing = 8, content_align = {0, 0.5}})
		{
			do_icon_button :: proc(icon: rune, loc := #caller_location) {
				self := add_node(
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
						interactive = true,
					},
					loc,
				).?
				node_update_transition(self, 0, self.is_hovered, 0.1)
				node_update_transition(self, 1, self.is_active, 0.1)
				self.background = fade(
					mix(self.transitions[1], tw.NEUTRAL_700, tw.ROSE_600),
					self.transitions[0],
				)
			}
			do_toggle_icon_button :: proc(icon: rune, loc := #caller_location) {
				self := add_node(
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
					},
					loc,
				).?
				node_update_transition(self, 0, self.is_hovered, 0.1)
				self.style.background = fade(tw.NEUTRAL_700, self.transitions[0])
			}
			//
			// Some text editing options
			//
			do_icon_button(lucide.BOLD)
			do_icon_button(lucide.ITALIC)
			do_icon_button(lucide.STRIKETHROUGH)
			do_icon_button(lucide.UNDERLINE)
			//
			// Add a visual separator
			//
			add_node(
				&{
					min_size = {2, 0},
					max_size = {0, INFINITY},
					grow = {false, true},
					background = tw.NEUTRAL_700,
				},
			)
			//
			// The toggle switch is a very simple component with fixed sizing so it can be added in one step
			//
			add_toggle_switch(&app.boolean)
		}
		end_node()
		//
		// Here I add a text field to the UI with a few steps
		//
		{
			// First, create the descriptor that will define the node as an editable input
			desc := make_field_descriptor(&app.edited_text, type_info_of(type_of(app.edited_text)))
			// Then apply my sizing preference
			desc.min_size = {300, 200}
			desc.grow = {true, false}
			desc.max_size = {INFINITY, 0}
			desc.placeholder = "Once upon a time..."
			desc.is_multiline = true
			desc.enable_wrapping = true
			// Then add the node to the UI and perform the input logic
			add_field(&desc)
		}
	}
	end_node()
}

