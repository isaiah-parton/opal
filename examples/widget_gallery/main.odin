package widget_gallery

import kn "../../katana"
import "../../katana/sdl3glue"
import "../../lucide"
import opal "../../opal"
import "../../sdl3app"
import tw "../../tailwind_colors"
import "base:runtime"
import "core:bytes"
import "core:fmt"
import "core:math"
import "core:math/bits"
import "core:math/ease"
import "core:math/linalg"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:reflect"
import "core:slice"
import "core:strings"
import "core:time"
import "core:unicode"
import "vendor:sdl3"
import "vendor:wgpu"

FILLER_TEXT :: `Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nunc quis malesuada metus, a placerat lacus. Mauris aliquet congue blandit. Praesent elementum efficitur lorem, sed mattis ipsum viverra a. Integer blandit neque eget ultricies commodo. In sapien libero, gravida sit amet egestas quis, pharetra non mi. In nec ligula molestie, placerat dui vitae, ultricies nisl. Curabitur ultrices iaculis urna, in convallis dui dictum id. Nullam suscipit, massa ac venenatis finibus, turpis augue ultrices dolor, at accumsan est sem eu dui. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae; Curabitur sem neque, varius in eros non, vestibulum condimentum ante. In molestie nulla non nulla pulvinar placerat. Nullam sit amet imperdiet turpis.`

App :: struct {
	using app:     sdl3app.App,
	toggle_switch: bool,
	slider:        f32,
	text:          string,
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

	if !sdl3.Init({.VIDEO, .EVENTS}) {
		panic("Could not initialize SDL3")
	}

	sdl3app.state = new_clone(App {
		run = true,
		on_start = proc(app: ^sdl3app.App) {
			app := (^App)(app)
			opal.set_color(.Selection_Background, tw.SKY_500)
			opal.set_color(.Selection_Foreground, tw.BLACK)
			opal.set_color(.Scrollbar_Background, tw.SLATE_800)
			opal.set_color(.Scrollbar_Foreground, tw.SLATE_500)

			opal.global_ctx.window_interface.callback_data = app
			opal.global_ctx.window_interface.maximize_callback = proc(data: rawptr) {
				app := (^App)(data)
				if .MAXIMIZED in sdl3.GetWindowFlags(app.window) {
					sdl3.RestoreWindow(app.window)
				} else {
					sdl3.MaximizeWindow(app.window)
				}
			}
			opal.global_ctx.window_interface.iconify_callback = proc(data: rawptr) {
				app := (^App)(data)
				sdl3.MinimizeWindow(app.window)
			}
			opal.global_ctx.window_interface.close_callback = proc(data: rawptr) {
				app := (^App)(data)
				app.run = false
			}
		},
		on_frame = proc(app: ^sdl3app.App) {
			app := (^App)(app)
			using opal
			window_radius :=
				app.radius *
				f32(
					i32(
						transmute(sdl3.WindowFlags)sdl3.GetWindowFlags(app.window) >=
						sdl3.WINDOW_MAXIMIZED,
					),
				)

			begin()
			sdl3app.app_use_node_for_window_grabbing(app, global_ctx.window_interface.grab_node.?)
			begin_node(
				&{
					sizing = {grow = 1, max = INFINITY},
					background = global_ctx.theme.color.background,
					vertical = true,
					padding = global_ctx.theme.min_spacing,
					interactive = true,
					gap = global_ctx.theme.min_spacing,
				},
			)
			{
				begin_node(&{sizing = {fit = 1}, gap = global_ctx.theme.min_spacing})
				{
					for variant in Button_Variant {
						push_id(int(variant))
						add_button(&{label = fmt.tprint(variant), variant = variant})
						pop_id()
					}
				}
				end_node()
				begin_node(&{sizing = {fit = 1}, gap = global_ctx.theme.min_spacing})
				{
					for variant in Button_Variant {
						push_id(int(variant))
						add_button(
							&{
								icon = lucide.POINTER,
								label = fmt.tprint(variant),
								variant = variant,
							},
						)
						pop_id()
					}
				}
				end_node()
			}
			end_node()
			end()
		},
	})

	sdl3app.run(
		&{
			width              = 1000,
			height             = 800,
			min_width          = 500,
			min_height         = 400,
			customize_window   = true,
			// vsync = true,
			min_frame_interval = time.Second / 120,
		},
	)

	free(sdl3app.state)
}

