package components

import ".."

Chip_Descriptor :: struct {
	selected: bool,
}

begin_chip :: proc(descriptor: ^Chip_Descriptor) -> opal.Node_Result {
	using opal
	return begin_node(
		&{
			stroke       = theme.border_color,
			stroke_width = 2,
			padding      = 3,
			gap          = 2,
			// on_animate = proc(self: ^Node) {
			// 	node_update_transition(self, 0, self.is_hovered, theme.animation_time)
			// 	self.background = fade(theme.color.background, self.transitions[0])
			// },
		},
	)
}
