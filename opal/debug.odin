package opal

import kn "../katana"
import "../lucide"
import tw "../tailwind_colors"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:slice"
import "core:time"

_BACKGROUND :: tw.NEUTRAL_900
_FOREGROUND :: tw.NEUTRAL_800
_TEXT :: tw.WHITE

Average_Tracker :: struct(T: typeid) {
	total:     T,
	average:   T,
	count:     int,
	timestamp: time.Time,
}

average_tracker_update :: proc(
	self: ^Average_Tracker($T),
	current_value: T,
	period: time.Duration,
) {
	self.total += current_value
	self.count += 1
	if time.since(self.timestamp) > period {
		self.average = self.total / T(self.count)
		self.count = 0
		self.total = 0
		self.timestamp = time.now()
	}
}

Performance_Info :: struct {
	// Additional frame delay
	frame_interval:        time.Duration,

	// Time of last drawn frame
	last_draw_time:        time.Time,

	// Profiling state
	frame_start_time:      time.Time,
	frame_duration:        time.Duration,
	compute_start_time:    time.Time,
	compute_duration:      time.Duration,
	interval_start_time:   time.Time,
	interval_duration:     time.Duration,

	// Debug only.
	avg_frame_duration:    Average_Tracker(time.Duration),
	avg_interval_duration: Average_Tracker(time.Duration),
	avg_compute_duration:  Average_Tracker(time.Duration),
	drawn_nodes:           int,
	sizing_passes:         int,
}

performance_info_solve :: proc(self: ^Performance_Info) {
	average_tracker_update(&self.avg_frame_duration, self.frame_duration, time.Millisecond * 500)
	average_tracker_update(
		&self.avg_interval_duration,
		self.interval_duration,
		time.Millisecond * 500,
	)
	average_tracker_update(
		&self.avg_compute_duration,
		self.compute_duration,
		time.Millisecond * 500,
	)
}

Inspector :: struct {
	using panel:             Panel,

	// Currently shown
	shown:                   bool,

	// width
	width:                   f32,

	// Currently picking a node
	is_selecting:            bool,

	//
	selection_start_time:    time.Time,

	// Selected node for viewing properties
	selected_id:             Id,

	// Selected node for inspection
	inspected_id:            Id,
	inspected_node:          ^Node,
	inspected_node_parents:  [dynamic]Id,
	inspected_time:          time.Time,

	// Hovered node
	hovered_node:            ^Node,
	selected_node:           Node,

	//
	inspected_node_snapshot: Node,

	// Show colored highlights around text nodes to differentiate them
	show_text_widgets:       bool,

	// Show highlights around nodes whose contents are clipped with graphical scissors
	show_clipped_nodes:      bool,

	// Nodes under mouse
	nodes_under_mouse:       [dynamic]^Node,
}

inspector_set_inspected_node :: proc(self: ^Inspector, node: ^Node) {
	assert(node != nil)
	clear(&self.inspected_node_parents)
	parent := node.parent
	for parent != nil {
		append(&self.inspected_node_parents, parent.id)
		parent = parent.parent
	}
	self.inspected_id = node.id
	self.inspected_time = time.now()
}

inspector_activate_mouse_selection :: proc(self: ^Inspector) {
	self.selection_start_time = time.now()
	self.is_selecting = true
}

inspector_update_node_snapshot :: proc(self: ^Inspector) {
	if self.inspected_id != 0 {
		if node, ok := global_ctx.node_by_id[self.inspected_id]; ok {
			self.inspected_node_snapshot = node^
		}
	}
}

