package file_explorer

import kn "../../katana"
import "../../lucide"
import "../../opal"
import tw "../../tailwind_colors"
import "core:c/libc"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

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
			radius = global_ctx.theme.radius_small,
			padding = {8 + f32(depth) * 20, 4, 8, 4},
			sizing = {fit = 1, grow = {1, 0}, max = INFINITY},
			content_align = {0, 0.5},
			gap = 4,
			foreground = tw.BLUE_700 if self.file_info.is_dir else kn.BLACK,
			stroke = global_ctx.theme.color.border,
			stroke_width = f32(i32(self.selected)) * 2,
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
				sizing = {fit = {1, 1}, grow = {1, 0}, max = INFINITY},
				foreground = node.foreground,
				clip_content = true,
			},
		)
		// add_node(&{sizing = {grow = {1, 0}, max = INFINITY}})
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
		kn.mix(
			f32(i32(self.selected)) * 0.5,
			global_ctx.theme.color.base_strong,
			global_ctx.theme.color.accent,
		),
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

	// Handle click-n-drag
	if !app.dragging &&
	   node.is_active &&
	   linalg.distance(global_ctx.mouse_position, global_ctx.mouse_click_position) > 1 &&
	   global_ctx.last_mouse_down_button == .Left {
		if !multi_select {
			// Select only the hovered item
			for &item, j in app.items {
				item_deselect_children(&item)
				item.selected = false
			}
			self.selected = true
			update_selection = true
		}
		app.dragging = true
	}

	// Handle mouse pressed
	if !app.dragging && node.is_active && !node.was_active {
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

	// Handle mouse relased
	if node.was_active && !node.is_active {
		if node.click_count == 2 {
			// Handle double click
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
				update_selection = true
			}
			if self.file_info.is_dir {
				self.expanded = !self.expanded
				if self.expanded {
					item_load_children(self)
				}
			}
		}
	}
}

