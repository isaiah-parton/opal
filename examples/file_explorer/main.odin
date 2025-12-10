package example

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
import "core:mem"
import "core:os"
import "core:os/os2"
import "core:path/filepath"
import "core:reflect"
import "core:slice"
import "core:strings"
import "core:time"
import "local:/katana/sdl2glue"
import kn "local:katana"
import opal "local:opal"
import "local:opal/components"
import "local:opal/lucide"
import "local:opal/sdl2app"
import tw "local:opal/tailwind_colors"
import "vendor:sdl2"
import stbi "vendor:stb/image"
import stbtt "vendor:stb/truetype"
import "vendor:wgpu"


FILLER_TEXT :: `Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nunc quis malesuada metus, a placerat lacus. Mauris aliquet congue blandit. Praesent elementum efficitur lorem, sed mattis ipsum viverra a. Integer blandit neque eget ultricies commodo. In sapien libero, gravida sit amet egestas quis, pharetra non mi. In nec ligula molestie, placerat dui vitae, ultricies nisl. Curabitur ultrices iaculis urna, in convallis dui dictum id. Nullam suscipit, massa ac venenatis finibus, turpis augue ultrices dolor, at accumsan est sem eu dui. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae; Curabitur sem neque, varius in eros non, vestibulum condimentum ante. In molestie nulla non nulla pulvinar placerat. Nullam sit amet imperdiet turpis.`

Item :: struct {
	using file_info: os.File_Info,
	children:        [dynamic]Item,
	selected:        bool,
}

