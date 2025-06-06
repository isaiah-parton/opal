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
import "core:os"
import "core:strings"
import "core:time"
import "vendor:sdl3"
import "vendor:wgpu"

import "../components"

FILLER_TEXT :: `Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nunc quis malesuada metus, a placerat lacus. Mauris aliquet congue blandit. Praesent elementum efficitur lorem, sed mattis ipsum viverra a. Integer blandit neque eget ultricies commodo. In sapien libero, gravida sit amet egestas quis, pharetra non mi. In nec ligula molestie, placerat dui vitae, ultricies nisl. Curabitur ultrices iaculis urna, in convallis dui dictum id. Nullam suscipit, massa ac venenatis finibus, turpis augue ultrices dolor, at accumsan est sem eu dui. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae; Curabitur sem neque, varius in eros non, vestibulum condimentum ante. In molestie nulla non nulla pulvinar placerat. Nullam sit amet imperdiet turpis.`

Item :: struct {
	using file_info: os.File_Info,
	children:        [dynamic]Item,
}

Explorer :: struct {
	using app:     sdl3app.App,
	toggle_switch: bool,
	slider:        f32,
	text:          string,
	cwd:           string,
	items:         [dynamic]Item,
}

explorer_refresh :: proc(self: ^Explorer) -> os.Error {
	folder := os.open(self.cwd) or_return
	files := os.read_dir(folder, -1) or_return
	for file_info in files {
		append(&self.items, Item{file_info = file_info})
	}
	return nil
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
	Explorer {
		run = true,
		on_start = proc(app: ^sdl3app.App) {
			app := (^Explorer)(app)
			lucide.load()
			components.theme.icon_font = lucide.font
			opal.set_color(.Selection_Background, tw.SKY_500)
			opal.set_color(.Selection_Foreground, tw.BLACK)
			opal.set_color(.Scrollbar_Background, tw.SLATE_800)
			opal.set_color(.Scrollbar_Foreground, tw.SLATE_500)
			opal.global_ctx.snap_to_pixels = true
			components.theme.font, _ = kn.load_font_from_files(
				"Lexend-Regular.png",
				"Lexend-Regular.json",
			)
		},
		on_frame = proc(app: ^sdl3app.App) {
			app := (^Explorer)(app)
			using opal, components
			window_radius :=
				app.radius * f32(i32(.MAXIMIZED not_in sdl3.GetWindowFlags(app.window)))
			begin()
			begin_node(
				&{
					min_size = global_ctx.screen_size,
					background = theme.color.background,
					stroke = tw.NEUTRAL_600,
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
					if do_window_button(lucide.CHEVRON_DOWN, tw.NEUTRAL_500) {
						sdl3.MinimizeWindow(app.window)
					}
					if do_window_button(lucide.CHEVRON_UP, tw.NEUTRAL_500) {
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

				TEXT_COLOR :: tw.NEUTRAL_400
				TEXT_STROKE_COLOR :: tw.ROSE_600

				node := begin_node(
					&{
						max_size = INFINITY,
						grow = true,
						gap = 5,
						padding = 20,
						interactive = true,
						clip_content = true,
						show_scrollbars = true,
						vertical = true,
						content_align = 0.5,
					},
				).?
				{
					begin_node(&{fit = 1, vertical = true, gap = 10})
					{
						begin_section("Settings")
						components.add_field(
							&{
								value_data = &theme.base_size.x,
								value_type_info = type_info_of(f32),
								min_size = {200, 20},
								multiline = true,
								fit = {0, 1},
							},
						)
						components.add_field(
							&{
								value_data = &theme.base_size.y,
								value_type_info = type_info_of(f32),
								min_size = {200, 20},
								multiline = true,
								fit = {0, 1},
							},
						)
						end_section()
						//
						begin_section("Buttons")
						for variant, i in Button_Variant {
							push_id(i)
							desc := make_button(fmt.tprint(variant), variant)
							add_button(&desc)
							pop_id()
						}
						end_section()
						//
						begin_section("Boolean")
						components.add_toggle_switch(&app.toggle_switch)
						end_section()
						//
						begin_section("Slider")
						if new_value, ok := components.add_slider(&Slider_Descriptor(f32){min = 0, max = 1, value = app.slider, min_size = {300, 0}}).new_value.?;
						   ok {
							app.slider = new_value
						}
						end_section()
						//
						begin_section("Progress")
						components.add_radial_progress(&{size = 70, time = app.slider})
						components.add_progress_bar(&{time = app.slider})
						end_section()
						//
						begin_section("Input fields")
						components.add_field(
							&{
								value_data = &app.text,
								value_type_info = type_info_of(string),
								min_size = {200, 20},
								multiline = true,
								fit = {0, 1},
							},
						)
						end_section()
					}
					end_node()
				}
				end_node()
			}
			end_node()
			end()
		},
	},
	)

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
			background = tw.NEUTRAL_800,
			radius = 10,
			vertical = true,
			fit = 1,
			grow = {true, false},
			max_size = INFINITY,
		},
	)
	title_node := begin_node(
		&{
			fit = {0, 1},
			grow = {true, false},
			max_size = INFINITY,
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
			font = &components.theme.font,
			font_size = 16,
			fit = 1,
		},
	)
	add_node(
		&{
			grow = {false, true},
			min_size = {20, 0},
			max_size = INFINITY,
			font_size = 14,
			fit = 1,
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
			fit = {1, ease.circular_in_out(title_node.transitions[0])},
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
	loc := #caller_location,
) {
	using opal
	if font == nil {
		return
	}
	push_id(hash(loc))
	defer pop_id()
	desc.clip_content = true
	desc.wrapped = true
	begin_node(desc)
	s := text
	i := 0
	for len(s) > 0 {
		until := strings.index_byte(s, ' ')
		if until == -1 {
			until = len(s)
		} else {
			until += 1
		}
		push_id(int(i))
		add_node(
			&{
				foreground       = paint,
				fit              = 1,
				text             = s[:until],
				font             = font,
				font_size        = size,
				interactive      = true,
				enable_selection = true,
				// static_text = true,
			},
			loc = loc,
		)
		pop_id()
		s = s[until:]
		i += 1
	}
	end_node()
}

