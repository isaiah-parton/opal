package file_explorer

import tj "../../../turbojpeg-odin"
import kn "../../katana"
import "../../katana/sdl3glue"
import "../../lucide"
import opal "../../opal"
import "../../sdl3app"
import tw "../../tailwind_colors"
import "base:runtime"
import "core:bytes"
import "core:c/libc"
import c "core:c/libc"
import "core:fmt"
import img "core:image"
import "core:image/bmp"
import "core:image/png"
import "core:image/qoi"
import "core:image/tga"
import "core:math"
import "core:math/bits"
import "core:math/ease"
import "core:math/linalg"
import "core:mem"
import "core:os"
import "core:os/os2"
import "core:path/filepath"
import "core:reflect"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import "core:unicode"
import "core:unicode/utf8"
import "vendor:sdl3"
import stbi "vendor:stb/image"
import stbtt "vendor:stb/truetype"
import "vendor:wgpu"

FILLER_TEXT :: `Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nunc quis malesuada metus, a placerat lacus. Mauris aliquet congue blandit. Praesent elementum efficitur lorem, sed mattis ipsum viverra a. Integer blandit neque eget ultricies commodo. In sapien libero, gravida sit amet egestas quis, pharetra non mi. In nec ligula molestie, placerat dui vitae, ultricies nisl. Curabitur ultrices iaculis urna, in convallis dui dictum id. Nullam suscipit, massa ac venenatis finibus, turpis augue ultrices dolor, at accumsan est sem eu dui. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae; Curabitur sem neque, varius in eros non, vestibulum condimentum ante. In molestie nulla non nulla pulvinar placerat. Nullam sit amet imperdiet turpis.`

Context_Menu :: struct {
	position: [2]f32,
	file:     string,
}

Path_Input :: struct {
	path:             string,
	last_change_time: time.Time,
}

Explorer :: struct {
	using app:         sdl3app.App,
	toggle_switch:     bool,
	right_panel_width: f32,
	slider:            f32,
	text:              string,
	cwd:               string,
	last_cwd:          string,
	path_input:        Maybe(Path_Input),
	items:             [dynamic]Item,
	selected_items:    [dynamic]Item,
	selection_count:   int,
	primary_selection: Maybe(string),
	previews:          File_Previews,
	context_menu:      Maybe(Context_Menu),
	display_mode:      Item_Display_Mode,
	dragging:          bool,
}

memory_size_suffix :: proc(size: i64) -> string {
	switch size {
	case mem.Gigabyte ..= bits.I64_MAX:
		return "GB"
	case mem.Megabyte ..= mem.Gigabyte - 1:
		return "MB"
	case mem.Kilobyte ..= mem.Megabyte - 1:
		return "KB"
	}
	return "B"
}

fmt_memory_size :: proc(size: i64) -> string {
	if size > mem.Gigabyte {
		return fmt.tprintf("%.1f", f32(size) / mem.Gigabyte)
	} else if size > mem.Megabyte {
		return fmt.tprintf("%.1f", f32(size) / mem.Megabyte)
	} else if size > mem.Kilobyte {
		return fmt.tprintf("%.1f", f32(size) / mem.Kilobyte)
	} else {
		return fmt.tprintf("%i", size)
	}
	return "???"
}

explorer_change_folder :: proc(self: ^Explorer, folder: string) {
	if err := os.change_directory(folder); err == nil {
		delete(self.last_cwd)
		self.last_cwd = self.cwd
		self.cwd = os.get_current_directory()
		explorer_refresh(self)
	} else {
		fmt.eprintfln("Failed to change directory: %v", err)
	}
}

explorer_update_selection :: proc(self: ^Explorer) {
	file_previews_clear(&self.previews)
	clear(&self.selected_items)
	explorer_populate_previews(self, self.items[:])
}

explorer_activate_path_input :: proc(self: ^Explorer) {
	if self.path_input != nil {
		return
	}
	self.path_input = Path_Input {
		path = strings.clone(self.cwd),
	}
}

explorer_submit_path_input :: proc(self: ^Explorer) {
	if path_input, ok := self.path_input.?; ok {
		explorer_change_folder(self, path_input.path)
		delete(path_input.path)
		self.path_input = nil
	}
}

