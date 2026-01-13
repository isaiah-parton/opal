package example

import kn "../../katana"
import "../../katana/sdl3glue"
import "../../lucide"
import opal "../../opal"
import "../../sdl3app"
import tw "../../tailwind_colors"
import "base:runtime"
import "core:c/libc"
import "core:fmt"
import "core:image"
import "core:image/bmp"
import "core:image/jpeg"
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
import "core:time"
import "core:unicode"
import "core:unicode/utf8"
import "vendor:sdl3"
import stbi "vendor:stb/image"
import stbtt "vendor:stb/truetype"
import "vendor:wgpu"


FILLER_TEXT :: `Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nunc quis malesuada metus, a placerat lacus. Mauris aliquet congue blandit. Praesent elementum efficitur lorem, sed mattis ipsum viverra a. Integer blandit neque eget ultricies commodo. In sapien libero, gravida sit amet egestas quis, pharetra non mi. In nec ligula molestie, placerat dui vitae, ultricies nisl. Curabitur ultrices iaculis urna, in convallis dui dictum id. Nullam suscipit, massa ac venenatis finibus, turpis augue ultrices dolor, at accumsan est sem eu dui. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae; Curabitur sem neque, varius in eros non, vestibulum condimentum ante. In molestie nulla non nulla pulvinar placerat. Nullam sit amet imperdiet turpis.`

Item_Display_Mode :: enum {
	List,
	Grid,
}

Item :: struct {
	using file_info: os.File_Info,
	children:        [dynamic]Item,
	selected:        bool,
	expanded:        bool,
}

item_deselect_children :: proc(self: ^Item, exception: ^Item = nil) {
	for &child in self.children {
		if exception != nil && child.fullpath == exception.fullpath {
			continue
		}
		child.selected = false
		item_deselect_children(&child, exception)
	}
}

item_destroy :: proc(self: ^Item) {
	os.file_info_delete(self.file_info)
	delete(self.children)
	self^ = {}
}

item_clear_children :: proc(self: ^Item) {
	for &child in self.children {
		item_clear_children(&child)
		item_destroy(&child)
	}
	clear(&self.children)
}

item_load_children :: proc(self: ^Item) -> os.Error {
	folder := os.open(self.fullpath) or_return
	defer os.close(folder)

	files := os.read_dir(folder, -1) or_return
	defer delete(files)

	item_clear_children(self)

	for file_info in files {
		append(&self.children, Item{file_info = file_info})
	}

	slice.sort_by(self.children[:], proc(a, b: Item) -> bool {
		if a.is_dir != b.is_dir {
			return a.is_dir
		}
		return strings.compare(a.file_info.name, b.file_info.name) < 0
	})

	return nil
}

item_display_for_grid :: proc(
	self: ^Item,
	app: ^Explorer,
	loc := #caller_location,
) -> (
	node: ^opal.Node,
) {
	using opal

	push_id(hash_loc(loc))
	defer pop_id()

	if self.selected {
		app.selection_count += 1
	}

	node =
	begin_node(
		&{
			interactive = true,
			radius = 8,
			padding = 6,
			sizing = {
				exact = {200, 0},
				fit = {1, 1},
				relative = {0.25, 0},
				grow = {1, 0},
				max = INFINITY,
			},
			content_align = {0, 0.5},
			gap = 4,
			foreground = tw.BLUE_500 if self.file_info.is_dir else kn.WHITE,
			stroke = tw.BLUE_500,
			stroke_width = f32(i32(self.name == app.primary_selection)),
			clip_content = true,
		},
	).?
	{
		icon: rune = lucide.FILE
		if self.is_dir {
			icon = lucide.FOLDER
		} else if self.file_info.mode == 1049014 {
			icon = lucide.FOLDER_SYMLINK
		}
		add_node(
			&{
				sizing = {fit = 1, aspect_ratio = 1},
				text = string_from_rune(icon),
				font = &global_ctx.theme.icon_font,
				font_size = 32,
				foreground = node.foreground,
			},
		)
		begin_node(
			&{
				sizing = {grow = 1, max = INFINITY, fit = {1, 0}},
				vertical = true,
				content_align = {0, 0.5},
			},
		)
		{
			add_node(
				&{
					text = self.file_info.name,
					font = &global_ctx.theme.font,
					font_size = 16,
					sizing = {fit = 1},
					foreground = node.foreground,
				},
			)
			if !self.is_dir {
				begin_node(&{sizing = {grow = {1, 0}, max = INFINITY, fit = 1}})
				{
					add_node(
						&{
							text = fmt_memory_size(self.file_info.size),
							font = &global_ctx.theme.font,
							font_size = 16,
							sizing = {fit = 1},
							foreground = node.foreground,
						},
					)
					add_node(
						&{
							text = memory_size_suffix(self.file_info.size),
							font = &global_ctx.theme.font,
							font_size = 16,
							sizing = {fit = 1},
							foreground = fade(node.foreground.(kn.Color), 0.5),
						},
					)
				}
				end_node()
			}
		}
		end_node()
	}
	end_node()

	if node.is_hovered && !node.was_hovered {
		node.transitions[0] = 1
	}

	node_update_transition(node, 0, node.is_hovered, 0.1)
	node_update_transition(node, 1, node.is_active, 0.1)

	node.background = kn.fade(
		kn.mix(f32(i32(self.selected)) * 0.5, tw.NEUTRAL_700, tw.BLUE_700),
		max(f32(i32(self.selected)) * 0.5, node.transitions[0]),
	)

	item_handle_node_input(self, app, node)

	return
}

