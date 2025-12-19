package opal

Panel_State :: enum {
	None,
	Moving,
	Resizing,
}

Resize :: enum {
	None,
	Near,
	Far,
}

Panel :: struct {
	position:    [2]f32,
	size:        [2]f32,
	min_size:    [2]f32,
	resize_mode: [2]Resize,
	anchor:      [2]f32,
	state:       Panel_State,
	cursor:      Cursor,
}

panel_update :: proc(self: ^Panel, base_node, grab_node: ^Node) {
	ctx := global_ctx

	switch self.state {
	case .None:
		// Resizing
		if base_node != nil {
			if base_node.is_hovered || base_node.has_hovered_child {
				size :: 8
				left_box := Box{base_node.box.lo, {base_node.box.lo.x + size, base_node.box.hi.y}}
				top_box := Box{base_node.box.lo, {base_node.box.hi.x, base_node.box.lo.y + size}}
				right_box := Box {
					{base_node.box.hi.x - size, base_node.box.lo.y},
					{base_node.box.hi.x, base_node.box.hi.y},
				}
				bottom_box := Box {
					{base_node.box.lo.x, base_node.box.hi.y - size},
					{base_node.box.hi.x, base_node.box.hi.y},
				}
				over_left := point_in_box(ctx.mouse_position, left_box)
				over_right := point_in_box(ctx.mouse_position, right_box)
				over_top := point_in_box(ctx.mouse_position, top_box)
				over_bottom := point_in_box(ctx.mouse_position, bottom_box)
				over_left_or_right := over_left || over_right
				over_top_or_bottom := over_top || over_bottom
				self.cursor = .Normal
				if over_left_or_right && over_top_or_bottom {
					if (over_left && over_top) || (over_right && over_bottom) {
						self.cursor = .Resize_NWSE
					} else if (over_right && over_top) || (over_left && over_bottom) {
						self.cursor = .Resize_NESW
					}
				} else {
					if over_left_or_right {
						self.cursor = .Resize_EW
					} else if over_top_or_bottom {
						self.cursor = .Resize_NS
					}
				}
				set_cursor(self.cursor)
				if mouse_pressed(.Left) {
					if over_left_or_right || over_top_or_bottom {
						self.state = .Resizing
						self.resize_mode = {
							Resize(i32(over_left_or_right) + i32(over_right)),
							Resize(i32(over_top_or_bottom) + i32(over_bottom)),
						}
						self.anchor = base_node.box.hi
					}
				}
			}
		}
		if self.state == .None &&
		   (grab_node.is_hovered || grab_node.has_hovered_child) &&
		   mouse_pressed(.Left) {
			self.state = .Moving
			self.anchor = ctx.mouse_position - self.position
		}
	case .Moving:
		if self.state == .Moving {
			set_cursor(.Move)
			self.position = ctx.mouse_position - self.anchor
		}
	case .Resizing:
		for i in 0 ..= 1 {
			switch self.resize_mode[i] {
			case .None:
			case .Near:
				self.position[i] = min(ctx.mouse_position[i], self.anchor[i] - self.min_size[i])
				self.size[i] = self.anchor[i] - self.position[i]
			case .Far:
				self.size[i] = ctx.mouse_position[i] - self.position[i]
			}
		}
		set_cursor(self.cursor)
	}

	if mouse_released(.Left) {
		self.state = .None
	}
}