begin_section :: proc(name: string, loc := #caller_location) {
	using opal
	push_id(hash_loc(loc))
	begin_node(
		&{
			background = global_ctx.theme.color.background,
			radius = 10,
			vertical = true,
			sizing = {fit = 1, grow = {1, 0}, max = INFINITY},
		},
	)
	title_node := begin_node(
		&{
			sizing = {fit = {0, 1}, grow = {1, 0}, max = INFINITY},
			justify_between = true,
			interactive = true,
			padding = 10,
		},
	).?
	if title_node.is_hovered && title_node.was_active && !title_node.is_active {
		title_node.is_toggled = !title_node.is_toggled
	}
	node_update_transition(title_node, 0, title_node.is_toggled, 0.2)
	node_update_transition(title_node, 1, title_node.is_hovered, 0.1)
	text_color := mix(title_node.transitions[1], tw.NEUTRAL_500, tw.NEUTRAL_300)
	add_node(
		&{
			text = name,
			foreground = text_color,
			font = &global_ctx.theme.font,
			font_size = 16,
			sizing = {fit = 1},
		},
	)
	add_node(
		&{
			font_size = 14,
			sizing = {fit = 1, exact = {20, 0}, max = INFINITY, grow = {0, 1}},
			data = title_node,
			foreground = text_color,
			on_draw = proc(self: ^Node) {
				kn.add_arrow(
					box_center(self.box),
					5,
					2,
					(2 - (^Node)(self.data).transitions[0]) * math.PI * 0.5,
					paint = self.foreground,
				)
			},
		},
	)
	end_node()
	begin_node(
		&{
			sizing = {
				fit = {1, ease.circular_in_out(title_node.transitions[0])},
				grow = {1, 0},
				max = INFINITY,
			},
			clip_content = true,
			gap = 10,
			padding = 10,
			content_align = {0, 0.5},
		},
	)
}

end_section :: proc(loc := #caller_location) {
	using opal
	end_node()
	end_node()
	pop_id()
}

//
//
//
do_text :: proc(
	desc: ^opal.Node_Descriptor,
	text: string,
	size: f32,
	font: ^opal.Font,
	paint: opal.Paint_Option,
	interactive: bool = true,
	loc := #caller_location,
) {
	using opal
	if font == nil {
		return
	}

	push_id(hash(loc))
	defer pop_id()

	desc.clip_content = true
	desc.vertical = true

	begin_node(desc)
	s := text

	i := 1

	for len(s) > 0 {
		push_id(i)
		i += 1

		line_end := strings.index_byte(s, '\n')
		if line_end == -1 {
			line_end = len(s)
		} else {
			line_end += 1
		}
		line := s[:line_end]

		begin_node(&{wrapped = true, sizing = {fit = 1, max = INFINITY, grow = {1, 0}}})
		pop_id()
		{
			for len(line) > 0 {
				push_id(i)
				i += 1

				word_end := 0
				is_white_space := unicode.is_white_space(rune(line[0]))
				for s, i in line {
					if unicode.is_white_space(s) != is_white_space {
						word_end = i
					}
				}
				if word_end == -1 {
					word_end = len(line)
				} else {
					word_end += 1
				}

				text := line[:word_end]

				add_node(
					&{
						foreground = paint,
						sizing = {fit = 1},
						text = text,
						font = font,
						font_size = size,
						interactive = interactive,
						enable_selection = interactive,
					},
				)
				pop_id()
				line = line[word_end:]
			}
		}
		end_node()

		s = s[line_end:]
	}
	end_node()
}