inspector_show :: proc(self: ^Inspector) {
	self.min_size = {300, 400}
	self.size = linalg.max(self.size, self.min_size)
	self.width = max(self.width, 300)
	base_node := begin_node(
		&{
			sizing = {fit = {1, 0}, grow = {0, 1}, max = INFINITY, exact = {self.width, 0}},
			vertical = true,
			gap = global_ctx.theme.min_spacing,
			padding = global_ctx.theme.min_spacing,
			background = global_ctx.theme.color.background,
		},
	).?
	total_nodes := len(global_ctx.node_by_id)

	// Analytics card
	handle_node := begin_node(
		&{
			sizing = {fit = 1, grow = {1, 0}, max = INFINITY},
			padding = global_ctx.theme.min_spacing,
			radius = global_ctx.theme.radius_small,
			stroke_width = 2,
			stroke = global_ctx.theme.color.border,
			background = global_ctx.theme.color.accent,
			gap = 5,
			interactive = true,
			vertical = true,
			data = global_ctx,
			on_draw = proc(self: ^Node) {
				// center := self.box.hi - box_height(self.box) / 2
				// radius := box_height(self.box) * 0.35
				// ctx := (^Context)(self.data)

				// kn.add_circle(center, radius, tw.AMBER_500)
				// angle: f32 = 0
				// radians := (f32(ctx.compute_duration) / f32(ctx.frame_duration)) * math.PI * 2
				// kn.add_pie(center, angle, angle + radians, radius, tw.FUCHSIA_500)
				// angle += radians
			},
		},
	).?
	{
		desc := Node_Descriptor {
			sizing = {fit = 1, max = INFINITY},
			font_size = 12,
			foreground = global_ctx.theme.color.base_foreground,
		}
		desc.text = fmt.tprintf("FPS: %.0f", kn.get_fps())
		add_node(&desc)
		desc.text = fmt.tprintf(
			"Interval time: %v",
			global_ctx.performance_info.avg_interval_duration.average,
		)
		add_node(&desc)
		desc.text = fmt.tprintf(
			"Frame time: %v",
			global_ctx.performance_info.avg_frame_duration.average,
		)
		add_node(&desc)
		desc.text = fmt.tprintf(
			"Compute time: %v",
			global_ctx.performance_info.avg_compute_duration.average,
		)
		add_node(&desc)
		desc.foreground = global_ctx.theme.color.base_foreground
		desc.text = fmt.tprintf(
			"%i/%i nodes drawn",
			global_ctx.performance_info.drawn_nodes,
			len(global_ctx.node_by_id),
		)
		add_node(&desc)
		desc.text = fmt.tprintf("Sizing passes: %i", global_ctx.performance_info.sizing_passes)
		add_node(&desc)
	}
	end_node()

	// Options
	{
		if add_button(&{icon = lucide.SQUARE_DASHED_MOUSE_POINTER, label = "Select"}).clicked {
			inspector_activate_mouse_selection(self)
		}
		add_checkbox(&{label = "Text debug", value = &self.show_text_widgets})
		add_checkbox(&{label = "Show clipped nodes", value = &self.show_clipped_nodes})
		add_checkbox(&{label = "Pixel snap", value = &global_ctx.snap_to_pixels})
	}

	inspector_build_tree(&global_ctx.inspector)
	if self.inspected_id != 0 {
		begin_node(
			&{
				sizing = {exact = {0, 200}, grow = 1, max = INFINITY},
				padding = 4,
				clip_content = true,
				show_scrollbars = true,
				interactive = true,
				vertical = true,
			},
		)
		begin_node(&{sizing = {grow = {1, 0}, fit = 1, max = INFINITY}, vertical = true})
		add_value_node("Node", &self.inspected_node_snapshot, type_info_of(Node))
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
				sizing = {max = INFINITY, grow = {1, 0}, fit = 1},
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
					sizing = {fit = 1, max = INFINITY},
				},
			)
		} else {
			add_node(
				&{
					foreground = global_ctx.theme.color.base_foreground,
					font_size = 12,
					text = name,
					sizing = {fit = 1, max = INFINITY},
				},
			)
			if text != "" {
				add_node(
					&{
						text = text,
						foreground = tw.INDIGO_600,
						font_size = 12,
						sizing = {fit = 1, max = INFINITY},
					},
				)
			}
		}
		end_node()
		node.background = fade(global_ctx.theme.color.base_strong, f32(i32(node.is_hovered)))
		if expandable {
			node_update_transition(node, 0, node.is_toggled, 0.2)
			if node.was_active && node.is_hovered && !node.is_active {
				node.is_toggled = !node.is_toggled
			}
			if node.transitions[0] > 0.01 {
				begin_node(
					&{
						padding = {10, 0, 0, 0},
						sizing = {
							grow = {1, 0},
							max = INFINITY,
							fit = {0, ease.quadratic_in_out(node.transitions[0])},
						},
						content_align = {0, 1},
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

inspector_register_node_under_mouse :: proc(self: ^Inspector, node: ^Node) {
	assert(node != nil)
	append(&self.nodes_under_mouse, node)
}

inspector_build_tree :: proc(self: ^Inspector) {
	begin_node(
		&{
			sizing = {max = INFINITY, grow = 1},
			vertical = true,
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
	clear(&self.nodes_under_mouse)
}

inspector_update_mouse_selection :: proc(self: ^Inspector) {
	if !self.is_selecting {
		return
	}

	slice.sort_by(self.nodes_under_mouse[:], proc(a, b: ^Node) -> bool {
		return box_width(a.box) * box_height(a.box) < box_width(b.box) * box_height(b.box)
	})

	if len(self.nodes_under_mouse) > 0 {
		self.hovered_node = self.nodes_under_mouse[0]
	}

	if self.hovered_node != nil {
		self := self.hovered_node
		box := self.box
		padding_paint := kn.paint_index_from_option(Color{0, 120, 255, 100})
		if self.padding.x > 0 {
			kn.add_box(box_cut_left(&box, self.padding.x), paint = padding_paint)
		}
		if self.padding.y > 0 {
			kn.add_box(box_cut_top(&box, self.padding.y), paint = padding_paint)
		}
		if self.padding.z > 0 {
			kn.add_box(box_cut_right(&box, self.padding.z), paint = padding_paint)
		}
		if self.padding.w > 0 {
			kn.add_box(box_cut_bottom(&box, self.padding.w), paint = padding_paint)
		}
		kn.add_box(box, paint = Color{0, 255, 0, 80})
		kn.add_box_lines(self.box, 1, outline = .Outer_Stroke, paint = Color{0, 255, 0, 255})
	}

	if time.since(self.selection_start_time) > time.Millisecond && mouse_pressed(.Left) {
		self.is_selecting = false
		if self.hovered_node != nil {
			inspector_set_inspected_node(self, self.hovered_node)
		}
	}

	if key_pressed(.Escape) || mouse_pressed(.Right) {
		self.is_selecting = false
	}
}

inspector_build_node_widget :: proc(self: ^Inspector, node: ^Node, depth := 0) {
	assert(depth < MAX_TREE_DEPTH)

	ctx := global_ctx

	push_id(int(node.id))
	button_node := begin_node(
		&{
			content_align = {0, 0.5},
			gap = 4,
			sizing = {grow = {1, 0}, max = INFINITY, fit = {0, 1}},
			padding = {4, 2, 4, 2},
			interactive = true,
			group = true,
		},
	).?
	add_node(
		&{sizing = {exact = 14}, on_draw = nil if len(node.children) == 0 else proc(self: ^Node) {
				assert(self.parent != nil)
				kn.add_arrow(box_center(self.box), 5, 2, math.PI * 0.5 * ease.cubic_in_out(self.parent.transitions[0]), global_ctx.theme.color.base_foreground)
			}},
	)
	add_node(
		&{
			text = node.text if len(node.text) > 0 else fmt.tprintf("%x", node.id),
			sizing = {fit = 1, max = INFINITY},
			style = {
				font_size = 14,
				foreground = ctx.theme.color.base_foreground if self.inspected_id == node.id else (tw.EMERALD_700 if self.selected_id == node.id else kn.fade(ctx.theme.color.base_foreground, 0.5 + 0.5 * f32(i32(len(node.children) > 0)))),
			},
		},
	)
	end_node()

	if button_node.was_active && !button_node.is_active {
		if global_ctx.last_mouse_down_button == .Right {
			button_node.is_toggled = !button_node.is_toggled
		}
	}

	if button_node.is_active && !button_node.was_active {
		if global_ctx.last_mouse_down_button == .Left {
			if self.inspected_id == node.id {
				self.inspected_id = 0
			} else {
				self.inspected_id = node.id
			}
		}
	}

	button_node.background =
		tw.BLUE_500 if self.inspected_id == node.id else kn.fade(tw.STONE_600, f32(i32(button_node.is_hovered)) * 0.5 + 0.2 * f32(i32(len(node.children) > 0)))
	node_update_transition(button_node, 0, button_node.is_toggled, 0.1)

	if time.since(self.inspected_time) < time.Millisecond * 200 {
		for id in self.inspected_node_parents {
			if node.id == id {
				button_node.is_toggled = true
				break
			}
		}
	}

	if button_node.transitions[0] > 0.01 {
		begin_node(
			&{
				padding = {10, 0, 0, 0},
				sizing = {
					grow = {1, 0},
					max = INFINITY,
					fit = {0, ease.quadratic_in_out(button_node.transitions[0])},
				},
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

