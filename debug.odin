package opal

import kn "../katana"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import tw "tailwind_colors"

_BACKGROUND :: tw.NEUTRAL_900
_FOREGROUND :: tw.NEUTRAL_800
_TEXT :: tw.WHITE

Inspector :: struct {
	using panel:    Panel,
	shown:          bool,
	selected_id:    Id,
	inspected_id:   Id,
	inspected_node: Node,
}

inspector_show :: proc(self: ^Inspector) {
	self.min_size = {300, 400}
	self.size = linalg.max(self.size, self.min_size)
	base_node := begin_node(
		&{
			exact_offset = self.position,
			min_size = self.size,
			bounds = get_screen_box(),
			vertical = true,
			padding = 1,
			shadow_size = 10,
			shadow_color = tw.BLACK,
			stroke_width = 2,
			stroke = tw.CYAN_800,
			background = _BACKGROUND,
			z_index = 1,
			radius = 7,
		},
	).?
	total_nodes := len(global_ctx.node_by_id)
	handle_node := begin_node(
		&{
			fit = 1,
			padding = 5,
			style = {background = _FOREGROUND},
			grow = {true, false},
			max_size = INFINITY,
			interactive = true,
			vertical = true,
			data = global_ctx,
			on_draw = proc(self: ^Node) {
				center := self.box.hi - box_height(self.box) / 2
				radius := box_height(self.box) * 0.35
				ctx := (^Context)(self.data)

				kn.add_circle(center, radius, tw.AMBER_500)
				angle: f32 = 0
				radians := (f32(ctx.compute_duration) / f32(ctx.frame_duration)) * math.PI * 2
				kn.add_pie(center, angle, angle + radians, radius, tw.FUCHSIA_500)
				angle += radians
			},
		},
	).?
	{
		desc := Node_Descriptor {
			fit        = 1,
			font_size  = 12,
			foreground = _TEXT,
		}
		desc.text = fmt.tprintf("FPS: %.0f", kn.get_fps())
		add_node(&desc)
		desc.text = fmt.tprintf("Interval time: %v", global_ctx.interval_duration)
		add_node(&desc)
		desc.text = fmt.tprintf("Frame time: %v", global_ctx.frame_duration)
		desc.foreground = tw.AMBER_500
		add_node(&desc)
		desc.foreground = tw.FUCHSIA_500
		desc.text = fmt.tprintf("Compute time: %v", global_ctx.compute_duration)
		add_node(&desc)
		desc.foreground = _TEXT
		desc.text = fmt.tprintf(
			"%i/%i nodes drawn",
			global_ctx.drawn_nodes,
			len(global_ctx.node_by_id),
		)
		add_node(&desc)
	}
	end_node()
	panel_update(self, base_node, handle_node)
	inspector_reset(&global_ctx.inspector)
	inspector_build_tree(&global_ctx.inspector)
	if self.selected_id != 0 {
		begin_node(
			&{
				min_size = {0, 200},
				grow = {true, true},
				padding = 4,
				max_size = INFINITY,
				clip_content = true,
				show_scrollbars = true,
				style = {background = tw.NEUTRAL_950},
				interactive = true,
				vertical = true,
			},
		)
		begin_node(&{grow = {true, false}, fit = 1, max_size = INFINITY, vertical = true})
		add_value_node("Node", &self.inspected_node, type_info_of(Node))
		end_node()
		end_node()
	}
	end_node()

	add_value_node :: proc(name: string, data: rawptr, type_info: ^runtime.Type_Info) {
		expandable: bool
		text: string
		base_type_info := runtime.type_info_base(type_info)
		#partial switch v in base_type_info.variant {
		case (runtime.Type_Info_Struct),
		     (runtime.Type_Info_Dynamic_Array),
		     (runtime.Type_Info_Slice),
		     (runtime.Type_Info_Multi_Pointer):
			expandable = true
		case (runtime.Type_Info_Array):
			if v.count > 4 {
				expandable = true
			} else {
				text = fmt.tprint(any{data = data, id = type_info.id})
			}
		case (runtime.Type_Info_Pointer):
			text = fmt.tprint(any{data = data, id = typeid_of(rawptr)})
		case:
			text = fmt.tprint(any{data = data, id = type_info.id})
		}

		push_id(hash_uintptr(uintptr(data)))
		defer pop_id()

		node := begin_node(
			&{
				max_size = INFINITY,
				grow = {true, false},
				fit = 1,
				padding = 2,
				interactive = true,
				justify_between = true,
			},
		).?
		if expandable {
			add_node(
				&{
					foreground = tw.ORANGE_500,
					font_size = 12,
					text = fmt.tprintf("%c%s", '-' if node.is_toggled else '+', name),
					fit = 1,
				},
			)
		} else {
			add_node(&{foreground = _TEXT, font_size = 12, text = name, fit = 1})
			if text != "" {
				add_node(&{text = text, foreground = tw.INDIGO_600, font_size = 12, fit = 1})
			}
		}
		end_node()
		node.background = fade(tw.NEUTRAL_900, f32(i32(node.is_hovered)))
		if expandable {
			node_update_transition(node, 0, node.is_toggled, 0.2)
			if node.was_active && node.is_hovered && !node.is_active {
				node.is_toggled = !node.is_toggled
			}
			if node.transitions[0] > 0.01 {
				begin_node(
					&{
						padding = {10, 0, 0, 0},
						grow = {true, false},
						max_size = INFINITY,
						fit = {0, ease.quadratic_in_out(node.transitions[0])},
						clip_content = true,
						vertical = true,
					},
				)
				#partial switch v in base_type_info.variant {
				case (runtime.Type_Info_Struct):
					for i in 0 ..< v.field_count {
						push_id(int(i + 1))
						add_value_node(
							v.names[i],
							rawptr(uintptr(data) + v.offsets[i]),
							v.types[i],
						)
						pop_id()
					}
				case (runtime.Type_Info_Dynamic_Array):
					ra := (^runtime.Raw_Dynamic_Array)(data)
					for i in 0 ..< ra.len {
						push_id(int(i + 1))
						add_value_node(
							fmt.tprint(i),
							rawptr(uintptr(data) + uintptr(v.elem_size * i)),
							v.elem,
						)
						pop_id()
					}
				case (runtime.Type_Info_Array):
					for i in 0 ..< v.count {
						push_id(int(i + 1))
						add_value_node(
							fmt.tprint(i),
							rawptr(uintptr(data) + uintptr(v.elem_size * i)),
							v.elem,
						)
						pop_id()
					}
				case (runtime.Type_Info_Slice):
					rs := (^runtime.Raw_Slice)(data)
					for i in 0 ..< rs.len {
						push_id(int(i + 1))
						add_value_node(
							fmt.tprint(i),
							rawptr(uintptr(data) + uintptr(v.elem_size * i)),
							v.elem,
						)
						pop_id()
					}
				}
				end_node()
			}
		}
	}
}