item_display_for_list :: proc(
	self: ^Item,
	app: ^Explorer,
	depth := 0,
	loc := #caller_location,
) -> (
	node: ^opal.Node,
) {
	using opal

	push_id(hash_loc(loc))
	defer pop_id()

	if self.selected {
		app.selection_count += 1
	}

	node =
	begin_node(
		&{
			interactive = true,
			sticky = true,
			radius = 8,
			padding = {8 + f32(depth) * 20, 4, 8, 4},
			sizing = {fit = 1, grow = {1, 0}, max = INFINITY},
			content_align = {0, 0.5},
			gap = 4,
			foreground = tw.BLUE_500 if self.file_info.is_dir else kn.WHITE,
			stroke = tw.BLUE_500,
			stroke_width = f32(i32(self.name == app.primary_selection)),
		},
	).?
	{
		icon: rune = lucide.FILE
		if self.is_dir {
			icon = lucide.FOLDER_OPEN if self.expanded else lucide.FOLDER
		} else if self.file_info.mode == 1049014 {
			icon = lucide.FOLDER_SYMLINK
		}
		add_node(
			&{
				sizing = {fit = 1, aspect_ratio = 1},
				text = string_from_rune(icon),
				font = &global_ctx.theme.icon_font,
				font_size = 16,
				foreground = node.foreground,
			},
		)
		add_node(
			&{
				text = self.file_info.name,
				font = &global_ctx.theme.font,
				font_size = 16,
				sizing = {fit = 1},
				foreground = node.foreground,
			},
		)
		add_node(&{sizing = {grow = {1, 0}, max = INFINITY}})
		if !self.is_dir {
			add_node(
				&{
					text = fmt_memory_size(self.file_info.size),
					font = &global_ctx.theme.font,
					font_size = 16,
					sizing = {fit = 1},
					foreground = node.foreground,
				},
			)
			add_node(
				&{
					text = memory_size_suffix(self.file_info.size),
					font = &global_ctx.theme.font,
					font_size = 16,
					sizing = {fit = 1},
					foreground = fade(node.foreground.(kn.Color), 0.5),
				},
			)
		}
	}
	end_node()

	if node.transitions[2] > 0 {
		begin_node(
			&{
				sizing = {grow = {1, 0}, max = INFINITY, fit = {1, node.transitions[2]}},
				clip_content = true,
				vertical = true,
				padding = {0, 0, 0, 0},
			},
		)
		for &child, i in self.children {
			push_id(i + 1)
			item_display_for_list(&child, app, depth + 1)
			pop_id()
		}
		end_node()
	}

	if node.is_hovered && !node.was_hovered {
		node.transitions[0] = 1
	}

	node_update_transition(node, 0, node.is_hovered, 0.1)
	node_update_transition(node, 1, node.is_active, 0.1)
	node_update_transition(node, 2, self.expanded, 0.2)

	node.background = kn.fade(
		kn.mix(f32(i32(self.selected)) * 0.5, tw.NEUTRAL_700, tw.BLUE_700),
		max(f32(i32(self.selected)) * 0.5, node.transitions[0]),
	)

	item_handle_node_input(self, app, node)

	return
}