explorer_populate_previews :: proc(self: ^Explorer, items: []Item) {
	for &item in items {
		if item.selected {
			append(&self.selected_items, item)
			if !item.is_dir {
				if _, err := file_previews_add(&self.previews, item.fullpath); err != nil {
					fmt.eprintfln("Failed to create preview for %v: %v", item.name, err)
				}
			}
		}
		explorer_populate_previews(self, item.children[:])
	}
}

explorer_display_breadcrumbs :: proc(self: ^Explorer) {
	using opal

	i := 0
	for i < len(self.cwd) {
		s := self.cwd[i:]
		n := strings.index_any(s, "/\\")
		if n == -1 {
			n = len(s)
		}
		s = s[:n]

		push_id(i)
		defer pop_id()

		// The crumb node
		node := add_node(
			&{
				text = s,
				foreground = global_ctx.theme.color.base_foreground,
				font_size = 16,
				font = &global_ctx.theme.font,
				interactive = true,
				padding = {4, 2, 4, 2},
				radius = 8,
				sizing = {fit = 1},
			},
		).?

		// Fade animation
		node_update_transition(node, 0, node.is_hovered, 0.1)
		node.background = fade(tw.NEUTRAL_700, 0.4 * node.transitions[0])

		// Handle clicks on each crumb
		if node.is_active && !node.was_active {
			crumb_path := self.cwd[:max(i + n, 3)]
			explorer_change_folder(self, crumb_path)
		}

		i += n + 1

		// Draw arrow if there's another crumb after
		if i < len(self.cwd) {
			add_node(
				&{
					text = string_from_rune(lucide.CHEVRON_RIGHT),
					font_size = 16,
					sizing = {fit = 1, grow = {0, 1}, max = {0, INFINITY}},
					padding = {0, 3, 0, 0},
					content_align = {0, 0.5},
					font = &global_ctx.theme.icon_font,
					foreground = global_ctx.theme.color.base_foreground,
				},
			)
		}
	}
}