inspector_build_tree :: proc(self: ^Inspector) {
	begin_node(
		&{
			vertical = true,
			max_size = INFINITY,
			grow = true,
			clip_content = true,
			show_scrollbars = true,
			interactive = true,
		},
	)
	for root in global_ctx.roots {
		inspector_build_node_widget(self, root)
	}
	end_node()
}

inspector_reset :: proc(self: ^Inspector) {
	self.inspected_id = 0
}

inspector_build_node_widget :: proc(self: ^Inspector, node: ^Node, depth := 0) {
	assert(depth < MAX_TREE_DEPTH)
	push_id(int(node.id))
	button_node := begin_node(
		&{
			content_align = {0, 0.5},
			gap = 4,
			grow = {true, false},
			max_size = INFINITY,
			padding = {4, 2, 4, 2},
			fit = {0, 1},
			interactive = true,
			group = true,
		},
	).?
	add_node(&{min_size = 14, on_draw = nil if len(node.children) == 0 else proc(self: ^Node) {
				assert(self.parent != nil)
				kn.add_arrow(box_center(self.box), 5, 2, math.PI * 0.5 * ease.cubic_in_out(self.parent.transitions[0]), kn.WHITE)
			}})
	add_node(
		&{
			text = node.text if len(node.text) > 0 else fmt.tprintf("%x", node.id),
			fit = 1,
			style = {
				font_size = 14,
				foreground = tw.EMERALD_500 if self.selected_id == node.id else kn.fade(tw.EMERALD_50, 0.5 + 0.5 * f32(i32(len(node.children) > 0))),
			},
		},
	)
	end_node()
	if button_node.is_hovered {
		self.inspected_id = node.id
		if button_node.was_active && !button_node.is_active {
			button_node.is_toggled = !button_node.is_toggled
		}
	}
	if button_node.is_hovered && mouse_pressed(.Right) {
		if self.selected_id == node.id {
			self.selected_id = 0
		} else {
			self.selected_id = node.id
		}
	}
	button_node.background = kn.fade(
		tw.STONE_600,
		f32(i32(button_node.is_hovered)) * 0.5 + 0.2 * f32(i32(len(node.children) > 0)),
	)
	node_update_transition(button_node, 0, button_node.is_toggled, 0.1)
	if button_node.transitions[0] > 0.01 {
		begin_node(
			&{
				padding = {10, 0, 0, 0},
				grow = {true, false},
				max_size = INFINITY,
				fit = {0, ease.quadratic_in_out(button_node.transitions[0])},
				content_align = {0, 1},
				clip_content = true,
				vertical = true,
			},
		)
		for child in node.children {
			inspector_build_node_widget(self, child, depth + 1)
		}
		end_node()
	}
	pop_id()
}

