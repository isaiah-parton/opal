package components

import ".."

import tw "../tailwind_colors"

do_menu_item :: proc(label: string, icon: rune, loc := #caller_location) {
	using opal
	push_id(hash(loc))

	begin_node(
		&{
			padding = {3, 3, 12, 3},
			fit = 1,
			spacing = 6,
			max_size = INFINITY,
			grow = {true, false},
			content_align = {0, 0.5},
			is_widget = true,
			inherit_state = true,
			style = {radius = 3},
			on_animate = proc(self: ^Node) {
				using opal
				node_update_transition(self, 0, self.is_hovered, 0.1)
				node_update_transition(self, 1, self.is_active, 0.1)
				self.style.background = fade(
					tw.NEUTRAL_600,
					self.transitions[0] * 0.3 + self.transitions[1] * 0.3,
				)
			},
		},
	)
	do_node(
		&{
			text = string_from_rune(icon),
			fit = 1,
			style = {foreground = tw.NEUTRAL_300, font_size = 14, font = theme.icon_font},
		},
	)
	do_node(&{text = label, fit = 1, style = {font_size = 12, foreground = tw.NEUTRAL_300}})
	end_node()
	pop_id()
}

@(deferred_out = __do_menu)
do_menu :: proc(label: string, loc := #caller_location) -> bool {
	using opal
	push_id(hash(loc))
	node := do_node(
		&{
			padding = 3,
			radius = 3,
			fit = 1,
			text = label,
			font_size = 12,
			is_widget = true,
			on_animate = proc(self: ^Node) {
				self.style.background = fade(
					tw.NEUTRAL_600,
					(self.transitions[0] + self.transitions[1]) * 0.3,
				)
				self.style.foreground =
					tw.BLUE_500 if (self.is_focused || self.has_focused_child) else tw.NEUTRAL_300
				node_update_transition(self, 1, self.is_active, 0)
				node_update_transition(self, 0, self.is_hovered, 0)
				if self.is_hovered && self.parent != nil && self.parent.has_focused_child {
					focus_node(self.id)
				}
			},
		},
	)

	assert(node != nil)

	is_open := node.is_focused | node.has_focused_child | node.was_focused

	if is_open {
		begin_node(
			&{
				owner = node,
				is_root = true,
				node_relative_placement = Node_Relative_Placement {
					node = node,
					relative_offset = {0, 1},
					exact_offset = {-5, 0},
				},
				shadow_size = 5,
				shadow_color = {0, 0, 0, 128},
				bounds = get_screen_box(),
				z_index = 999,
				fit = 1,
				padding = 4,
				radius = 5,
				background = tw.NEUTRAL_900,
				stroke = tw.NEUTRAL_600,
				stroke_width = 1,
				vertical = true,
			},
		)
	}

	pop_id()

	return is_open
}

@(private)
__do_menu :: proc(is_open: bool) {
	using opal
	if is_open {
		end_node()
	}
}