Preview :: union {
	Text_Preview,
	Image_Preview,
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

Explorer :: struct {
	using app:         sdl2app.App,
	toggle_switch:     bool,
	slider:            f32,
	text:              string,
	cwd:               string,
	last_cwd:          string,
	items:             [dynamic]Item,
	primary_selection: Maybe(string),
	preview:           Preview,
	context_menu:      Maybe(Context_Menu),
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

explorer_set_primary_selection :: proc(self: ^Explorer, name: string) -> (err: os.Error) {
	self.primary_selection = name

	if os.is_dir(name) {
		return os.General_Error.Invalid_File
	}

	file := os.open(name, os.O_RDONLY) or_return
	defer os.close(file)

	switch filepath.ext(name) {
	case ".png", ".jpg", ".jpeg", ".qoi", ".tga", ".bmp":
		if img, err := image.load_from_file(name, {.alpha_add_if_missing}); err == nil {
			defer image.destroy(img)

			shrink_x := max(img.width - 256, 0)
			shrink_y := max(img.height - 256, 0)

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

			self.preview = Image_Preview {
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
				self.preview = Image_Preview {
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
		self.preview = text_preview
	}

	return nil
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

	if sdl2.Init({.VIDEO, .EVENTS}) != 0 {
		panic("Could not initialize SDL3")
	}

	sdl2app.state = new_clone(
	Explorer {
		run = true,
		on_start = proc(app: ^sdl2app.App) {
			app := (^Explorer)(app)
			lucide.load()
			components.theme.icon_font = lucide.font
			opal.set_color(.Selection_Background, tw.SKY_500)
			opal.set_color(.Selection_Foreground, tw.BLACK)
			opal.set_color(.Scrollbar_Background, tw.SLATE_800)
			opal.set_color(.Scrollbar_Foreground, tw.SLATE_500)
			opal.global_ctx.snap_to_pixels = true
			components.theme.font, _ = kn.load_font_from_files(
				"../fonts/Lexend-Regular.png",
				"../fonts/Lexend-Regular.json",
			)
			components.theme.monospace_font, _ = kn.load_font_from_files(
				"../fonts/SpaceMono-Regular.png",
				"../fonts/SpaceMono-Regular.json",
			)
			app.cwd = os.get_current_directory()
			if err := explorer_refresh(app); err != nil {
				fmt.eprintf("Failed to refresh explorer: %v\n", err)
			}
		},
		on_frame = proc(app: ^sdl2app.App) {
			app := (^Explorer)(app)
			using opal, components
			window_radius :=
				app.radius *
				f32(
					i32(
						transmute(sdl2.WindowFlags)sdl2.GetWindowFlags(app.window) >=
						sdl2.WINDOW_MAXIMIZED,
					),
				)

			begin()
			begin_node(
				&{
					sizing = {exact = global_ctx.screen_size},
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
						sizing = {
							fit = {0, 1},
							exact = {0, 20},
							max = INFINITY,
							grow = {true, false},
						},
						content_align = {0, 0.5},
						style = {background = tw.NEUTRAL_800},
					},
				)
				{
					if do_window_button(lucide.ARROW_LEFT, tw.EMERALD_500) {
						explorer_change_folder(app, app.last_cwd)
					}
					if do_window_button(lucide.ARROW_UP, tw.EMERALD_500) {
						explorer_change_folder(
							app,
							app.cwd[:max(strings.last_index_byte(app.cwd, '\\'), 3)],
						)
					}
					add_node(
						&{
							text = app.cwd,
							foreground = theme.color.base_foreground,
							font_size = 14,
							font = &theme.font,
							sizing = {fit = 1},
							padding = {10, 0, 0, 0},
						},
					)
					sdl2app.app_use_node_for_window_grabbing(
						app,
						add_node(&{sizing = {grow = true, max = INFINITY}, interactive = true}).?,
					)
					if do_window_button(lucide.CHEVRON_DOWN, tw.NEUTRAL_500) {
						sdl2.MinimizeWindow(app.window)
					}
					if do_window_button(lucide.CHEVRON_UP, tw.NEUTRAL_500) {
						if .MAXIMIZED in
						   transmute(sdl2.WindowFlags)sdl2.GetWindowFlags(app.window) {
							sdl2.RestoreWindow(app.window)
						} else {
							sdl2.MaximizeWindow(app.window)
						}
					}
					if do_window_button(lucide.X, tw.ROSE_500) {
						app.run = false
					}
				}
				end_node()

				if menu, ok := app.context_menu.?; ok {
					push_id(menu.file)
					defer pop_id()
					menu_root := begin_node(
						&Node_Descriptor {
							layer = 9,
							absolute = true,
							exact_offset = menu.position,
							sizing = {exact = {0, 0}, fit = 1, max = INFINITY},
							padding = 8,
							radius = 10,
							gap = 4,
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
								text = menu.file,
								foreground = tw.WHITE,
								font = &theme.font,
								font_size = 14,
								sizing = {fit = 1},
							},
						)
						begin_node(&{sizing = {fit = 1}, gap = 4})
						{
							{
								btn := components.make_button(lucide.COPY, .Primary)
								btn.font = &theme.icon_font
								if components.add_button(&btn) {
									fmt.eprintln("Not implemented")
								}
							}
							{
								btn := components.make_button(lucide.SCISSORS, .Primary)
								btn.font = &theme.icon_font
								if components.add_button(&btn) {
									fmt.eprintln("Not implemented")
								}
							}
							{
								btn := components.make_button(lucide.CLIPBOARD_PASTE, .Primary)
								btn.font = &theme.icon_font
								if components.add_button(&btn) {
									fmt.eprintln("Not implemented")
								}
							}
							{
								btn := components.make_button(lucide.TEXT_CURSOR_INPUT, .Primary)
								btn.font = &theme.icon_font
								if components.add_button(&btn) {
									fmt.eprintln("Not implemented")
								}
							}
							{
								btn := components.make_button(lucide.SHREDDER, .Primary)
								btn.font = &theme.icon_font
								if components.add_button(&btn) {
									fmt.eprintln("Not implemented")
								}
							}
						}
						end_node()
					}
					end_node()
				}

				begin_node(
					&{
						sizing = {max = INFINITY, grow = true, fit = 1},
						content_align = {0, 0.5},
						style = {background = tw.NEUTRAL_900},
					},
				)
				{
					begin_node(
						&{
							sizing = {
								max = {INFINITY, INFINITY},
								grow = {true, true},
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
						begin_node(&{sizing = {max = INFINITY, grow = true}, padding = 4, gap = 4})
						{
							// File list
							begin_node(
								&{
									sizing = {fit = {1, 0}, max = INFINITY, grow = {true, true}},
									padding = 4,
									vertical = true,
									show_scrollbars = true,
									clip_content = true,
									interactive = true,
									background = tw.NEUTRAL_800,
									radius = 10,
								},
							)
							{
								for &item, i in app.items {
									push_id(i)


									node := begin_node(
										&{
											interactive = true,
											radius = 8,
											padding = {8, 4, 8, 4},
											sizing = {
												fit = 1,
												grow = {true, false},
												max = INFINITY,
											},
											content_align = {0, 0.5},
											gap = 4,
											foreground = tw.BLUE_500 if item.file_info.is_dir else kn.WHITE,
											stroke = tw.BLUE_500,
											stroke_width = f32(i32(item.selected)),
										},
									).?
									{
										if item.is_dir {
											add_node(
												&{
													sizing = {fit = 1},
													text = string_from_rune(lucide.FOLDER),
													font = &theme.icon_font,
													square_fit = true,
													font_size = 16,
													foreground = node.foreground,
												},
											)
										} else if item.file_info.mode == 1049014 {
											add_node(
												&{
													sizing = {fit = 1},
													text = string_from_rune(lucide.FOLDER_SYMLINK),
													font = &theme.icon_font,
													square_fit = true,
													font_size = 16,
													foreground = node.foreground,
												},
											)
										}
										add_node(
											&{
												text = item.file_info.name,
												font = &theme.font,
												font_size = 16,
												sizing = {fit = 1},
												foreground = node.foreground,
											},
										)
										add_node(
											&{sizing = {grow = {true, false}, max = INFINITY}},
										)
										add_node(
											&{
												text = fmt_memory_size(item.file_info.size),
												font = &theme.font,
												font_size = 16,
												sizing = {fit = 1},
												foreground = node.foreground,
											},
										)
										add_node(
											&{
												text = memory_size_suffix(item.file_info.size),
												font = &theme.font,
												font_size = 16,
												sizing = {fit = 1},
												foreground = fade(node.foreground.(kn.Color), 0.5),
											},
										)
									}
									end_node()
									if node.is_hovered && !node.was_hovered {
										node.transitions[0] = 1
									}
									node_update_transition(node, 0, node.is_hovered, 0.1)
									node_update_transition(node, 1, node.is_active, 0.1)
									node.background = kn.fade(
										kn.mix(
											f32(i32(item.selected)) * 0.2,
											tw.NEUTRAL_700,
											tw.BLUE_700,
										),
										max(f32(i32(item.selected)) * 0.2, node.transitions[0]),
									)
									if node.is_active && !node.was_active {
										if node.click_count == 2 {
											if item.file_info.is_dir {
												explorer_change_folder(app, item.file_info.name)
											} else if item.file_info.mode == 1049014 {
												h, _ := os.open(item.file_info.name)
												fi, _ := os.read_dir(h, 1)
												if len(fi) > 0 {
													explorer_change_folder(
														app,
														filepath.dir(fi[0].fullpath),
													)
												}
											} else {
												libc.system(
													fmt.ctprintf(
														`start "" "%s"`,
														item.file_info.name,
													),
												)
											}
										} else {
											if global_ctx.last_mouse_down_button == .Right {
												app.context_menu = Context_Menu {
													position = global_ctx.mouse_position,
													file     = item.file_info.name,
												}
											} else {
												if key_down(.Left_Control) ||
												   key_down(.Right_Control) {
													item.selected = !item.selected
												} else {
													for &item, j in app.items {
														item.selected = false
													}
													item.selected = true
												}
												if !item.file_info.is_dir {
													if err := explorer_set_primary_selection(
														app,
														item.name,
													); err != nil {
														fmt.eprintfln(
															"Failed to set primary selection: %v",
															err,
														)
													}
												}
											}
										}
									}
									pop_id()
								}
							}
							end_node()
							// Preview
							if name, ok := app.primary_selection.?; ok {
								begin_node(
									&{
										sizing = {
											grow = {false, true},
											exact = {400, 0},
											max = {400, INFINITY},
										},
										vertical = true,
										padding = 8,
										background = tw.NEUTRAL_800,
										show_scrollbars = true,
										clip_content = true,
										interactive = true,
										radius = 10,
									},
								)
								{
									switch preview in app.preview {
									case (Text_Preview):
										do_text(
											&{sizing = {grow = true, max = INFINITY, fit = 1}},
											preview.text,
											14,
											&theme.monospace_font,
											tw.WHITE,
										)
									case (Image_Preview):
										add_node(
											&{
												sizing = {
													exact = preview.source.hi - preview.source.lo,
												},
												data = app,
												on_draw = proc(node: ^Node) {
													app := (^Explorer)(node.data)
													kn.add_box(
														node.box,
														4,
														kn.make_atlas_sample(
															app.preview.(Image_Preview).source,
															node.box,
															kn.WHITE,
														),
													)
												},
											},
										)
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

	sdl2app.run(
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

	free(sdl2app.state)
}

begin_section :: proc(name: string, loc := #caller_location) {
	using opal
	push_id(hash_loc(loc))
	begin_node(
		&{
			background = tw.NEUTRAL_800,
			radius = 10,
			vertical = true,
			sizing = {fit = 1, grow = {true, false}, max = INFINITY},
		},
	)
	title_node := begin_node(
		&{
			sizing = {fit = {0, 1}, grow = {true, false}, max = INFINITY},
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
			sizing = {fit = 1},
		},
	)
	add_node(
		&{
			font_size = 14,
			sizing = {fit = 1, exact = {20, 0}, max = INFINITY, grow = {false, true}},
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
				grow = {true, false},
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

		begin_node(&{wrapped = true, sizing = {fit = 1, max = INFINITY, grow = {true, false}}})
		pop_id()
		{
			for len(line) > 0 {
				push_id(i)
				i += 1

				word_end := strings.index_any(line, " ")
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
						interactive = true,
						enable_selection = true,
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