explorer_refresh :: proc(self: ^Explorer) -> os.Error {
	folder := os.open(self.cwd) or_return
	defer os.close(folder)

	files := os.read_dir(folder, -1) or_return
	defer delete(files)

	clear(&self.items)
	for file_info in files {
		append(&self.items, Item{file_info = file_info})
	}

	slice.sort_by(self.items[:], proc(a, b: Item) -> bool {
		if a.is_dir != b.is_dir {
			return a.is_dir
		}
		return strings.compare(a.file_info.name, b.file_info.name) < 0
	})

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

	if !sdl3.Init({.VIDEO, .EVENTS}) {
		panic("Could not initialize SDL3")
	}

	sdl3app.state = new_clone(
	Explorer {
		run = true,
		on_start = proc(app: ^sdl3app.App) {
			app := (^Explorer)(app)
			opal.set_color(.Selection_Background, tw.SKY_500)
			opal.set_color(.Selection_Foreground, tw.BLACK)
			opal.set_color(.Scrollbar_Background, tw.SLATE_800)
			opal.set_color(.Scrollbar_Foreground, tw.SLATE_500)
			opal.global_ctx.snap_to_pixels = true
			app.cwd = os.get_current_directory()
			if err := explorer_refresh(app); err != nil {
				fmt.eprintf("Failed to refresh explorer: %v\n", err)
			}

			opal.global_ctx.window_interface.callback_data = app
			opal.global_ctx.window_interface.maximize_callback = proc(data: rawptr) {
				app := (^Explorer)(data)
				if .MAXIMIZED in sdl3.GetWindowFlags(app.window) {
					sdl3.RestoreWindow(app.window)
				} else {
					sdl3.MaximizeWindow(app.window)
				}
			}
			opal.global_ctx.window_interface.iconify_callback = proc(data: rawptr) {
				app := (^Explorer)(data)
				sdl3.MinimizeWindow(app.window)
			}
			opal.global_ctx.window_interface.close_callback = proc(data: rawptr) {
				app := (^Explorer)(data)
				app.run = false
			}
		},
		on_frame = proc(app: ^sdl3app.App) {
			app := (^Explorer)(app)
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
					padding = 1,
					radius = window_radius,
					clip_content = window_radius > 0,
					interactive = true,
				},
			)
			{
				if app.dragging {
					if mouse_released(.Left) {
						app.dragging = false
					}
					begin_node(
						&{
							style = {
								background = global_ctx.theme.color.background,
								stroke_width = 2,
								stroke = global_ctx.theme.color.border,
							},
							layer = 9,
							radius = global_ctx.theme.radius_small,
							shadow_color = kn.fade(tw.BLACK, 0.5),
							shadow_offset = {0, 2},
							shadow_size = 8,
							exact_offset = global_ctx.mouse_position,
							is_root = true,
							sizing = {fit = 1, exact = {300, 0}},
							vertical = true,
						},
					)
					{
						for &item, i in app.selected_items {
							push_id(int(i))
							item.selected = false
							node := item_display_for_list(&item, app)
							node.interactive = false
							pop_id()
						}
						add_node(
							&{
								layer = 10,
								absolute = true,
								align = {0, 1},
								sizing = {fit = 1},
								text = fmt.tprintf("%i items", len(app.selected_items)),
								font = &global_ctx.theme.font,
								font_size = 14,
								foreground = global_ctx.theme.color.base_foreground,
							},
						)
					}
					end_node()
				}

				// Show the context menu (if you wanna show the context menu)
				if menu, ok := app.context_menu.?; ok {
					push_id(menu.file)
					defer pop_id()

					// Container node
					menu_root := begin_node(
						&Node_Descriptor {
							layer = 9,
							is_root = true,
							exact_offset = menu.position,
							sizing = {exact = {0, 0}, fit = 1, max = INFINITY},
							radius = 10,
							background = global_ctx.theme.color.background,
							stroke = global_ctx.theme.color.border,
							shadow_color = kn.fade(tw.BLACK, 0.5),
							shadow_offset = {0, 2},
							shadow_size = 8,
							stroke_width = 2,
							interactive = true,
							vertical = true,
						},
					).?

					// Handle clicking out
					if mouse_pressed(.Left) &&
					   !menu_root.is_focused &&
					   !menu_root.has_focused_child {
						app.context_menu = nil
					}

					node_update_transition(menu_root, 0, true, 0.2)
					menu_root.scale.y = 0.5 + ease.cubic_out(menu_root.transitions[0]) * 0.5

					{
						add_node(
							&{
								text = menu.file if len(app.selected_items) == 1 else fmt.tprintf("%i files", len(app.selected_items)),
								foreground = global_ctx.theme.color.base_foreground,
								font = &global_ctx.theme.font,
								font_size = 16,
								sizing = {fit = 1},
								padding = {8, 4, 24, 4},
							},
						)
						add_node(
							&{
								sizing = {exact = {0, 2}, max = {INFINITY, 2}, grow = {1, 0}},
								background = global_ctx.theme.color.border,
							},
						)
						begin_node(
							&{
								sizing = {fit = 1, max = INFINITY, grow = {1, 0}},
								gap = 4,
								padding = 4,
								vertical = true,
							},
						)
						{
							// Show context options
							do_menu_item("New Folder", lucide.FOLDER_PLUS)
							do_menu_item("New File", lucide.FILE_PLUS)
							do_menu_item("Copy", lucide.COPY)
							do_menu_item("Cut", lucide.SCISSORS)
							do_menu_item("Paste", lucide.CLIPBOARD_PASTE)
							do_menu_item("Rename", lucide.TEXT_CURSOR_INPUT)
							do_menu_item("Shred", lucide.SHREDDER)
						}
						end_node()
					}
					end_node()
				}

				begin_node(
					&{sizing = {max = INFINITY, grow = 1, fit = 1}, content_align = {0, 0.5}},
				)
				{
					begin_node(
						&{
							sizing = {
								max = {INFINITY, INFINITY},
								grow = 1,
								exact = {200, 0},
								fit = {1, 0},
							},
							vertical = true,
						},
					)
					{
						// Main stuff
						begin_node(&{sizing = {max = INFINITY, grow = 1}})
						{
							// Body
							begin_node(
								&{
									sizing = {fit = {1, 0}, max = INFINITY, grow = 1},
									vertical = true,
									background = global_ctx.theme.color.background,
								},
							)
							{
								// Toolbar
								begin_node(
									&{
										sizing = {fit = {0, 1}, grow = {1, 0}, max = INFINITY},
										content_align = {0, 0.5},
										gap = 4,
										padding = 8,
									},
								)
								{
									node := begin_node(
										&{
											sizing = {grow = 1, max = INFINITY},
											clip_content = true,
											content_align = {0, 0.5},
											interactive = true,
										},
									).?
									{
										if path_input, ok := &app.path_input.?; ok {
											// Show the path input
											field_result := add_field(
												&{
													sizing = {grow = 1, max = INFINITY},
													value_data = &path_input.path,
													value_type_info = type_info_of(
														type_of(path_input.path),
													),
												},
											)

											// Keep it focused
											focus_node(field_result.node.?.id)

											// Handle clicking out
											if !field_result.node.?.is_focused &&
											   field_result.node.?.was_focused {
												explorer_submit_path_input(app)
											}

											// Handle enter pressage
											if field_result.was_confirmed {
												explorer_submit_path_input(app)
											}
										} else {
											// Activate the input if you click around the breadcrumbs
											if node.is_focused && !node.was_focused {
												explorer_activate_path_input(app)
											}

											// Show breadcrumbs
											explorer_display_breadcrumbs(app)
										}
									}
									end_node()
									// Some little selector buttons for changing modes
									begin_node(
										&{
											sizing = {fit = 1},
											radius = 8,
											padding = 2,
											// background = global_ctx.theme.color.base_strong,
											stroke = global_ctx.theme.color.border,
											stroke_width = 2,
										},
									)
									{
										mode_icons := [Item_Display_Mode]rune {
											.Grid = lucide.GRID_2X2,
											.List = lucide.ROWS_3,
										}
										for mode, i in Item_Display_Mode {
											radius: [4]f32 = 6
											if i == 0 {
												radius[1] = 0
												radius[3] = 0
											} else if i == len(Item_Display_Mode) - 1 {
												radius[0] = 0
												radius[2] = 0
											}

											push_id(i)
											node := add_node(
												&{
													text = string_from_rune(mode_icons[mode]),
													sizing = {fit = 1, aspect_ratio = 1},
													padding = 6,
													font_size = 16,
													interactive = true,
													content_align = 0.5,
													radius = radius,
													font = &global_ctx.theme.icon_font,
													foreground = global_ctx.theme.color.base_foreground,
												},
											).?
											pop_id()

											node_update_transition(node, 0, node.is_hovered, 0.1)
											node.background =
												tw.GREEN_500 if app.display_mode == mode else fade(tw.NEUTRAL_400, 0.4 * node.transitions[0])
											if node.is_active && !node.was_active {
												app.display_mode = mode
											}
										}
									}
									end_node()
								}
								end_node()
								// File list
								begin_node(
									&{
										wrapped = app.display_mode == .Grid,
										vertical = true,
										sizing = {grow = 1, max = INFINITY},
										show_scrollbars = true,
										clip_content = true,
										interactive = true,
										padding = 8,
									},
								)
								{
									app.selection_count = 0
									if app.display_mode == .List {
										for &item, i in app.items {
											push_id(i)
											item_display_for_list(&item, app)
											pop_id()
										}
									} else {
										for &item, i in app.items {
											push_id(i)
											item_display_for_grid(&item, app)
											pop_id()
										}
									}
								}
								end_node()
							}
							end_node()

							// Right panel
							if len(app.previews.items) > 0 {
								add_resizer(
									&{orientation = .Vertical, value = &app.right_panel_width},
								)
								app.right_panel_width = max(app.right_panel_width, 240)
								begin_node(
									&{
										sizing = {
											grow = {0, 1},
											fit = {0, 1},
											exact = {app.right_panel_width, 0},
											max = {app.right_panel_width, INFINITY},
										},
										content_align = {0.5, 0.5},
										vertical = true,
										padding = 12,
										gap = 12,
										background = global_ctx.theme.color.background,
										show_scrollbars = true,
										clip_content = true,
										interactive = true,
									},
								)
								{
									file_previews_display(&app.previews)
								}
								end_node()
							}
						}
						end_node()
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