item_handle_node_input :: proc(self: ^Item, app: ^Explorer, node: ^opal.Node) {
	using opal

	multi_select := key_down(.Left_Control) || key_down(.Right_Control)

	update_selection: bool
	defer if update_selection do explorer_update_selection(app)

	if node.is_active &&
	   linalg.distance(global_ctx.mouse_position, global_ctx.mouse_click_position) > 10 &&
	   global_ctx.last_mouse_down_button == .Left {
		if !multi_select && len(app.selected_items) == 1 {
			for &item, j in app.items {
				item_deselect_children(&item)
				item.selected = false
			}
			self.selected = true
			update_selection = true
		}
		app.dragging = true
	}

	if node.is_active && !node.was_active {
		if global_ctx.last_mouse_down_button == .Right {
			app.context_menu = Context_Menu {
				position = global_ctx.mouse_position,
				file     = self.file_info.name,
			}
		}
		if multi_select {
			self.selected = !self.selected
		} else {
			self.selected = true
		}
		update_selection = true
	}

	if node.was_active && !node.is_active {
		if node.click_count == 2 {
			if self.file_info.is_dir {
				explorer_change_folder(app, self.file_info.name)
			} else if self.file_info.mode == 1049014 {
				h, _ := os.open(self.file_info.name)
				fi, _ := os.read_dir(h, 1)
				if len(fi) > 0 {
					explorer_change_folder(app, filepath.dir(fi[0].fullpath))
				}
			} else {
				libc.system(fmt.ctprintf(`start "" "%s"`, self.fullpath))
			}
		} else {
			if !multi_select && !app.dragging {
				for &item, j in app.items {
					if item.fullpath == self.fullpath {
						continue
					}
					item_deselect_children(&item, self)
					item.selected = false
				}
			}
			if self.file_info.is_dir {
				self.expanded = !self.expanded
				if self.expanded {
					item_load_children(self)
				}
			}
		}
		update_selection = true
	}
}

Preview :: union {
	Text_Preview,
	Image_Preview,
}

preview_uninit :: proc(self: ^Preview) {
	switch variant in self {
	case Text_Preview:
		delete(variant.data)
	case Image_Preview:
	}
	self^ = {}
}

Text_Preview :: struct {
	data: []u8,
	text: string,
}

Image_Preview :: struct {
	source: kn.Box,
}

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
	previews:          [dynamic]Preview,
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
	for &preview in self.previews {
		preview_uninit(&preview)
	}
	clear(&self.previews)
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
				if preview, err := explorer_make_preview(self, item.fullpath); err == nil {
					append(&self.previews, preview)
				} else {
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

explorer_make_preview :: proc(self: ^Explorer, name: string) -> (result: Preview, err: os.Error) {
	self.primary_selection = name

	if os.is_dir(name) {
		err = os.General_Error.Invalid_File
		return
	}

	file := os.open(name, os.O_RDONLY) or_return
	defer os.close(file)

	switch filepath.ext(name) {
	case ".png", ".jpg", ".jpeg", ".qoi", ".tga", ".bmp":
		if img, err := image.load_from_file(name, {.alpha_add_if_missing}); err == nil {
			defer image.destroy(img)

			MAX_DIMENSION :: 512

			shrink_x := max(img.width - MAX_DIMENSION, 0)
			shrink_y := max(img.height - MAX_DIMENSION, 0)

			new_width := img.width
			new_height := img.height
			if shrink_x > shrink_y {
				new_width = img.width - shrink_x
				new_height = int(f32(img.height) * (f32(new_width) / f32(img.width)))
			} else {
				new_height = img.height - shrink_y
				new_width = int(f32(img.width) * (f32(new_height) / f32(img.height)))
			}

			new_data := make([]u8, new_width * new_height * 4)
			defer delete(new_data)

			stbi.resize_uint8(
				raw_data(img.pixels.buf),
				i32(img.width),
				i32(img.height),
				0,
				raw_data(new_data),
				i32(new_width),
				i32(new_height),
				0,
				4,
			)

			result = Image_Preview {
				source = kn.copy_image_to_atlas(raw_data(new_data), new_width, new_height),
			}
		} else {
			fmt.eprintln(err)
		}
	case ".ttf", ".otf":
		if data, ok := os.read_entire_file(name); ok {
			font: stbtt.fontinfo
			if !stbtt.InitFont(&font, raw_data(data), 0) {
				fmt.eprintln("Failed to initialize font")
			}

			x, y, w, h: i32
			codepoint: rune
			for i := 0;; i += 1 {
				index := stbtt.FindGlyphIndex(&font, rune(i))
				if index != 0 && !stbtt.IsGlyphEmpty(&font, index) {
					codepoint = rune(i)
					break
				}
			}
			scale := stbtt.ScaleForPixelHeight(&font, 32)
			glyph_pixels := stbtt.GetGlyphBitmap(
				&font,
				scale,
				scale,
				i32(codepoint),
				&w,
				&h,
				&x,
				&y,
			)[:w *
			h]
			// defer stbtt.FreeBitmap(glyph_pixels, nil)
			if glyph_pixels == nil {
				fmt.eprintln("Failed to get codepoint bitmap")
			} else {
				image_pixels := make([]u8, w * h * 4)
				defer delete(image_pixels)
				for i in 0 ..< len(glyph_pixels) {
					j := i * 4
					image_pixels[j] = 255
					image_pixels[j + 1] = 255
					image_pixels[j + 2] = 255
					image_pixels[j + 3] = glyph_pixels[i]
				}
				result = Image_Preview {
					source = kn.copy_image_to_atlas(raw_data(image_pixels), int(w), int(h)),
				}
			}
		} else {
			fmt.eprintln("Failed to read font file")
		}
	case:
		text_preview := Text_Preview {
			data = make([]u8, 1024),
		}
		defer if err != nil do delete(text_preview.data)

		n := os.read(file, text_preview.data) or_return

		text_preview.text = string(text_preview.data[:n])

		if utf8.valid_string(text_preview.text) {
			result = text_preview
		} else {
			err = os.General_Error.Unsupported
		}
	}

	return
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
			}
			opal.global_ctx.window_interface.iconify_callback = proc(data: rawptr) {
				app := (^Explorer)(data)
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
							style = {background = tw.NEUTRAL_900},
							layer = 3,
							radius = 4,
							shadow_color = tw.BLACK,
							shadow_size = 10,
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
								layer = 4,
								absolute = true,
								align = {0, 1},
								sizing = {fit = 1},
								text = fmt.tprintf("%i items", len(app.selected_items)),
								font = &global_ctx.theme.font,
								font_size = 14,
								foreground = tw.WHITE,
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
							absolute = true,
							exact_offset = menu.position,
							sizing = {exact = {0, 0}, fit = 1, max = INFINITY},
							radius = 10,
							background = tw.NEUTRAL_800,
							stroke = tw.NEUTRAL_600,
							shadow_color = tw.BLACK,
							shadow_offset = 2,
							shadow_size = 10,
							stroke_width = 1,
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
								foreground = tw.WHITE,
								font = &global_ctx.theme.font,
								font_size = 16,
								sizing = {fit = 1},
								padding = {8, 4, 24, 4},
							},
						)
						add_node(
							&{
								sizing = {exact = {0, 1}, max = {INFINITY, 1}, grow = {1, 0}},
								background = tw.NEUTRAL_600,
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
					&{
						sizing = {max = INFINITY, grow = 1, fit = 1},
						content_align = {0, 0.5},
						style = {background = tw.NEUTRAL_900},
					},
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
							gap = 2,
							padding = 4,
							vertical = true,
						},
					)
					{
						// Main stuff
						begin_node(&{sizing = {max = INFINITY, grow = 1}, padding = 4, gap = 4})
						{
							// Body
							begin_node(
								&{
									sizing = {fit = {1, 0}, max = INFINITY, grow = 1},
									padding = 8,
									gap = 8,
									vertical = true,
									background = tw.NEUTRAL_800,
									radius = 10,
								},
							)
							{
								// Toolbar
								begin_node(
									&{
										sizing = {fit = {0, 1}, grow = {1, 0}, max = INFINITY},
										content_align = {0, 0.5},
										gap = 4,
									},
								)
								{
									node := begin_node(
										&{
											sizing = {grow = 1, max = INFINITY},
											clip_content = true,
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
											padding = 2,
											radius = 8,
											gap = 2,
											background = tw.NEUTRAL_900,
										},
									)
									{
										for mode, i in Item_Display_Mode {
											push_id(i)
											node := add_node(
												&{
													text = string_from_rune(
														lucide.GRID_2X2 if mode == .Grid else lucide.ROWS_3,
													),
													sizing = {fit = 1, aspect_ratio = 1},
													padding = 4,
													font_size = 16,
													stroke_width = 2,
													interactive = true,
													content_align = 0.5,
													radius = 6,
													font = &global_ctx.theme.icon_font,
													foreground = global_ctx.theme.color.base_foreground,
												},
											).?
											pop_id()

											node_update_transition(node, 0, node.is_hovered, 0.1)
											node.background =
												tw.NEUTRAL_700 if app.display_mode == mode else fade(tw.NEUTRAL_700, 0.4 * node.transitions[0])
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
							if len(app.previews) > 0 {
								{
									begin_node(
										&{
											sizing = {
												grow = {0, 1},
												max = INFINITY,
												exact = {1, 0},
											},
											layer = 1,
											group = true,
										},
									)
									{
										node := add_node(
											&{
												absolute = true,
												sizing = {relative = {0, 1}, exact = {7, 0}},
												exact_offset = {-3, 0},
												interactive = true,
												radius = 2,
												sticky = true,
												cursor = Cursor.Resize_EW,
												data = app,
												on_draw = proc(self: ^Node) {
													app := (^Explorer)(self.data)
													if self.is_active {
														app.right_panel_width =
															self.parent.parent.box.hi.x -
															self.parent.parent.padding.z -
															self.parent.parent.gap -
															box_width(self.box) / 2 -
															opal.global_ctx.mouse_position.x
													}
													center := box_center(self.box)
													color := kn.mix(
														self.transitions[0] * 0.5,
														global_ctx.theme.color.border,
														global_ctx.theme.color.accent,
													)
													kn.add_circle(center + {0, -7}, 2.5, color)
													kn.add_circle(center, 2.5, color)
													kn.add_circle(center + {0, 7}, 2.5, color)
												},
											},
										).?
										node_update_transition(
											node,
											0,
											node.is_hovered || node.is_active,
											0.1,
										)
										node_update_transition(node, 1, node.is_active, 0.2)
									}
									end_node()
								}
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
										padding = 8,
										gap = 8,
										background = tw.NEUTRAL_800,
										show_scrollbars = true,
										clip_content = true,
										interactive = true,
										radius = 10,
									},
								)
								{
									for &preview, i in app.previews {
										push_id(int(i + 1))
										defer pop_id()
										switch &variant in preview {
										case (Text_Preview):
											do_text(
												&{sizing = {grow = 1, max = INFINITY, fit = 1}},
												variant.text,
												14,
												&global_ctx.theme.monospace_font,
												tw.WHITE,
											)
										// global_ctx.add_field(
										// 	&{
										// 		sizing = {grow = 1, max = INFINITY},
										// 		multiline = true,
										// 		value_data = &variant.text,
										// 		value_type_info = type_info_of(
										// 			type_of(variant.text),
										// 		),
										// 	},
										// )
										case (Image_Preview):
											add_node(
												&{
													sizing = {
														grow = 1,
														max = variant.source.hi -
														variant.source.lo,
														aspect_ratio = box_width(variant.source) /
														box_height(variant.source),
													},
													data = &preview,
													on_draw = proc(node: ^Node) {
														app := (^Explorer)(node.data)
														kn.add_box(
															node.box,
															4,
															kn.make_atlas_sample(
																(^Image_Preview)(node.data)^.source,
																node.box,
																kn.WHITE,
															),
														)
													},
												},
											)
										}
									}
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
			background = tw.NEUTRAL_800,
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

				word_end := strings.index_any(line, " .")
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

